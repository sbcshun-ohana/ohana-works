-- 保育業務 Phase1: admin_web向け一覧取得RPC群
-- 単純なSELECTはRLSに任せるが、施設横断の集計・結合・機能フラグ判定を要するものはRPC化する。

-- 機能フラグの実効判定(職員個別オーバーライド > 施設オーバーライド > 既定値)。
create or replace function is_childcare_enabled_for_office(p_office_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select enabled from feature_flag_employee_overrides
     where feature_key = 'childcare_operations' and employee_id = my_employee_id()),
    (select enabled from feature_flag_office_overrides
     where feature_key = 'childcare_operations' and office_id = p_office_id),
    (select default_enabled from feature_flags where feature_key = 'childcare_operations'),
    false
  );
$$;

-- 保育業務メニュー表示可否・施設選択用: 機能が有効かつ自分がアクセスできる施設一覧。
create or replace function fetch_my_childcare_offices()
returns table (office_id uuid, office_name text, is_manager boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
  select o.id, o.name, manages_childcare(o.id)
  from offices o
  where is_childcare_enabled_for_office(o.id) and has_childcare_office_access(o.id)
  order by o.name;
end;
$$;

create or replace function fetch_childcare_classes(p_office_id uuid)
returns table (class_id uuid, class_name text, age_group text, school_year int)
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
  select cc.id, cc.class_name, cc.age_group, cc.school_year
  from childcare_classes cc
  where cc.office_id = p_office_id and cc.is_active and has_childcare_class_access(cc.id)
  order by cc.class_name;
end;
$$;

-- 欠席チェック画面: クラス内の在籍園児と当日の出欠状態。
create or replace function fetch_class_children(p_class_id uuid, p_business_date date)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  gender text,
  enrollment_status text,
  is_absent boolean,
  absence_reason text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_class_access(p_class_id) then
    raise exception 'not authorized';
  end if;

  return query
  select
    c.id, c.display_name, c.honorific_suffix, c.gender, c.enrollment_status,
    coalesce(cda.is_absent, false), cda.absence_reason
  from child_class_enrollments cce
  join children c on c.id = cce.child_id
  left join child_daily_attendance cda on cda.child_id = c.id and cda.business_date = p_business_date
  where cce.class_id = p_class_id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
    and c.enrollment_status <> '退園済み'
  order by c.display_name;
end;
$$;

-- クラス活動 入力・申請・承認画面: 施設内の全クラスの当日分(未着手はactivity_id=null)。
create or replace function fetch_class_activities_for_office(p_office_id uuid, p_business_date date)
returns table (
  activity_id uuid,
  class_id uuid,
  class_name text,
  assignee_employee_id uuid,
  assignee_name text,
  status text,
  today_theme text,
  activity_content text,
  class_overview text,
  class_announcement text,
  other_notes text,
  submitted_at timestamptz,
  rejected_reason text
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
    cda.id, cc.id, cc.class_name,
    cda.assignee_employee_id, e.name,
    cda.status, cda.today_theme, cda.activity_content, cda.class_overview,
    cda.class_announcement, cda.other_notes, cda.submitted_at, cda.rejected_reason
  from childcare_classes cc
  left join class_daily_activities cda on cda.class_id = cc.id and cda.business_date = p_business_date
  left join employees e on e.id = cda.assignee_employee_id
  where cc.office_id = p_office_id and cc.is_active
  order by cc.class_name;
end;
$$;

-- 連絡帳 一覧・承認・差し戻し・コピー画面: 施設内の在籍園児の当日分(未着手はcontact_id=null)。
create or replace function fetch_daily_contacts_for_office(p_office_id uuid, p_business_date date)
returns table (
  contact_id uuid,
  child_id uuid,
  child_display_name text,
  child_honorific_suffix text,
  class_name text,
  assignee_employee_id uuid,
  assignee_name text,
  status text,
  guardian_message text,
  child_today_notes text,
  free_notes text,
  ai_generated_text text,
  current_text text,
  admin_comment text,
  rejected_reason text,
  submitted_at timestamptz,
  approved_at timestamptz,
  copied_at timestamptz,
  is_absent boolean
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
    cdc.id, c.id, c.display_name, c.honorific_suffix, cc.class_name,
    cdc.assignee_employee_id, e.name,
    cdc.status, cdc.guardian_message, cdc.child_today_notes, cdc.free_notes,
    cdc.ai_generated_text, cdc.current_text, cdc.admin_comment, cdc.rejected_reason,
    cdc.submitted_at, cdc.approved_at, cdc.copied_at,
    coalesce(cda.is_absent, false)
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  join childcare_classes cc on cc.id = cce.class_id
  left join child_daily_contacts cdc on cdc.child_id = c.id and cdc.business_date = p_business_date
  left join employees e on e.id = cdc.assignee_employee_id
  left join child_daily_attendance cda on cda.child_id = c.id and cda.business_date = p_business_date
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by cc.class_name, c.display_name;
end;
$$;

-- 担当者選択ドロップダウン用: 施設に所属する在籍職員一覧。
create or replace function fetch_childcare_office_staff(p_office_id uuid)
returns table (employee_id uuid, name text)
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
  select distinct e.id, e.name
  from employees e
  join employee_office_assignments eoa on eoa.employee_id = e.id
  where eoa.office_id = p_office_id
    and eoa.start_date <= current_date
    and (eoa.end_date is null or eoa.end_date >= current_date)
    and e.resignation_date is null
  order by e.name;
end;
$$;

-- 園児別担当者割当画面: 施設内の在籍園児と現在の担当者。
create or replace function fetch_children_for_office(p_office_id uuid)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  class_name text,
  current_assignee_employee_id uuid,
  current_assignee_name text,
  enrollment_status text
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
    c.id, c.display_name, c.honorific_suffix, cc.class_name,
    cca.assigned_employee_id, e.name, c.enrollment_status
  from children c
  left join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= current_date
    and (cce.effective_end_date is null or cce.effective_end_date >= current_date)
  left join childcare_classes cc on cc.id = cce.class_id
  left join child_contact_assignments cca on cca.child_id = c.id and cca.effective_end_date is null
  left join employees e on e.id = cca.assigned_employee_id
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by c.display_name;
end;
$$;
