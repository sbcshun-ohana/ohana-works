-- 保護者アプリ Phase A 修正: pgcrypto関数のsearch_path不足を解消
--
-- 不具合: create_guardian_invitation_by_staff/by_guardian/accept_guardian_invitationは
-- gen_random_bytes()/digest()(pgcrypto)を使うが、これらはSupabase管理下のPostgresでは
-- publicではなくextensionsスキーマにインストールされている。関数のsearch_pathがpublicの
-- みだったため「function gen_random_bytes(integer) does not exist」で例外になっていた
-- (ダミーデータ検証で発見)。search_pathにextensionsを追加して解消する。

create or replace function create_guardian_invitation_by_staff(
  p_child_id uuid,
  p_role text,
  p_ttl_hours int default 72
)
returns table (invitation_id uuid, token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_office_id uuid;
  v_token text;
  v_token_hash text;
  v_invitation_id uuid;
  v_expires_at timestamptz;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if p_role not in ('primary', 'additional') then
    raise exception 'invalid role';
  end if;

  v_token := encode(gen_random_bytes(24), 'base64');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');
  v_expires_at := now() + (p_ttl_hours || ' hours')::interval;

  insert into guardian_invitations (child_id, role, invited_by_employee_id, token_hash, expires_at)
  values (p_child_id, p_role, my_employee_id(), v_token_hash, v_expires_at)
  returning id into v_invitation_id;

  return query select v_invitation_id, v_token, v_expires_at;
end;
$$;

create or replace function create_guardian_invitation_by_guardian(
  p_child_id uuid,
  p_role text,
  p_ttl_hours int default 72
)
returns table (invitation_id uuid, token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token text;
  v_token_hash text;
  v_invitation_id uuid;
  v_expires_at timestamptz;
begin
  if not guardian_is_primary_for_child(p_child_id) then
    raise exception 'not authorized: only a primary guardian can invite others';
  end if;
  if p_role not in ('primary', 'additional') then
    raise exception 'invalid role';
  end if;
  if p_role = 'primary' and (
    select count(*) from guardian_child_links where child_id = p_child_id and role = 'primary'
  ) >= 2 then
    raise exception 'primary guardian limit (2) already reached for this child';
  end if;

  v_token := encode(gen_random_bytes(24), 'base64');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');
  v_expires_at := now() + (p_ttl_hours || ' hours')::interval;

  insert into guardian_invitations (child_id, role, invited_by_guardian_id, token_hash, expires_at)
  values (p_child_id, p_role, my_guardian_id(), v_token_hash, v_expires_at)
  returning id into v_invitation_id;

  return query select v_invitation_id, v_token, v_expires_at;
end;
$$;

create or replace function accept_guardian_invitation(
  p_token text,
  p_name text,
  p_name_kana text default null,
  p_phone text default null,
  p_email text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_token_hash text;
  v_invitation guardian_invitations%rowtype;
  v_guardian_id uuid;
  v_auth_user_id uuid := auth.uid();
begin
  if v_auth_user_id is null then
    raise exception 'authentication required before accepting an invitation';
  end if;

  v_token_hash := encode(digest(p_token, 'sha256'), 'hex');
  select * into v_invitation from guardian_invitations where token_hash = v_token_hash for update;

  if v_invitation.id is null then
    raise exception 'invalid invitation token';
  end if;
  if v_invitation.status <> 'pending' then
    raise exception 'invitation is % and cannot be accepted', v_invitation.status;
  end if;
  if v_invitation.expires_at < now() then
    update guardian_invitations set status = 'expired' where id = v_invitation.id;
    raise exception 'invitation has expired';
  end if;
  if v_invitation.role = 'primary' and (
    select count(*) from guardian_child_links where child_id = v_invitation.child_id and role = 'primary'
  ) >= 2 then
    raise exception 'primary guardian limit (2) already reached for this child';
  end if;

  select id into v_guardian_id from guardians where auth_user_id = v_auth_user_id;
  if v_guardian_id is null then
    insert into guardians (auth_user_id, name, name_kana, phone, email)
    values (v_auth_user_id, p_name, p_name_kana, p_phone, p_email)
    returning id into v_guardian_id;
  end if;

  insert into guardian_child_links (guardian_id, child_id, role)
  values (v_guardian_id, v_invitation.child_id, v_invitation.role)
  on conflict (guardian_id, child_id) do nothing;

  update guardian_invitations
  set status = 'accepted', accepted_by_guardian_id = v_guardian_id, accepted_at = now()
  where id = v_invitation.id;

  return v_guardian_id;
end;
$$;
