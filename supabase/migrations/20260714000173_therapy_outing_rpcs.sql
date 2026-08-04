-- 療育外出 §5: admin_web/キオスク支援RPC。権限(2026-08-04確定):
--   事業者マスタ=統括園長以上(is_executive_or_system_admin)、
--   対象児設定・QR発行/revoke・記録の手動修正=主任以上(manages_childcare on 児の施設)。
-- QR発行は生tokenを1回だけ返し、token_hash のみ保存(guardian QR同型)。修正は上書きせず
-- staff_manual イベントを追記(訂正履歴で辿る)。

-- 事業者マスタ(統括園長以上)
create or replace function create_therapy_provider(p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_executive_or_system_admin() then raise exception 'not authorized'; end if;
  insert into therapy_providers(name) values (p_name) returning id into v_id;
  return v_id;
end; $$;

create or replace function update_therapy_provider(p_id uuid, p_name text, p_is_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_executive_or_system_admin() then raise exception 'not authorized'; end if;
  update therapy_providers set name = p_name, is_active = p_is_active where id = p_id;
end; $$;

-- 対象児設定(主任以上)。複数行可。期間重複は EXCLUDE(171)で拒否。
create or replace function add_child_therapy_setting(
  p_child_id uuid, p_provider_id uuid, p_start_date date, p_end_date date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  insert into child_therapy_settings(child_id, provider_id, start_date, end_date, created_by)
  values (p_child_id, p_provider_id, p_start_date, p_end_date, my_employee_id())
  returning id into v_id;
  return v_id;
end; $$;

create or replace function update_child_therapy_setting(p_id uuid, p_start_date date, p_end_date date)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select c.office_id into v_office from child_therapy_settings s join children c on c.id = s.child_id where s.id = p_id;
  if v_office is null then raise exception 'setting not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  update child_therapy_settings set start_date = p_start_date, end_date = p_end_date where id = p_id;
end; $$;

create or replace function delete_child_therapy_setting(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select c.office_id into v_office from child_therapy_settings s join children c on c.id = s.child_id where s.id = p_id;
  if v_office is null then raise exception 'setting not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  delete from child_therapy_settings where id = p_id;
end; $$;

-- QR発行(主任以上)。同一児×事業者の既存有効QRをrevokeし、新規発行。生tokenを1回返す。
create or replace function issue_therapy_qr(p_child_id uuid, p_provider_id uuid)
returns table (qr_id uuid, token text)
language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_token text; v_hash text; v_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  update therapy_outing_qr_codes set revoked_at = now()
  where child_id = p_child_id and provider_id = p_provider_id and revoked_at is null;

  v_token := encode(gen_random_bytes(24), 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');
  insert into therapy_outing_qr_codes(child_id, provider_id, token_hash, issued_by)
  values (p_child_id, p_provider_id, v_hash, my_employee_id())
  returning id into v_id;

  qr_id := v_id; token := v_token; return next;
end; $$;

create or replace function revoke_therapy_qr(p_qr_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select c.office_id into v_office from therapy_outing_qr_codes q join children c on c.id = q.child_id where q.id = p_qr_id;
  if v_office is null then raise exception 'qr not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  update therapy_outing_qr_codes set revoked_at = now() where id = p_qr_id and revoked_at is null;
end; $$;

-- 記録の手動追加・修正(主任以上)。上書きせず staff_manual イベントを追記(訂正履歴)。
create or replace function record_therapy_event_manual(
  p_child_id uuid, p_provider_id uuid, p_event_type text, p_occurred_at timestamptz, p_correction_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_id uuid;
begin
  if p_event_type not in ('out', 'return') then raise exception 'invalid event_type'; end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  insert into therapy_outing_events(child_id, provider_id, event_type, occurred_at, source, recorded_by, correction_note)
  values (p_child_id, p_provider_id, p_event_type, p_occurred_at, 'staff_manual', my_employee_id(), p_correction_note)
  returning id into v_id;
  return v_id;
end; $$;

-- 記録一覧(admin_web・月次)。施設×期間×(任意)園児。out/returnのペアリングはクライアント側。
create or replace function fetch_therapy_records(
  p_office_id uuid, p_start_date date, p_end_date date, p_child_id uuid default null)
returns table (
  event_id uuid, child_id uuid, display_name text, honorific_suffix text,
  provider_id uuid, provider_name text, event_type text, occurred_at timestamptz,
  source text, correction_note text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
  select e.id, c.id, c.display_name, c.honorific_suffix_resolved,
         tp.id, tp.name, e.event_type, e.occurred_at, e.source, e.correction_note
  from therapy_outing_events e
  join children c on c.id = e.child_id
  join therapy_providers tp on tp.id = e.provider_id
  where c.office_id = p_office_id
    and (e.occurred_at at time zone 'Asia/Tokyo')::date between p_start_date and p_end_date
    and (p_child_id is null or e.child_id = p_child_id)
  order by c.display_name, e.occurred_at;
end; $$;
