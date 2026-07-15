-- 正社員給与計算仕様書対応。パートタイム版(20260714000033-035)と共通する
-- エンジン・エラーチェック基盤の上に、正社員特有の3項目を追加する。
--
-- 【照合結果】
-- 1. 欠勤控除自動計算: 既存実装で対応済み(下記compute_and_upsert_payroll_detail
--    のv_deduction_unit_price計算式が仕様の(基本給+役職手当+職務手当)÷所定労働
--    時間×欠勤時間と一致。有給休暇はrequest_type='paid_leave'で'absence'とは
--    別区分のため欠勤控除の対象に含まれない。変更不要)。
-- 2. 調整手当の使途差(有給休暇分賃金の補填 vs 前月修正・過不足調整): 保存先は
--    employee_allowances(allowance_master='調整手当')で共通、金額のみを保持する
--    汎用フィールドのため、バックエンドでの区別は不要(UI側の説明文のみで対応)。
-- 3. 社会保険「原則加入」: 自動でinsurance_enrollmentsへ書き込む処理は追加しない
--    (加入判定は法的に確認を要する事項であり、システムが無断で確定的な加入
--    データを作成するのは適切でないため)。代わりに、正社員で加入状況が
--    未登録の場合はpayroll_run_issuesのseverityをerrorに引き上げ(パート等は
--    従来通りwarning)、見落としを防ぐ形で対応する。
-- 4. エラーチェック追加: base_salary_missing(月給の基本給未設定)・
--    prescribed_hours_missing(所定労働時間未設定)・absence_hours_abnormal
--    (欠勤+遅刻早退時間が所定労働時間を超える異常値)を追加する。

alter table payroll_run_issues drop constraint payroll_run_issues_issue_type_check;
alter table payroll_run_issues add constraint payroll_run_issues_issue_type_check
  check (issue_type in (
    'wage_not_set', 'hourly_wage_missing', 'insurance_enrollment_missing',
    'bank_account_missing', 'attendance_unapproved', 'negative_net_pay',
    'base_salary_missing', 'prescribed_hours_missing', 'absence_hours_abnormal'
  ));

-- compute_and_upsert_payroll_detail: 欠勤時間異常・マイナス支給額の自己チェックを
-- エンジン内に追加する(いずれも計算済みの値を再利用するだけで、外側で同じ計算を
-- 重複させない)。それ以外のロジックは20260714000033から変更なし。
create or replace function compute_and_upsert_payroll_detail(
  p_employee_id uuid,
  p_month_start date,
  p_month_end date,
  p_payroll_run_id uuid,
  p_computed_by uuid
)
returns boolean
language plpgsql
as $$
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
          when (r.details ->> 'sub_type') = 'tardiness' then
            greatest(extract(epoch from ((r.details ->> 'time')::time - s.start_time)) / 60, 0)
          when (r.details ->> 'sub_type') = 'early_leave' then
            greatest(extract(epoch from (s.end_time - (r.details ->> 'time')::time)) / 60, 0)
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

  select tax_column, dependent_count into v_tax_column, v_dependent_count_raw
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
  select coalesce((monthly_amounts ->> to_char(p_month_start, 'YYYY-MM'))::int, 0)
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
      || jsonb_build_object('net_pay', (v_home_office_entry ->> 'subtotal')::int - v_deductions_total);
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
$$;

-- run_payroll: base_salary_missing・prescribed_hours_missingの事前チェックを追加、
-- insurance_enrollment_missingのseverityを雇用形態別に分岐(正社員=error/それ以外=
-- warning)。negative_net_payの事後チェックはエンジン内へ移動したためここでは行わない
-- (重複記録防止)。
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
  v_monthly_base_salary int;
  v_hourly_wage int;
  v_avg_monthly_hours numeric;
  v_fiscal_year int;
  v_is_full_time boolean;
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
$$;
