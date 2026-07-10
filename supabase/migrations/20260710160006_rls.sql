-- 21章: RLS全テーブル有効化・デフォルト拒否
-- 職員=自分のデータのみ / 管理者=ロールと管理施設範囲内 /
-- 給与・マイナンバー・扶養・標準報酬・借上宿舎系=労務管理者以上のみ

-- ============================================================
-- ヘルパー関数
-- ============================================================
create or replace function my_employee_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from employees where auth_user_id = auth.uid();
$$;

-- 労務管理者以上(システム最高管理者・労務管理者)か判定
create or replace function is_labor_manager_plus()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id()
      and r.code in ('system_admin', 'labor_manager')
  );
$$;

-- 指定施設を管理する権限を持つか(全施設対象ロール、または当該施設にスコープされた
-- 園長・主任・園管理者以上のロールを保有していれば true)
create or replace function manages_office(target_office_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select is_labor_manager_plus() or exists (
    select 1
    from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id()
      and r.code in ('director', 'chief', 'office_manager', 'system_admin', 'labor_manager')
      and (er.office_id is null or er.office_id = target_office_id)
  );
$$;

-- ============================================================
-- 全テーブルRLS有効化(ポリシー未定義のテーブルはデフォルト拒否)
-- ============================================================
do $$
declare
  t text;
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public'
  loop
    execute format('alter table public.%I enable row level security;', t);
  end loop;
end $$;

-- ============================================================
-- 自己参照ポリシー(職員は自分のデータのみ閲覧可)
-- ============================================================
create policy employees_select_self on employees
  for select using (auth_user_id = auth.uid() or manages_office(home_office_id));

create policy daily_attendances_select_self on daily_attendances
  for select using (employee_id = my_employee_id());

create policy time_punches_select_self on time_punches
  for select using (employee_id = my_employee_id());

-- QR画面でのリアルタイム失効検知(使用済み検知→自動再発行)のため自分のトークンのみ参照可。
-- 発行・更新はEdge Function(service role)経由に限定し、クライアントからの直接書込は許可しない。
create policy qr_tokens_select_self on qr_tokens
  for select using (employee_id = my_employee_id());

create policy shifts_select_self on shifts
  for select using (employee_id = my_employee_id() or (office_id is not null and manages_office(office_id)));

create policy requests_select_self on requests
  for select using (employee_id = my_employee_id());
create policy requests_insert_self on requests
  for insert with check (employee_id = my_employee_id());

create policy leave_grants_select_self on leave_grants
  for select using (employee_id = my_employee_id());
create policy leave_usages_select_self on leave_usages
  for select using (employee_id = my_employee_id());

create policy payslips_select_self on payslips
  for select using (employee_id = my_employee_id());

create policy notifications_select_self on notifications
  for select using (target_employee_id = my_employee_id());

-- ============================================================
-- 参照マスタ(機密性なし): ログイン済み職員なら誰でも参照可
-- ============================================================
create policy offices_select_authenticated on offices
  for select using (my_employee_id() is not null);

do $$
declare
  t text;
  reference_tables text[] := array[
    'job_types',
    'positions',
    'employment_types',
    'roles',
    'holidays',
    'leave_day_hour_settings',
    'company_housing_program_settings'
  ];
begin
  foreach t in array reference_tables loop
    execute format(
      'create policy %1$I_select_authenticated on %1$I for select using (my_employee_id() is not null);',
      t
    );
  end loop;
end $$;

-- ============================================================
-- 管理者ポリシー(施設範囲内)
-- ============================================================

create policy daily_attendances_select_managed on daily_attendances
  for select using (
    exists (
      select 1 from employees e
      where e.id = daily_attendances.employee_id and manages_office(e.home_office_id)
    )
  );

-- ============================================================
-- 重要情報(5.3/21章): 労務管理者以上のみ
-- ============================================================
create policy my_numbers_labor_manager_only on my_numbers
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy standard_monthly_remunerations_labor_manager_only on standard_monthly_remunerations
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy tax_withholding_statuses_labor_manager_only on tax_withholding_statuses
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy dependents_labor_manager_only on dependents
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy bank_transfer_accounts_labor_manager_only on bank_transfer_accounts
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy company_housing_settings_labor_manager_only on company_housing_settings
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy company_housing_deductions_labor_manager_only on company_housing_deductions
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy special_duty_allowances_labor_manager_only on special_duty_allowances
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy insurance_enrollments_labor_manager_only on insurance_enrollments
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy wage_masters_labor_manager_only on wage_masters
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy resident_taxes_labor_manager_only on resident_taxes
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy payroll_runs_labor_manager_only on payroll_runs
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy payroll_details_labor_manager_only on payroll_details
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

create policy sensitive_access_logs_labor_manager_only on sensitive_access_logs
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

comment on function manages_office(uuid) is
  '5.3/21章の管理者権限範囲チェック。給与・マイナンバー等の重要情報テーブルは
   本関数ではなく is_labor_manager_plus() 単独で判定する(園長等には権限を渡さない)。';

comment on schema public is
  'RLSは本マイグレーションでベースラインのみ実装。役職手当や施設マスタ編集等、
   詳細な権限ロールマスタ(5.2)に基づく編集権限の粒度は管理者Web実装時に
   role_permissions テーブルを参照するポリシー/Edge Functionとして追加拡張すること。
   Next.js管理者Web側はサーバー(service_role)経由での操作を基本とし、
   本ポリシー群は主にFlutterクライアントからの直接アクセスに対する防御線として機能する。';
