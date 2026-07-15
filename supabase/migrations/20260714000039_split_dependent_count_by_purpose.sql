-- 扶養人数の区分整理。
--
-- これまでtax_withholding_statuses.dependent_countは「社会保険の扶養人数」
-- (①)を格納していたが、給与計算エンジンの源泉徴収税額表ルックアップは
-- 本来「所得税の扶養人数(源泉控除対象扶養親族数)」(②)を参照すべきである。
-- ①と②は法律上別概念であり、これまで①の値を誤って②として使っていた。
--
-- 既存のdependent_countは①(社会保険の扶養人数)としてそのまま維持し、
-- 別途②(所得税の扶養人数)の列を追加する。現時点で②に該当する職員は
-- いないため、新列はデフォルト0で全職員分を初期化する。

alter table tax_withholding_statuses
  rename column dependent_count to social_insurance_dependent_count;

comment on column tax_withholding_statuses.social_insurance_dependent_count is
  '①社会保険の扶養人数(自身の健康保険等の被扶養者数)。源泉徴収税額計算には使用しない。';

alter table tax_withholding_statuses
  add column income_tax_dependent_count int not null default 0;

comment on column tax_withholding_statuses.income_tax_dependent_count is
  '②所得税の扶養人数(源泉控除対象扶養親族数)。源泉徴収税額表のルックアップに使用する。';

-- 6.3/6.6 UI用RPCを①②両方の扶養人数を受け付けるよう改修。
-- 引数構成(p_dependent_count → p_social_insurance_dependent_count +
-- p_income_tax_dependent_count)が変わるため、create or replaceの前に
-- 旧シグネチャの関数を明示的に削除する。
drop function if exists set_employee_tax_withholding_status(uuid, text, int, boolean, date);

create or replace function set_employee_tax_withholding_status(
  p_employee_id uuid,
  p_tax_column text,
  p_social_insurance_dependent_count int,
  p_income_tax_dependent_count int,
  p_submitted_flag boolean,
  p_effective_start_year_month date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;
  if p_tax_column not in ('甲欄', '乙欄') then
    raise exception 'invalid tax_column: % (must be 甲欄 or 乙欄)', p_tax_column;
  end if;
  if p_social_insurance_dependent_count is null or p_social_insurance_dependent_count < 0 then
    raise exception 'social_insurance_dependent_count must be 0 or greater';
  end if;
  if p_income_tax_dependent_count is null or p_income_tax_dependent_count < 0 then
    raise exception 'income_tax_dependent_count must be 0 or greater';
  end if;

  update tax_withholding_statuses
  set effective_end_year_month = (p_effective_start_year_month - interval '1 month')::date
  where employee_id = p_employee_id
    and effective_end_year_month is null
    and effective_start_year_month < p_effective_start_year_month;

  insert into tax_withholding_statuses (
    employee_id, submitted_flag, tax_column,
    social_insurance_dependent_count, income_tax_dependent_count,
    effective_start_year_month, created_by
  ) values (
    p_employee_id, p_submitted_flag, p_tax_column,
    p_social_insurance_dependent_count, p_income_tax_dependent_count,
    p_effective_start_year_month, my_employee_id()
  )
  returning id into v_new_id;

  return v_new_id;
end;
$$;

-- 戻り値の列構成(OUTパラメータ)が変わるため、create or replaceの前に
-- 旧定義を明示的に削除する。
drop function if exists fetch_employees_tax_withholding_status();

create or replace function fetch_employees_tax_withholding_status()
returns table (
  employee_id uuid,
  employee_name text,
  office_name text,
  tax_column text,
  social_insurance_dependent_count int,
  income_tax_dependent_count int,
  submitted_flag boolean,
  effective_start_year_month date
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

-- 一括CSV取込RPCも①②両方を受け付けるよう改修。
create or replace function import_employee_tax_withholding_csv(
  p_file_name text,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_log_id uuid;
  v_count int := 0;
  v_employee_id uuid;
  r record;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  for r in
    select * from jsonb_to_recordset(p_rows) as x(
      employee_number text,
      tax_column text,
      social_insurance_dependent_count int,
      income_tax_dependent_count int,
      submitted_flag boolean,
      effective_start_year_month date
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    perform set_employee_tax_withholding_status(
      v_employee_id, r.tax_column, r.social_insurance_dependent_count, r.income_tax_dependent_count,
      r.submitted_flag, r.effective_start_year_month
    );
    v_count := v_count + 1;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'employee_tax_withholding', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_count, 'applied', '{}'::jsonb
  )
  returning id into v_log_id;

  return jsonb_build_object('log_id', v_log_id, 'imported_count', v_count);
end;
$$;

-- 給与計算エンジン: 源泉徴収税額表の参照先を②所得税の扶養人数に修正。
-- (20260714000036からの変更点は「tax_column, dependent_count」を
-- 「tax_column, income_tax_dependent_count」に変更した1箇所のみ)
create or replace function compute_and_upsert_payroll_detail(
  p_employee_id uuid, p_month_start date, p_month_end date, p_payroll_run_id uuid, p_computed_by uuid
)
returns boolean
language plpgsql
as $function$
declare
  v_summary attendance_summaries%rowtype;
  v_salary_type salary_type;
  v_salary_type_count int;
  v_monthly_base_salary integer := 0;
  v_hourly_wage integer;
  v_office_count int := 0;
  v_home_office_id uuid;
  v_birth_date date;
  v_age int;
  v_employee_name text;

  v_wage_row record;
  v_office_allowance_total int;
  v_office_allowance_breakdown jsonb;
  v_office_breakdown jsonb := '{}'::jsonb;

  v_avg_monthly_hours numeric;
  v_ot_hourly_rate numeric := 0;

  v_ot_base_allowance_total int := 0;
  v_ei_target_allowance_total int := 0;
  v_taxable_allowance_total int := 0;
  v_allowance_total int := 0;
  v_position_allowance int := 0;
  v_job_duty_allowance int := 0;
  v_allowance_breakdown jsonb := '{}'::jsonb;

  v_special_duty_amount int := 0;
  v_special_duty_taxable boolean := true;
  v_special_duty_ei_target boolean := true;

  v_early_shift_minutes int := 0;
  v_early_shift_allowance int := 0;

  v_commute_unit_price int;
  v_commute_calc_type text;
  v_commute_taxable_limit int;
  v_commute_amount int := 0;
  v_commute_taxable_excess int := 0;

  v_base_salary int := 0;
  v_regular_minutes int := 0;
  v_overtime_premium int := 0;
  v_night_premium int := 0;
  v_holiday_premium int := 0;
  v_gross_total int := 0;

  v_absence_minutes numeric := 0;
  v_tardiness_minutes numeric := 0;
  v_absence_deduction int := 0;
  v_deduction_unit_price numeric := 0;

  v_health_amount int; v_health_grade int;
  v_pension_amount int; v_pension_grade int;
  v_health_rate numeric; v_care_rate numeric; v_pension_rate numeric; v_ei_rate numeric;
  v_childcare_rate numeric;
  v_health_deduction int := 0;
  v_care_deduction int := 0;
  v_pension_deduction int := 0;
  v_ei_deduction int := 0;
  v_childcare_deduction int := 0;
  v_ei_wage_base int := 0;

  v_tax_column text;
  v_dependent_count_raw int;
  v_dependent_count int;
  v_taxable_base int := 0;
  v_income_tax int := 0;
  v_tier_base int;
  v_tier_threshold int;
  v_tier_rate numeric;

  v_resident_fiscal_year int;
  v_resident_tax int := 0;

  v_burden_fee int := 0;
  v_housing_deduction int := 0;
  v_deductions_total int := 0;
  v_net_pay int := 0;

  v_home_office_entry jsonb;

  v_earnings jsonb;
  v_deductions jsonb;
begin
  select * into v_summary from attendance_summaries
  where employee_id = p_employee_id and target_month = p_month_start;
  if v_summary.id is null then
    return false;
  end if;

  select name into v_employee_name from employees where id = p_employee_id;

  select count(distinct salary_type), count(*)
  into v_salary_type_count, v_office_count
  from wage_masters w
  where w.employee_id = p_employee_id
    and w.effective_start_date <= p_month_end
    and (w.effective_end_date is null or w.effective_end_date >= p_month_start);

  if v_office_count = 0 then
    return false;
  end if;
  if v_salary_type_count > 1 then
    raise exception 'employee % has inconsistent salary_type across offices for %', p_employee_id, p_month_start;
  end if;

  select home_office_id, birth_date into v_home_office_id, v_birth_date
  from employees where id = p_employee_id;
  v_age := case when v_birth_date is null then null
    else extract(year from age(p_month_end, v_birth_date))::int end;

  select coalesce(sum(ea.amount) filter (where am.overtime_base_target), 0)
  into v_ot_base_allowance_total
  from employee_allowances ea
  join allowance_masters am on am.id = ea.allowance_master_id
  where ea.employee_id = p_employee_id
    and ea.effective_start_date <= p_month_end
    and (ea.effective_end_date is null or ea.effective_end_date >= p_month_start);

  select
    coalesce(sum(ea.amount), 0),
    coalesce(sum(ea.amount) filter (where am.employment_insurance_target), 0),
    coalesce(sum(ea.amount) filter (where am.taxable), 0),
    coalesce(sum(ea.amount) filter (where am.name = '役職手当'), 0),
    coalesce(sum(ea.amount) filter (where am.name = '職務手当'), 0),
    coalesce(jsonb_object_agg(am.name, ea.amount) filter (where ea.amount is not null), '{}'::jsonb)
  into v_allowance_total, v_ei_target_allowance_total, v_taxable_allowance_total,
       v_position_allowance, v_job_duty_allowance, v_allowance_breakdown
  from employee_allowances ea
  join allowance_masters am on am.id = ea.allowance_master_id
  where ea.employee_id = p_employee_id
    and ea.effective_start_date <= p_month_end
    and (ea.effective_end_date is null or ea.effective_end_date >= p_month_start);

  select cm.unit_price, cm.calc_type, cm.taxable_limit
  into v_commute_unit_price, v_commute_calc_type, v_commute_taxable_limit
  from commute_masters cm
  where cm.employee_id = p_employee_id
    and cm.office_id = v_home_office_id
    and cm.effective_start_date <= p_month_end
    and (cm.effective_end_date is null or cm.effective_end_date >= p_month_start)
  order by cm.effective_start_date desc limit 1;

  v_commute_amount := case
    when v_commute_calc_type = 'fixed_monthly' then coalesce(v_commute_unit_price, 0)
    when v_commute_calc_type = 'per_day_roundtrip' then coalesce(v_commute_unit_price, 0) * v_summary.attendance_days
    else 0
  end;
  v_commute_taxable_excess := greatest(v_commute_amount - coalesce(v_commute_taxable_limit, v_commute_amount), 0);

  for v_wage_row in
    select office_id, salary_type, monthly_base_salary, hourly_wage, effective_start_date
    from wage_masters
    where employee_id = p_employee_id
      and effective_start_date <= p_month_end
      and (effective_end_date is null or effective_end_date >= p_month_start)
    order by effective_start_date desc
  loop
    v_salary_type := v_wage_row.salary_type;
    if v_salary_type = '月給' then
      v_monthly_base_salary := v_monthly_base_salary + coalesce(v_wage_row.monthly_base_salary, 0);
    else
      if v_hourly_wage is null then
        v_hourly_wage := v_wage_row.hourly_wage;
      end if;
    end if;

    select coalesce(sum(ea.amount), 0),
           coalesce(jsonb_object_agg(am.name, ea.amount) filter (where ea.amount is not null), '{}'::jsonb)
    into v_office_allowance_total, v_office_allowance_breakdown
    from employee_allowances ea
    join allowance_masters am on am.id = ea.allowance_master_id
    where ea.employee_id = p_employee_id
      and ea.office_id = v_wage_row.office_id
      and ea.effective_start_date <= p_month_end
      and (ea.effective_end_date is null or ea.effective_end_date >= p_month_start);

    v_office_breakdown := v_office_breakdown || jsonb_build_object(
      v_wage_row.office_id::text, jsonb_build_object(
        'base_salary', case when v_salary_type = '月給' then coalesce(v_wage_row.monthly_base_salary, 0) else 0 end,
        'allowances', v_office_allowance_total,
        'commute', case when v_wage_row.office_id = v_home_office_id then v_commute_amount else 0 end,
        'subtotal', (case when v_salary_type = '月給' then coalesce(v_wage_row.monthly_base_salary, 0) else 0 end)
          + v_office_allowance_total
          + (case when v_wage_row.office_id = v_home_office_id then v_commute_amount else 0 end)
      )
    );
  end loop;

  if v_office_count > 1 and v_salary_type = '時給' then
    raise warning
      'employee % has multiple offices with 時給 salary_type — hourly rate blending is not supported, using single rate from most recent wage_masters row; per-office hours cannot be attributed (see 14章 attendance_segments future work)',
      p_employee_id;
  end if;

  if v_salary_type = '月給' then
    select fy.hours into v_avg_monthly_hours
    from average_monthly_working_hours fy
    where fy.fiscal_year = (case when extract(month from p_month_start) >= 4
      then extract(year from p_month_start) else extract(year from p_month_start) - 1 end)::int;
    if coalesce(v_avg_monthly_hours, 0) > 0 then
      v_ot_hourly_rate := (v_monthly_base_salary + v_ot_base_allowance_total) / v_avg_monthly_hours / 60.0;
    end if;
  else
    v_ot_hourly_rate := coalesce(v_hourly_wage, 0) / 60.0;
  end if;

  select sda.amount, coalesce(sdas.taxable, true), coalesce(sdas.employment_insurance_target, true)
  into v_special_duty_amount, v_special_duty_taxable, v_special_duty_ei_target
  from special_duty_allowances sda
  left join lateral (
    select taxable, employment_insurance_target from special_duty_allowance_settings
    where effective_start_date <= p_month_start
    order by effective_start_date desc limit 1
  ) sdas on true
  where sda.employee_id = p_employee_id
    and sda.target_payroll_month = p_month_start
    and sda.confirmed = true;
  v_special_duty_amount := coalesce(v_special_duty_amount, 0);

  select coalesce(sum(
    greatest(0, extract(epoch from (
      least(da.approved_work_end_at, (da.work_date::timestamp + interval '8 hours') at time zone 'Asia/Tokyo')
      - greatest(da.approved_work_start_at, (da.work_date::timestamp + interval '7 hours') at time zone 'Asia/Tokyo')
    )) / 60)
  ), 0)::int
  into v_early_shift_minutes
  from daily_attendances da
  where da.employee_id = p_employee_id
    and da.work_date between p_month_start and p_month_end
    and da.approved_work_start_at is not null and da.approved_work_end_at is not null;
  v_early_shift_allowance := (v_early_shift_minutes / 15) * 125;

  v_overtime_premium := round(
    v_ot_hourly_rate * (
      (v_summary.overtime_minutes - v_summary.overtime_over_60h_minutes) * 0.25
      + v_summary.overtime_over_60h_minutes * 0.50
    )
  )::int;
  v_night_premium := round(v_ot_hourly_rate * v_summary.late_night_minutes * 0.25)::int;
  v_holiday_premium := round(v_ot_hourly_rate * v_summary.statutory_holiday_minutes * 0.35)::int;

  if v_salary_type = '月給' then
    v_base_salary := v_monthly_base_salary;

    if v_summary.prescribed_minutes > 0 then
      v_deduction_unit_price := (v_monthly_base_salary + v_position_allowance + v_job_duty_allowance)::numeric
        / v_summary.prescribed_minutes;

      select coalesce(sum(
        extract(epoch from (
          case when s.end_time < s.start_time then s.end_time - s.start_time + interval '24 hours'
          else s.end_time - s.start_time end
        )) / 60 - s.break_minutes
      ), 0)
      into v_absence_minutes
      from requests r
      join shifts s on s.employee_id = r.employee_id and s.work_date = r.target_date and s.status = 'confirmed'
      where r.employee_id = p_employee_id and r.request_type = 'absence' and r.status = 'approved'
        and r.target_date between p_month_start and p_month_end;

      select coalesce(sum(
        case
          when (r.details->>'sub_type') = 'tardiness' then
            greatest(extract(epoch from ((r.details->>'time')::time - s.start_time)) / 60, 0)
          when (r.details->>'sub_type') = 'early_leave' then
            greatest(extract(epoch from (s.end_time - (r.details->>'time')::time)) / 60, 0)
          else 0
        end
      ), 0)
      into v_tardiness_minutes
      from requests r
      join shifts s on s.employee_id = r.employee_id and s.work_date = r.target_date and s.status = 'confirmed'
      where r.employee_id = p_employee_id and r.request_type = 'tardiness_early_leave' and r.status = 'approved'
        and r.target_date between p_month_start and p_month_end;

      v_absence_deduction := floor(v_deduction_unit_price * (v_absence_minutes + v_tardiness_minutes))::int;

      -- 欠勤時間の異常値チェック: 欠勤+遅刻早退の合計が所定労働時間を超える場合は
      -- 明らかなデータ異常(申請の二重計上・所定労働時間の設定ミス等)として記録する。
      if (v_absence_minutes + v_tardiness_minutes) > v_summary.prescribed_minutes then
        insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
        values (p_payroll_run_id, p_employee_id, 'absence_hours_abnormal', 'error',
          coalesce(v_employee_name, p_employee_id::text) || ': 欠勤+遅刻早退時間(' ||
          round((v_absence_minutes + v_tardiness_minutes) / 60.0, 1) || '時間)が所定労働時間(' ||
          round(v_summary.prescribed_minutes / 60.0, 1) || '時間)を超えています');
      end if;
    end if;
  else
    v_regular_minutes := greatest(
      v_summary.actual_worked_minutes - v_summary.overtime_minutes - v_summary.statutory_holiday_minutes, 0
    );
    v_base_salary := round(coalesce(v_hourly_wage, 0) * v_regular_minutes / 60.0)::int;
    v_overtime_premium := round(
      coalesce(v_hourly_wage, 0) * (
        (v_summary.overtime_minutes - v_summary.overtime_over_60h_minutes) * 1.25
        + v_summary.overtime_over_60h_minutes * 1.50
      ) / 60.0
    )::int;
    v_holiday_premium := round(coalesce(v_hourly_wage, 0) * v_summary.statutory_holiday_minutes * 1.35 / 60.0)::int;
    v_absence_deduction := 0;
  end if;

  v_gross_total := v_base_salary + v_allowance_total + v_special_duty_amount + v_early_shift_allowance
    + v_overtime_premium + v_night_premium + v_holiday_premium + v_commute_amount;

  select smr.health_insurance_amount, smr.health_insurance_grade,
         smr.pension_amount, smr.pension_grade
  into v_health_amount, v_health_grade, v_pension_amount, v_pension_grade
  from standard_monthly_remunerations smr
  where smr.employee_id = p_employee_id and smr.effective_year_month <= p_month_start
  order by smr.effective_year_month desc limit 1;

  select rate into v_health_rate from insurance_rate_tables
  where insurance_type = '健康保険' and grade = v_health_grade
    and effective_start_year_month <= p_month_start
    and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
  order by effective_start_year_month desc limit 1;

  select rate into v_care_rate from insurance_rate_tables
  where insurance_type = '介護保険' and grade = v_health_grade
    and effective_start_year_month <= p_month_start
    and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
  order by effective_start_year_month desc limit 1;

  select rate into v_pension_rate from insurance_rate_tables
  where insurance_type = '厚生年金' and grade = v_pension_grade
    and effective_start_year_month <= p_month_start
    and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
  order by effective_start_year_month desc limit 1;

  select rate into v_ei_rate from insurance_rate_tables
  where insurance_type = '雇用保険'
    and effective_start_year_month <= p_month_start
    and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
  order by effective_start_year_month desc limit 1;

  select rate into v_childcare_rate from insurance_rate_tables
  where insurance_type = '子ども・子育て支援金' and grade = v_health_grade
    and effective_start_year_month <= p_month_start
    and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
  order by effective_start_year_month desc limit 1;

  if v_health_amount is not null and v_health_rate is not null and exists (
    select 1 from insurance_enrollments
    where employee_id = p_employee_id and insurance_type = '健康保険' and enrolled = true
      and acquisition_date <= p_month_end and (loss_date is null or loss_date >= p_month_start)
  ) then
    v_health_deduction := round_half_yen(v_health_amount * v_health_rate / 2);
    if v_age is not null and v_age between 40 and 64 and v_care_rate is not null then
      v_care_deduction := round_half_yen(v_health_amount * v_care_rate / 2);
    end if;
    if v_childcare_rate is not null then
      v_childcare_deduction := round_half_yen(v_health_amount * v_childcare_rate / 2);
    end if;
  end if;

  if v_pension_amount is not null and v_pension_rate is not null and exists (
    select 1 from insurance_enrollments
    where employee_id = p_employee_id and insurance_type = '厚生年金' and enrolled = true
      and acquisition_date <= p_month_end and (loss_date is null or loss_date >= p_month_start)
  ) then
    v_pension_deduction := round_half_yen(v_pension_amount * v_pension_rate / 2);
  end if;

  v_ei_wage_base := v_base_salary + v_ei_target_allowance_total + v_overtime_premium + v_night_premium
    + v_holiday_premium + v_early_shift_allowance
    + (case when v_special_duty_ei_target then v_special_duty_amount else 0 end);
  if v_ei_rate is not null and exists (
    select 1 from insurance_enrollments
    where employee_id = p_employee_id and insurance_type = '雇用保険' and enrolled = true
      and acquisition_date <= p_month_end and (loss_date is null or loss_date >= p_month_start)
  ) then
    v_ei_deduction := round_half_yen(v_ei_wage_base * v_ei_rate);
  end if;

  select tax_column, income_tax_dependent_count into v_tax_column, v_dependent_count_raw
  from tax_withholding_statuses
  where employee_id = p_employee_id
    and effective_start_year_month <= p_month_start
    and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
  order by effective_start_year_month desc limit 1;
  v_tax_column := coalesce(v_tax_column, '乙欄');
  v_dependent_count_raw := coalesce(v_dependent_count_raw, 0);
  v_dependent_count := least(v_dependent_count_raw, 7);

  v_taxable_base := v_base_salary + v_taxable_allowance_total
    + (case when v_special_duty_taxable then v_special_duty_amount else 0 end)
    + v_early_shift_allowance + v_overtime_premium + v_night_premium + v_holiday_premium
    + v_commute_taxable_excess
    - v_health_deduction - v_care_deduction - v_pension_deduction - v_ei_deduction - v_childcare_deduction;
  v_taxable_base := greatest(v_taxable_base, 0);

  if v_taxable_base < 105000 then
    if v_tax_column = '甲欄' then
      v_income_tax := 0;
    else
      v_income_tax := round(v_taxable_base * 0.03063)::int;
    end if;
  elsif v_taxable_base >= 740000 then
    select base_amount, threshold_amount, rate
    into v_tier_base, v_tier_threshold, v_tier_rate
    from withholding_tax_progressive_tiers
    where tax_column = v_tax_column
      and (dependent_count is null or dependent_count = v_dependent_count)
      and threshold_amount <= v_taxable_base
      and (upper_bound is null or v_taxable_base < upper_bound)
      and effective_start_year_month <= p_month_start
      and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
    order by threshold_amount desc limit 1;
    if v_tier_base is null then
      v_income_tax := 0;
    else
      v_income_tax := round(v_tier_base + (v_taxable_base - v_tier_threshold) * v_tier_rate)::int;
    end if;
  else
    select tax_amount into v_income_tax
    from withholding_tax_tables
    where tax_column = v_tax_column and dependent_count = v_dependent_count
      and wage_lower_bound <= v_taxable_base
      and (wage_upper_bound is null or v_taxable_base < wage_upper_bound)
      and effective_start_year_month <= p_month_start
      and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
    order by effective_start_year_month desc limit 1;
    v_income_tax := coalesce(v_income_tax, 0);
  end if;

  if v_tax_column = '甲欄' and v_dependent_count_raw > 7 then
    v_income_tax := greatest(v_income_tax - (v_dependent_count_raw - 7) * 1610, 0);
  end if;

  v_resident_fiscal_year := case when extract(month from p_month_start) >= 6
    then extract(year from p_month_start) else extract(year from p_month_start) - 1 end;
  select coalesce((monthly_amounts->>to_char(p_month_start, 'YYYY-MM'))::int, 0)
  into v_resident_tax
  from resident_taxes
  where employee_id = p_employee_id and fiscal_year = v_resident_fiscal_year;
  v_resident_tax := coalesce(v_resident_tax, 0);

  select coalesce(amount, 0) into v_burden_fee
  from burden_fee_records where employee_id = p_employee_id and target_month = p_month_start;
  v_burden_fee := coalesce(v_burden_fee, 0);

  select coalesce(deduction_amount, 0) into v_housing_deduction
  from company_housing_deductions where employee_id = p_employee_id and target_month = p_month_start;
  v_housing_deduction := coalesce(v_housing_deduction, 0);

  v_deductions_total := v_absence_deduction + v_health_deduction + v_care_deduction + v_pension_deduction
    + v_ei_deduction + v_childcare_deduction + v_income_tax + v_resident_tax + v_burden_fee + v_housing_deduction;
  v_net_pay := v_gross_total - v_deductions_total;

  if v_net_pay < 0 then
    insert into payroll_run_issues (payroll_run_id, employee_id, issue_type, severity, message)
    values (p_payroll_run_id, p_employee_id, 'negative_net_pay', 'error',
      coalesce(v_employee_name, p_employee_id::text) || ': 差引支給額がマイナスです(' || v_net_pay || '円)');
  end if;

  if v_office_breakdown ? v_home_office_id::text then
    v_home_office_entry := v_office_breakdown -> v_home_office_id::text;
    v_home_office_entry := v_home_office_entry
      || jsonb_build_object('deductions_total', v_deductions_total)
      || jsonb_build_object('net_pay', (v_home_office_entry->>'subtotal')::int - v_deductions_total);
    v_office_breakdown := jsonb_set(v_office_breakdown, array[v_home_office_id::text], v_home_office_entry);
  end if;

  v_earnings := jsonb_build_object(
    'base_salary', v_base_salary,
    'allowance_total', v_allowance_total,
    'allowance_breakdown', v_allowance_breakdown,
    'special_duty_allowance', v_special_duty_amount,
    'early_shift_allowance', v_early_shift_allowance,
    'overtime_premium', v_overtime_premium,
    'night_premium', v_night_premium,
    'holiday_premium', v_holiday_premium,
    'commute_allowance', v_commute_amount,
    'gross_total', v_gross_total
  );
  v_deductions := jsonb_build_object(
    'absence_deduction', v_absence_deduction,
    'health_insurance', v_health_deduction,
    'care_insurance', v_care_deduction,
    'pension_insurance', v_pension_deduction,
    'employment_insurance', v_ei_deduction,
    'childcare_support_levy', v_childcare_deduction,
    'income_tax', v_income_tax,
    'resident_tax', v_resident_tax,
    'burden_fee', v_burden_fee,
    'company_housing_deduction', v_housing_deduction,
    'deductions_total', v_deductions_total
  );

  insert into payroll_details (
    payroll_run_id, employee_id, office_breakdown, earnings, deductions, net_pay
  ) values (
    p_payroll_run_id, p_employee_id,
    v_office_breakdown,
    v_earnings, v_deductions, v_net_pay
  )
  on conflict (payroll_run_id, employee_id) do update set
    office_breakdown = excluded.office_breakdown,
    earnings = excluded.earnings,
    deductions = excluded.deductions,
    net_pay = excluded.net_pay,
    updated_at = now();

  insert into payslips (payroll_run_id, employee_id, generated_at)
  values (p_payroll_run_id, p_employee_id, now())
  on conflict (payroll_run_id, employee_id) do update set generated_at = now();

  return true;
end;
$function$;
