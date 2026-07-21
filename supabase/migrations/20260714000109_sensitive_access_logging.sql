-- 開発計画(改訂版 2026-07-17) Phase 0 / P0-7: 重要情報アクセスログの実装。
-- PostgreSQLにはSELECT時に自動発火するトリガーが無いため、記録は各RPC本体に
-- log_sensitive_access()呼び出しを埋め込む方式で行う(トリガー方式は技術的に不可)。
--
-- 対象は現時点で実際に機微データを返しているRPC3件のみ:
--   fetch_payroll_transfer_recipients (bank_transfer_accounts)
--   fetch_employee_facility_wages (wage_masters)
--   fetch_employees_tax_withholding_status (tax_withholding_statuses)
-- my_numbers・dependents・standard_monthly_remunerations・company_housing_settings/
-- company_housing_deductions を返す読み取りRPCは現状どこにも存在しない(CSV取込での
-- 書き込みのみ)。将来これらを返すRPCを追加する場合は、必ずlog_sensitive_access()を
-- 呼び出すこと。
--
-- ログ記録という副作用を持つため、対象の3関数はSTABLEからVOLATILE(既定)へ変更する
-- (STABLEのまま書き込みを行うとクエリプランナの前提と矛盾するため)。

create or replace function log_sensitive_access(p_screen text, p_target_employee_id uuid, p_target_data text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_headers json;
  v_ip inet;
  v_ua text;
begin
  -- PostgREST経由のリクエストヘッダから取得を試みる。ヘッダが無い呼び出し元
  -- (Edge Function・直接RPC実行等)ではNULLのまま記録する。
  begin
    v_headers := current_setting('request.headers', true)::json;
    v_ip := nullif(split_part(v_headers->>'x-forwarded-for', ',', 1), '')::inet;
    v_ua := v_headers->>'user-agent';
  exception when others then
    v_ip := null;
    v_ua := null;
  end;

  insert into sensitive_access_logs (viewer_id, target_employee_id, screen, target_data, device_info, ip_address)
  values (my_employee_id(), p_target_employee_id, p_screen, p_target_data, v_ua, v_ip);
end;
$$;

comment on function log_sensitive_access(text, uuid, text) is
  '重要情報(給与・銀行口座・マイナンバー・扶養情報等)を返すRPCから呼び出す共通ログ記録関数。
   マイナンバー・扶養人数・標準報酬月額・借上宿舎の各テーブルを返す読み取りRPCを将来追加する
   場合は、必ずこの関数を呼び出すこと。';

create or replace function fetch_payroll_transfer_recipients(p_payroll_run_id uuid, p_office_id uuid)
returns table (
  employee_id uuid, employee_name text, net_pay integer,
  bank_name_kana text, branch_name_kana text, bank_code text, branch_code text,
  account_type text, account_number text, account_holder_name_kana text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status payroll_run_status;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  select status into v_status from payroll_runs where id = p_payroll_run_id;
  if v_status is null then
    raise exception 'payroll run not found';
  end if;
  if v_status = 'draft' then
    raise exception '給与確定前の対象月は振込CSVを出力できません(17.2: 給与確定の後工程)';
  end if;

  perform log_sensitive_access(
    '振込データ出力(fetch_payroll_transfer_recipients)',
    null,
    format('payroll_run_id=%s, office_id=%s', p_payroll_run_id, p_office_id)
  );

  return query
  select
    pd.employee_id, e.name, pd.net_pay,
    bta.bank_name_kana, bta.branch_name_kana, bta.bank_code, bta.branch_code,
    bta.account_type, bta.account_number, bta.account_holder_name_kana
  from payroll_details pd
  join employees e on e.id = pd.employee_id
  left join bank_transfer_accounts bta on bta.employee_id = pd.employee_id and bta.is_current = true
  where pd.payroll_run_id = p_payroll_run_id
    and e.home_office_id = p_office_id
  order by e.name;
end;
$$;

create or replace function fetch_employee_facility_wages(p_employee_id uuid)
returns table (
  office_id uuid, office_name text, salary_type salary_type,
  monthly_base_salary integer, hourly_wage integer, effective_start_date date
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  perform log_sensitive_access('施設別基本給(fetch_employee_facility_wages)', p_employee_id, '施設別基本給');

  return query
  select w.office_id, o.name, w.salary_type, w.monthly_base_salary, w.hourly_wage, w.effective_start_date
  from wage_masters w
  join offices o on o.id = w.office_id
  where w.employee_id = p_employee_id
    and w.effective_start_date <= current_date
    and (w.effective_end_date is null or w.effective_end_date >= current_date)
  order by o.name;
end;
$$;

create or replace function fetch_employees_tax_withholding_status()
returns table (
  employee_id uuid, employee_name text, office_name text, tax_column text,
  social_insurance_dependent_count integer, income_tax_dependent_count integer,
  submitted_flag boolean, effective_start_year_month date
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  perform log_sensitive_access(
    '源泉徴収区分・扶養人数一覧(fetch_employees_tax_withholding_status)',
    null,
    '源泉徴収区分・扶養人数一覧(全職員)'
  );

  return query
  select
    e.id, e.name, o.name,
    tws.tax_column, tws.social_insurance_dependent_count, tws.income_tax_dependent_count,
    tws.submitted_flag, tws.effective_start_year_month
  from employees e
  join offices o on o.id = e.home_office_id
  left join lateral (
    select tax_column, social_insurance_dependent_count, income_tax_dependent_count,
           submitted_flag, effective_start_year_month
    from tax_withholding_statuses
    where employee_id = e.id and effective_start_year_month <= current_date
    order by effective_start_year_month desc
    limit 1
  ) tws on true
  where e.resignation_date is null
  order by e.name;
end;
$$;
