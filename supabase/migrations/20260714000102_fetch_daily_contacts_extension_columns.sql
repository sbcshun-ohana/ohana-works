-- 保護者アプリ Phase A: fetch_daily_contacts_for_office(Phase1で定義済み)に
-- child_daily_contacts拡張列(20260714000087: 午睡/排泄/食事/検温/入浴)を追加する。
--
-- RETURNS TABLEの列構成を変更するため、CREATE OR REPLACEでは対応できず
-- DROP FUNCTIONしてから再作成する。既存の呼び出し元(admin_web)は
-- 新しく返る列を無視すれば従来通り動作するため、破壊的変更ではない。

drop function if exists fetch_daily_contacts_for_office(uuid, date);

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
  is_absent boolean,
  nap_periods jsonb,
  toileting_records jsonb,
  meal_completion_pct int,
  meal_free_note text,
  temperature numeric,
  temperature_measured_at time,
  bath_taken boolean
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
    coalesce(cda.is_absent, false),
    cdc.nap_periods, cdc.toileting_records, cdc.meal_completion_pct, cdc.meal_free_note,
    cdc.temperature, cdc.temperature_measured_at, cdc.bath_taken
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
