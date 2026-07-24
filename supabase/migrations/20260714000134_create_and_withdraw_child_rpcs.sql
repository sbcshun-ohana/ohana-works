-- 園児マスタ: 新規園児登録・退園処理のRPC。
-- 現状SQL依存だった園児登録・異動・退園のうち、新規登録と退園をadmin_web UIから
-- 行えるようにする(P1課題「園児登録・異動・退園のadmin_web UI」の一部着手)。

create or replace function create_child(
  p_office_id uuid,
  p_full_name text,
  p_display_name text,
  p_name_kana text,
  p_gender text,
  p_birth_date date,
  p_class_id uuid,
  p_enrollment_start_date date
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

  select office_id into v_class_office_id from childcare_classes where id = p_class_id;
  if v_class_office_id is null or v_class_office_id <> p_office_id then
    raise exception 'class does not belong to this office';
  end if;

  insert into children (
    office_id, full_name, display_name, name_kana, gender, birth_date,
    enrollment_date, enrollment_status
  ) values (
    p_office_id, p_full_name, p_display_name, p_name_kana, p_gender, p_birth_date,
    p_enrollment_start_date, '在籍中'
  )
  returning id into v_child_id;

  insert into child_class_enrollments (child_id, class_id, effective_start_date, effective_end_date)
  values (v_child_id, p_class_id, p_enrollment_start_date, null);

  return v_child_id;
end;
$$;

create or replace function withdraw_child(p_child_id uuid, p_withdrawal_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  update children
  set enrollment_status = '退園済み', withdrawal_date = p_withdrawal_date
  where id = p_child_id;

  update child_class_enrollments
  set effective_end_date = p_withdrawal_date
  where child_id = p_child_id and effective_end_date is null;
end;
$$;

-- 園児マスタ一覧に正式氏名・ふりがな・退園日を追加する。
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
  family_daily_report_required_until date
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
    c.family_daily_report_required_from, c.family_daily_report_required_until
  from children c
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  where c.office_id = p_office_id
  order by cc.class_name, c.display_name;
end;
$$;
