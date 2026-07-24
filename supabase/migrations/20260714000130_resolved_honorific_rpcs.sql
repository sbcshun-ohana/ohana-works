-- 子ども名を返す既存RPC群を、honorific_suffix(生の上書き値)ではなく
-- honorific_suffix_resolved(性別既定込みで解決済み)を返すよう修正する。
-- JSON上のキー名はhonorific_suffixのまま維持するため、呼び出し側(admin_web/Flutter)の
-- コード変更は不要。あわせてfetch_class_childrenからは廃止したfamily_daily_report_required_override
-- 列を除去する(欠席選択ページのトグルは園児マスタ画面に移管したため)。

drop function if exists fetch_class_children(uuid, date);

create function fetch_class_children(p_class_id uuid, p_business_date date)
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
    c.id, c.display_name, c.honorific_suffix_resolved, c.gender, c.enrollment_status,
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
    cdc.id, c.id, c.display_name, c.honorific_suffix_resolved, cc.class_name,
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
    c.id, c.display_name, c.honorific_suffix_resolved, cc.class_name,
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

drop function if exists fetch_daily_board_for_office(uuid, date);

create function fetch_daily_board_for_office(p_office_id uuid, p_business_date date)
returns table (
  child_id uuid,
  display_name text,
  honorific_suffix text,
  class_name text,
  status text,
  last_event_type text,
  last_event_at timestamptz,
  family_daily_report_status text,
  temperature numeric,
  has_pickup_change boolean,
  pickup_person_name text,
  pickup_person_relationship text,
  pickup_time_from time,
  pickup_time_to time
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
    c.id, c.display_name, c.honorific_suffix_resolved, cc.class_name,
    coalesce(dcs.status, 'not_arrived'),
    cae.event_type, cae.occurred_at,
    fdr.status,
    fdr.temperature,
    (fdr.pickup_person_name is not null),
    fdr.pickup_person_name,
    fdr.pickup_person_relationship,
    fdr.pickup_time_from,
    fdr.pickup_time_to
  from children c
  join child_class_enrollments cce on cce.child_id = c.id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  join childcare_classes cc on cc.id = cce.class_id
  left join daily_child_status dcs on dcs.child_id = c.id and dcs.business_date = p_business_date
  left join child_attendance_events cae on cae.id = dcs.last_event_id
  left join family_daily_reports fdr on fdr.child_id = c.id and fdr.business_date = p_business_date
  where c.office_id = p_office_id and c.enrollment_status <> '退園済み'
  order by cc.class_name, c.display_name;
end;
$$;

-- fetch_ai_allowed_context: 手動でcoalesce+caseしていた敬称解決を生成列参照に単純化する
-- (ロジックは変えず、v_honorific_suffix/v_genderの手動計算箇所のみ生成列参照に置き換える)。
create or replace function fetch_ai_allowed_context(p_child_id uuid, p_business_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_display_name text;
  v_effective_honorific text;
  v_class_id uuid;
  v_class_name text;
  v_age_group text;
  v_today_activity jsonb;
  v_today_contact jsonb;
  v_notice_labels text[];
  v_recent_contacts jsonb;
  v_office_tone_settings jsonb;
begin
  select office_id, display_name, honorific_suffix_resolved
    into v_office_id, v_display_name, v_effective_honorific
  from children where id = p_child_id;

  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  select cce.class_id, cc.class_name, cc.age_group
    into v_class_id, v_class_name, v_age_group
  from child_class_enrollments cce
  join childcare_classes cc on cc.id = cce.class_id
  where cce.child_id = p_child_id
    and cce.effective_start_date <= p_business_date
    and (cce.effective_end_date is null or cce.effective_end_date >= p_business_date)
  order by cce.effective_start_date desc
  limit 1;

  select jsonb_build_object(
    'today_theme', cda.today_theme,
    'activity_content', cda.activity_content,
    'class_overview', cda.class_overview,
    'class_announcement', cda.class_announcement,
    'other_notes', cda.other_notes
  ) into v_today_activity
  from class_daily_activities cda
  where cda.class_id = v_class_id and cda.business_date = p_business_date;

  select jsonb_build_object(
    'guardian_message', cdc.guardian_message,
    'child_today_notes', cdc.child_today_notes,
    'free_notes', cdc.free_notes
  ) into v_today_contact
  from child_daily_contacts cdc
  where cdc.child_id = p_child_id and cdc.business_date = p_business_date;

  select coalesce(array_agg(inm.label order by inm.sort_order), array[]::text[])
    into v_notice_labels
  from child_daily_contacts cdc
  join child_daily_contact_notice_checks cdcnc on cdcnc.contact_id = cdc.id
  join individual_notice_masters inm on inm.id = cdcnc.notice_master_id
  where cdc.child_id = p_child_id and cdc.business_date = p_business_date;

  select coalesce(jsonb_agg(jsonb_build_object('business_date', x.business_date, 'text', x.current_text) order by x.business_date desc), '[]'::jsonb)
    into v_recent_contacts
  from (
    select business_date, current_text
    from child_daily_contacts
    where child_id = p_child_id
      and status = 'approved'
      and business_date >= p_business_date - 7
      and business_date < p_business_date
      and current_text is not null
  ) x;

  select tone_settings into v_office_tone_settings
  from ai_style_profiles
  where scope_type = 'office' and scope_id = v_office_id;

  return jsonb_build_object(
    'display_name', v_display_name,
    'honorific_suffix', v_effective_honorific,
    'class_name', v_class_name,
    'age_group', v_age_group,
    'today_input', jsonb_build_object(
      'class_activity', v_today_activity,
      'child_contact', v_today_contact,
      'individual_notices', to_jsonb(v_notice_labels)
    ),
    'recent_contacts', v_recent_contacts,
    'office_tone_settings', coalesce(v_office_tone_settings, '{}'::jsonb)
  );
end;
$$;
