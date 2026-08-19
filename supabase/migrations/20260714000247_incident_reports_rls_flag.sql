-- 247: ヒヤリハット・事故報告 Phase A ②(RLS + 全施設閲覧述語 + 機能フラグ)。
-- 閲覧=全施設の保育職員(§4.2)。保護者は employee を持たないため一切見えない。
-- 書き込みは③のRPC(security definer)経由のみ = RLSに write ポリシーは置かない。

-- 全施設の保育職員か(全施設閲覧の述語)。全施設管理者 or 有効な施設配属を持つ職員。
create or replace function is_childcare_staff()
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_executive_or_system_admin()
    or exists (
      select 1 from employee_office_assignments eoa
      where eoa.employee_id = my_employee_id()
        and eoa.start_date <= current_date
        and (eoa.end_date is null or eoa.end_date >= current_date)
    );
$$;
grant execute on function is_childcare_staff() to authenticated, service_role;

-- 機能フラグ(既定OFF・施設別ON。運用は feature_flag_office_overrides / 管理Web)
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('incident_reports_enabled', 'ヒヤリハット・事故報告',
   'ヒヤリハット/事故報告書(様式・承認・クロージング・週次集計)の施設別有効化。既定OFF、試験施設からON。', false)
on conflict (feature_key) do nothing;

create or replace function is_incident_reports_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select is_feature_enabled_for_office('incident_reports_enabled', p_office_id);
$$;
grant execute on function is_incident_reports_enabled_for_office(uuid) to authenticated, service_role;

-- RLS: 全8テーブル。select=全施設の保育職員のみ。write=RPC(definer)経由のみ。
alter table incident_reports enable row level security;
create policy incident_reports_select on incident_reports
  for select using (is_childcare_staff());

alter table incident_lookup_options enable row level security;
create policy incident_lookup_options_select on incident_lookup_options
  for select using (is_childcare_staff());

alter table incident_report_children enable row level security;
create policy incident_report_children_select on incident_report_children
  for select using (is_childcare_staff());

alter table incident_report_photos enable row level security;
create policy incident_report_photos_select on incident_report_photos
  for select using (is_childcare_staff());

alter table incident_report_progress_logs enable row level security;
create policy incident_report_progress_logs_select on incident_report_progress_logs
  for select using (is_childcare_staff());

alter table incident_report_guardian_contacts enable row level security;
create policy incident_report_guardian_contacts_select on incident_report_guardian_contacts
  for select using (is_childcare_staff());

alter table incident_report_medical_visits enable row level security;
create policy incident_report_medical_visits_select on incident_report_medical_visits
  for select using (is_childcare_staff());

alter table incident_report_childcare_dept_contacts enable row level security;
create policy incident_report_childcare_dept_contacts_select on incident_report_childcare_dept_contacts
  for select using (is_childcare_staff());
