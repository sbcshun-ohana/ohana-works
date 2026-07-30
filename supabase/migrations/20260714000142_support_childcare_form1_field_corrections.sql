-- Phase 3(支援保育事業): 実機確認で判明した様式1・様式2フォームの項目不一致を修正。
-- 原本xlsxをセル単位で再確認した結果:
--   - support_childcare_form1.class_size_3/4/5 は実際のセルに対応がなく(3・4・5歳児クラスの
--     総人数は既存の在籍データから自動把握できるため、様式1に手入力欄は存在しない)、削除する
--   - 職員数(F9/F10/F11)・備考(G9:H9等)は3・4・5歳児クラスごとに別々の入力欄であり、
--     単一の集計欄ではなかった。staff_count/notesを削除し、staff_count_3/4/5・notes_3/4/5に置換
--   - 関係機関との連携で「児童発達支援事業所に通っている」を選ぶ場合のみ「事業所名」欄
--     (N54セル)が必要。agency_nameを追加
--   - 保護者との連携の「送迎時の会話」は正式な面談記録として認められないため、
--     meeting_type列自体を廃止し、常に正式面談として記録する

alter table support_childcare_form1
  drop column class_size_3,
  drop column class_size_4,
  drop column class_size_5,
  drop column staff_count,
  drop column notes,
  add column staff_count_3 int,
  add column staff_count_4 int,
  add column staff_count_5 int,
  add column notes_3 text,
  add column notes_4 text,
  add column notes_5 text;

alter table support_childcare_agency_links
  add column agency_name text;

alter table support_childcare_guardian_meetings
  drop column meeting_type;

-- update_support_childcare_form1: パラメータ構成が変わるため再作成
drop function if exists update_support_childcare_form1(
  uuid, date, int, int, int, int, int, int, int, text, uuid, text, text, text, text
);

create or replace function update_support_childcare_form1(
  p_application_id uuid,
  p_recorded_on date,
  p_extra_staff_count_3 int, p_extra_staff_count_4 int, p_extra_staff_count_5 int,
  p_staff_count_3 int, p_staff_count_4 int, p_staff_count_5 int,
  p_notes_3 text, p_notes_4 text, p_notes_5 text,
  p_policy_stance_item_id uuid, p_policy_target_month text,
  p_policy_no_extra_staff_reason text, p_policy_no_application_reason text,
  p_subsidy_expected_effect text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_status text;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;
  select status into v_status from support_childcare_applications where id = p_application_id;
  if v_status in ('finalized', 'released', 'superseded', 'archived') then
    raise exception 'application is % and cannot be edited', v_status;
  end if;

  update support_childcare_form1 set
    recorded_on = p_recorded_on,
    extra_staff_count_3 = p_extra_staff_count_3, extra_staff_count_4 = p_extra_staff_count_4,
    extra_staff_count_5 = p_extra_staff_count_5,
    staff_count_3 = p_staff_count_3, staff_count_4 = p_staff_count_4, staff_count_5 = p_staff_count_5,
    notes_3 = p_notes_3, notes_4 = p_notes_4, notes_5 = p_notes_5,
    policy_stance_item_id = p_policy_stance_item_id, policy_target_month = p_policy_target_month,
    policy_no_extra_staff_reason = p_policy_no_extra_staff_reason,
    policy_no_application_reason = p_policy_no_application_reason,
    subsidy_expected_effect = p_subsidy_expected_effect
  where application_id = p_application_id;
end;
$$;

-- fetch_support_childcare_application_detail: 戻り値の列構成が変わるため再作成
drop function if exists fetch_support_childcare_application_detail(uuid);

create or replace function fetch_support_childcare_application_detail(p_application_id uuid)
returns table (
  application_id uuid, status text, child_name text,
  form1_id uuid, form1_recorded_on date,
  form1_extra_staff_count_3 int, form1_extra_staff_count_4 int, form1_extra_staff_count_5 int,
  form1_staff_count_3 int, form1_staff_count_4 int, form1_staff_count_5 int,
  form1_notes_3 text, form1_notes_4 text, form1_notes_5 text,
  form1_policy_stance_item_id uuid, form1_policy_target_month text,
  form1_policy_no_extra_staff_reason text, form1_policy_no_application_reason text,
  form1_subsidy_expected_effect text,
  form2_id uuid, form2_annual_goal text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_office_id uuid;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not (has_childcare_office_access(v_office_id) or is_support_childcare_office_approver(v_office_id)) then
    raise exception 'not authorized';
  end if;

  return query
  select
    a.id, a.status, ch.display_name,
    f1.id, f1.recorded_on,
    f1.extra_staff_count_3, f1.extra_staff_count_4, f1.extra_staff_count_5,
    f1.staff_count_3, f1.staff_count_4, f1.staff_count_5,
    f1.notes_3, f1.notes_4, f1.notes_5,
    f1.policy_stance_item_id, f1.policy_target_month,
    f1.policy_no_extra_staff_reason, f1.policy_no_application_reason,
    f1.subsidy_expected_effect,
    f2.id, f2.annual_goal
  from support_childcare_applications a
  join support_childcare_candidates cand on cand.id = a.candidate_id
  join children ch on ch.id = cand.child_id
  left join support_childcare_form1 f1 on f1.application_id = a.id
  left join support_childcare_form2 f2 on f2.application_id = a.id
  where a.id = p_application_id;
end;
$$;

-- record_support_childcare_agency_link: 事業所名パラメータを追加するため再作成
drop function if exists record_support_childcare_agency_link(
  uuid, text, text, date, date, text, text, text
);

create or replace function record_support_childcare_agency_link(
  p_application_id uuid, p_agency_type text, p_contact_person text,
  p_consultation_date date, p_enrollment_start_date date, p_agency_name text, p_frequency text,
  p_content text, p_support_outcome text
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_id uuid;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_agency_links (
    application_id, agency_type, contact_person, consultation_date, enrollment_start_date,
    agency_name, frequency, content, support_outcome, recorded_by
  ) values (
    p_application_id, p_agency_type, p_contact_person, p_consultation_date, p_enrollment_start_date,
    p_agency_name, p_frequency, p_content, p_support_outcome, my_employee_id()
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- record_support_childcare_guardian_meeting: meeting_typeパラメータを削除するため再作成
drop function if exists record_support_childcare_guardian_meeting(
  uuid, date, text, text, text, text
);

create or replace function record_support_childcare_guardian_meeting(
  p_application_id uuid, p_meeting_date date,
  p_attendee text, p_content text, p_guardian_intention text
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid;
  v_id uuid;
begin
  v_office_id := support_childcare_application_office_id(p_application_id);
  if v_office_id is null then
    raise exception 'application not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  insert into support_childcare_guardian_meetings (
    application_id, meeting_date, attendee, content, guardian_intention, recorded_by
  ) values (
    p_application_id, p_meeting_date, p_attendee, p_content, p_guardian_intention, my_employee_id()
  )
  returning id into v_id;

  return v_id;
end;
$$;
