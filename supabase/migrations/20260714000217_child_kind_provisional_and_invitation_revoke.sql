-- 217: 入園時基本情報(M6) Phase 1 = 在籍種別統一(child_kind)・仮登録(園児名のみ)・招待無効化RPC。
-- 1) children.child_kind 追加('regular'/'temporary'、既存児は全員 regular)
-- 2) gender/birth_date/enrollment_date の nullable 化(仮登録=園児名だけを許容。
--    敬称生成列は else '' で null 安全、197の enrollment_date クリップは GREATEST が null を無視するため無事)
-- 3) create_provisional_child: 入園予定として名前だけで作成(クラス在籍なし=ボード/在園児一覧に出ない)
-- 4) create_child 再定義(p_child_kind 追加。戻り値変更のため drop→create)
-- 5) set_child_kind: 既存児の在籍種別変更
-- 6) revoke_guardian_invitation: pending 招待の無効化(紛失時→再発行は既存createで)
-- 7) fetch_children_for_office_master 再定義(child_kind, enrollment_date を末尾に追加。現行=134版)

-- 1) 在籍種別
alter table children add column if not exists child_kind text not null default 'regular';
alter table children drop constraint if exists children_child_kind_check;
alter table children add constraint children_child_kind_check
  check (child_kind in ('regular','temporary'));
comment on column children.child_kind is '在籍種別: regular=通常在籍 / temporary=一時預かり(M6 Phase1で統一)';

-- 2) 仮登録(園児名のみ)を許容
alter table children alter column gender drop not null;
alter table children alter column birth_date drop not null;
alter table children alter column enrollment_date drop not null;

-- 3) 仮登録RPC(主任以上)。enrollment_status='入園予定'・クラス在籍は作らない。
create or replace function create_provisional_child(
  p_office_id uuid,
  p_full_name text,
  p_name_kana text default null,
  p_planned_start_date date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_child_id uuid;
begin
  if not manages_childcare(p_office_id) then
    raise exception 'not authorized';
  end if;
  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'full name is required';
  end if;

  insert into children (
    office_id, full_name, display_name, name_kana,
    enrollment_date, enrollment_status, child_kind
  ) values (
    p_office_id, trim(p_full_name), trim(p_full_name), nullif(trim(coalesce(p_name_kana,'')), ''),
    p_planned_start_date, '入園予定', 'regular'
  )
  returning id into v_child_id;

  return v_child_id;
end;
$$;

-- 4) create_child 再定義: p_child_kind 追加(一時預かり児も正規登録画面から作れるように)。
drop function if exists create_child(uuid, text, text, text, text, date, uuid, date);

create function create_child(
  p_office_id uuid,
  p_full_name text,
  p_display_name text,
  p_name_kana text,
  p_gender text,
  p_birth_date date,
  p_class_id uuid,
  p_enrollment_start_date date,
  p_child_kind text default 'regular'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_office_id uuid;
  v_child_id uuid;
begin
  if not manages_childcare(p_office_id) then
    raise exception 'not authorized';
  end if;
  if p_full_name is null or length(trim(p_full_name)) = 0 then
    raise exception 'full name is required';
  end if;
  if p_display_name is null or length(trim(p_display_name)) = 0 then
    raise exception 'display name is required';
  end if;
  if p_child_kind not in ('regular','temporary') then
    raise exception 'invalid child kind';
  end if;

  select office_id into v_class_office_id from childcare_classes where id = p_class_id;
  if v_class_office_id is null or v_class_office_id <> p_office_id then
    raise exception 'class does not belong to this office';
  end if;

  insert into children (
    office_id, full_name, display_name, name_kana, gender, birth_date,
    enrollment_date, enrollment_status, child_kind
  ) values (
    p_office_id, p_full_name, p_display_name, p_name_kana, p_gender, p_birth_date,
    p_enrollment_start_date, '在籍中', p_child_kind
  )
  returning id into v_child_id;

  insert into child_class_enrollments (child_id, class_id, effective_start_date, effective_end_date)
  values (v_child_id, p_class_id, p_enrollment_start_date, null);

  return v_child_id;
end;
$$;

-- 5) 在籍種別の変更(主任以上)
create or replace function set_child_kind(p_child_id uuid, p_child_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  if p_child_kind not in ('regular','temporary') then
    raise exception 'invalid child kind';
  end if;
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  update children set child_kind = p_child_kind where id = p_child_id;
end;
$$;

-- 6) 招待の無効化(主任以上・pendingのみ)。再発行は既存 create_guardian_invitation_by_staff を再実行。
create or replace function revoke_guardian_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  select c.office_id, gi.status into v_office_id, v_status
  from guardian_invitations gi
  join children c on c.id = gi.child_id
  where gi.id = p_invitation_id;

  if v_office_id is null then
    raise exception 'invitation not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_status <> 'pending' then
    raise exception 'only pending invitations can be revoked';
  end if;

  update guardian_invitations set status = 'revoked' where id = p_invitation_id;
end;
$$;

-- 7) 園児マスタRPC再定義(現行=134版に child_kind / enrollment_date を末尾追加。戻り型変更のため drop→create)
drop function if exists fetch_children_for_office_master(uuid);

create function fetch_children_for_office_master(p_office_id uuid)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  full_name text,
  name_kana text,
  gender text,
  birth_date date,
  enrollment_status text,
  withdrawal_date date,
  class_id uuid,
  class_name text,
  class_family_daily_report_required boolean,
  family_daily_report_required_from date,
  family_daily_report_required_until date,
  child_kind text,
  enrollment_date date
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    c.id, c.display_name, c.honorific_suffix_resolved, c.full_name, c.name_kana,
    c.gender, c.birth_date, c.enrollment_status, c.withdrawal_date,
    cc.id, cc.class_name, cc.family_daily_report_required,
    c.family_daily_report_required_from, c.family_daily_report_required_until,
    c.child_kind, c.enrollment_date
  from children c
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  where c.office_id = p_office_id
  order by cc.class_name, c.display_name;
end;
$$;
