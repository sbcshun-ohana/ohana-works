-- 週20時間の社会保険加入判定チェック(insurance_eligibility_mismatch)。
--
-- 既存のinsurance_enrollment_missingは「insurance_enrollments行が1件も
-- 無い」場合のみ検知するため、相内愛莉さんのように「意図的に
-- enrolled=falseの行が登録済み」の職員が週20時間以上勤務するようになった
-- 場合は検知できない盲点があった。本マイグレーションで、週所定労働時間
-- (weekly_scheduled_hours)が20時間以上なのに健康保険・厚生年金が
-- enrolled=trueでない職員を別途警告として検知する。
--
-- 自動でinsurance_enrollmentsへ書き込むことはせず、あくまで
-- payroll_run_issuesへの警告表示のみとする(法的な加入要否の最終判断は
-- 人間が行う、という既存方針を踏襲)。

alter table payroll_run_issues drop constraint payroll_run_issues_issue_type_check;
alter table payroll_run_issues add constraint payroll_run_issues_issue_type_check
  check (issue_type = any (array[
    'wage_not_set', 'hourly_wage_missing', 'insurance_enrollment_missing', 'bank_account_missing',
    'attendance_unapproved', 'negative_net_pay', 'base_salary_missing', 'prescribed_hours_missing',
    'absence_hours_abnormal', 'insurance_eligibility_mismatch'
  ]));

create or replace function run_payroll(p_target_month date DEFAULT (date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone))::date)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
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
  v_monthly_base_salary int;
  v_hourly_wage int;
  v_avg_monthly_hours numeric;
  v_fiscal_year int;
  v_is_full_time boolean;
  v_weekly_hours numeric;
  v_health_enrolled boolean;
  v_pension_enrolled boolean;
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
    select e.id, e.name, (et.name = '正社員') as is_full_time from employees e
    left join employment_types et on et.id = e.employment_type_id
    where e.hire_date <= v_month_end
      and (e.resignation_date is null or e.resignation_date >= v_month_start)
  loop
    v_total_employees := v_total_employees + 1;
    v_is_full_time := coalesce(v_employee.is_full_time, false);

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
      select salary_type, monthly_base_salary, hourly_wage into v_salary_type, v_monthly_base_salary, v_hourly_wage
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
      if v_salary_type = '月給' and (v_monthly_base_salary is null or v_monthly_base_salary <= 0) then
        insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
        values (v_run_id, v_employee.id, 'base_salary_missing', 'error',
          v_employee.name || ': 月額基本給が未設定または0円です');
      end if;

      if v_salary_type = '月給' then
        v_fiscal_year := (case when extract(month from v_month_start) >= 4
          then extract(year from v_month_start) else extract(year from v_month_start) - 1 end)::int;
        select hours into v_avg_monthly_hours from average_monthly_working_hours where fiscal_year = v_fiscal_year;
        if coalesce(v_avg_monthly_hours, 0) <= 0 then
          insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
          values (v_run_id, v_employee.id, 'prescribed_hours_missing', 'error',
            v_employee.name || ': ' || v_fiscal_year || '年度の平均所定労働時間(average_monthly_working_hours)が未設定です');
        end if;
      end if;
    end if;

    if not exists (select 1 from insurance_enrollments where employee_id = v_employee.id) then
      insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
      values (v_run_id, v_employee.id, 'insurance_enrollment_missing',
        case when v_is_full_time then 'error' else 'warning' end,
        v_employee.name || ': 社会保険・雇用保険の加入状況が未登録です' ||
        case when v_is_full_time then '(正社員は原則加入対象です)' else '(未加入判定が漏れている可能性)' end);
    end if;

    -- 週20時間の社会保険加入判定チェック(insurance_eligibility_mismatch)。
    select wsh.weekly_hours into v_weekly_hours
    from weekly_scheduled_hours wsh
    where wsh.employee_id = v_employee.id
      and wsh.effective_start_date <= v_month_end
      and (wsh.effective_end_date is null or wsh.effective_end_date >= v_month_start)
    order by wsh.effective_start_date desc limit 1;

    if v_weekly_hours is not null and v_weekly_hours >= 20 then
      v_health_enrolled := exists (
        select 1 from insurance_enrollments
        where employee_id = v_employee.id and insurance_type = '健康保険' and enrolled = true
          and acquisition_date <= v_month_end and (loss_date is null or loss_date >= v_month_start)
      );
      v_pension_enrolled := exists (
        select 1 from insurance_enrollments
        where employee_id = v_employee.id and insurance_type = '厚生年金' and enrolled = true
          and acquisition_date <= v_month_end and (loss_date is null or loss_date >= v_month_start)
      );
      if not (v_health_enrolled and v_pension_enrolled) then
        insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
        values (v_run_id, v_employee.id, 'insurance_eligibility_mismatch', 'warning',
          v_employee.name || ': 週所定労働時間が' || v_weekly_hours || '時間(20時間以上)ですが、' ||
          case
            when not v_health_enrolled and not v_pension_enrolled then '健康保険・厚生年金とも未加入です'
            when not v_health_enrolled then '健康保険が未加入です'
            else '厚生年金が未加入です'
          end || '。加入要否をご確認ください');
      end if;
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
    end if;
  end loop;

  update payroll_runs set updated_at = now() where id = v_run_id;

  return v_run_id;
end;
$function$;
