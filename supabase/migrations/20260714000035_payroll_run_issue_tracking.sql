-- パートタイム給与計算仕様書対応(2/2): 給与計算時のエラーチェック機構。
-- run_payrollはこれまでスキップした職員の理由を追跡・可視化していなかった。
-- 対象職員ごとに既知の欠落パターンを事前チェックし、payroll_run_issuesに
-- 記録する。値を推測せず「計算できない/怪しい」ことを明示するのが目的で、
-- チェック自体は給与計算結果(payroll_details)を書き換えない。

create table payroll_run_issues (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references payroll_runs(id) on delete cascade,
  employee_id uuid not null references employees(id),
  issue_type text not null check (issue_type in (
    'wage_not_set', 'hourly_wage_missing', 'insurance_enrollment_missing',
    'bank_account_missing', 'attendance_unapproved', 'negative_net_pay'
  )),
  severity text not null check (severity in ('error', 'warning')),
  message text not null,
  created_at timestamptz not null default now()
);
create index idx_payroll_run_issues_run on payroll_run_issues(payroll_run_id);

alter table payroll_run_issues enable row level security;
create policy payroll_run_issues_select_labor_manager on payroll_run_issues
  for select using (is_labor_manager_plus());

create or replace function run_payroll(p_target_month date default date_trunc('month', current_date)::date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_month_start date := date_trunc('month', p_target_month)::date;
  v_month_end date := (date_trunc('month', p_target_month) + interval '1 month' - interval '1 day')::date;
  v_run_id uuid;
  v_run_status payroll_run_status;
  v_employee record;
  v_total_employees int := 0;
  v_computed int := 0;
  v_wage_count int;
  v_salary_type salary_type;
  v_hourly_wage int;
  v_net_pay int;
begin
  if auth.uid() is not null and not is_labor_manager_plus() then
    raise exception 'not authorized to run payroll';
  end if;

  select id, status into v_run_id, v_run_status from payroll_runs where target_month = v_month_start;
  if v_run_id is not null and v_run_status <> 'draft' then
    raise exception 'payroll run for this month is already % and cannot be recalculated', v_run_status;
  end if;
  if v_run_id is null then
    insert into payroll_runs (target_month, status) values (v_month_start, 'draft') returning id into v_run_id;
  end if;

  delete from payroll_run_issues where payroll_run_id = v_run_id;

  for v_employee in
    select e.id, e.name from employees e
    where e.hire_date <= v_month_end
      and (e.resignation_date is null or e.resignation_date >= v_month_start)
  loop
    v_total_employees := v_total_employees + 1;

    select count(*) into v_wage_count
    from wage_masters w
    where w.employee_id = v_employee.id
      and w.effective_start_date <= v_month_end
      and (w.effective_end_date is null or w.effective_end_date >= v_month_start);

    if v_wage_count = 0 then
      insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
      values (v_run_id, v_employee.id, 'wage_not_set', 'error',
        v_employee.name || ': 対象月の基本給(wage_masters)が登録されていません');
    else
      select salary_type, hourly_wage into v_salary_type, v_hourly_wage
      from wage_masters w
      where w.employee_id = v_employee.id
        and w.effective_start_date <= v_month_end
        and (w.effective_end_date is null or w.effective_end_date >= v_month_start)
      order by w.effective_start_date desc limit 1;
      if v_salary_type = '時給' and (v_hourly_wage is null or v_hourly_wage <= 0) then
        insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
        values (v_run_id, v_employee.id, 'hourly_wage_missing', 'error',
          v_employee.name || ': 時給が未設定または0円です');
      end if;
    end if;

    if not exists (select 1 from insurance_enrollments where employee_id = v_employee.id) then
      insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
      values (v_run_id, v_employee.id, 'insurance_enrollment_missing', 'warning',
        v_employee.name || ': 社会保険・雇用保険の加入状況が未登録です(未加入判定が漏れている可能性)');
    end if;

    if not exists (
      select 1 from bank_transfer_accounts where employee_id = v_employee.id and is_current = true
    ) then
      insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
      values (v_run_id, v_employee.id, 'bank_account_missing', 'warning',
        v_employee.name || ': 振込先口座が未登録です');
    end if;

    if not exists (
      select 1 from attendance_summaries where employee_id = v_employee.id and target_month = v_month_start
    ) then
      insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
      values (v_run_id, v_employee.id, 'attendance_unapproved', 'error',
        v_employee.name || ': 対象月の勤怠集計(attendance_summaries)がありません(未承認または未実施)');
    end if;

    if compute_and_upsert_payroll_detail(v_employee.id, v_month_start, v_month_end, v_run_id, my_employee_id()) then
      v_computed := v_computed + 1;

      select net_pay into v_net_pay from payroll_details
      where payroll_run_id = v_run_id and employee_id = v_employee.id;
      if v_net_pay is not null and v_net_pay < 0 then
        insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
        values (v_run_id, v_employee.id, 'negative_net_pay', 'error',
          v_employee.name || ': 差引支給額がマイナスです(' || v_net_pay || '円)');
      end if;
    end if;
  end loop;

  update payroll_runs set updated_at = now() where id = v_run_id;

  return v_run_id;
end;
$$;

create or replace function fetch_payroll_run_issues(p_payroll_run_id uuid)
returns table (
  id uuid, employee_id uuid, employee_name text, issue_type text, severity text, message text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  return query
  select pri.id, pri.employee_id, e.name, pri.issue_type, pri.severity, pri.message
  from payroll_run_issues pri
  join employees e on e.id = pri.employee_id
  where pri.payroll_run_id = p_payroll_run_id
  order by (pri.severity = 'error') desc, e.name;
end;
$$;
