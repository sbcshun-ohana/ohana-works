-- 16章/17章/18章 給与計算エンジン
--
-- attendance_summaries(20260714000007)の集計結果を入力に、基本給・各種手当・
-- 時間外/深夜/法定休日割増・欠勤控除・社会保険/雇用保険/源泉所得税/住民税控除を
-- 計算し payroll_runs/payroll_details/payslips へ保存する。
--
-- 割増の重複(11.7: 時間外+深夜=+50%等)は、各割増を「その割増固有の対象分数」に
-- 対して独立に加算する設計にすることで、明示的な重複判定ロジックなしに正しい
-- 合成レートを再現している(時間外分は基礎給に対し+25%/+50%、深夜分は独立に+25%、
-- 法定休日分は独立に+35%を加算。法定休日の時間は時間外集計から除外済み
-- (20260714000007側で担保)のため、時間外+法定休日の二重計上は発生しない)。
--
-- 17.2の給与確定フロー全体(確定ロック・振込CSV・PDF発行・通知)はスコープ外。
-- 本エンジンは計算とpayroll_runs(draft)/payroll_details/payslips(PDF未生成)の
-- 保存までを担う。payroll_runsが既にconfirmed/transferredの月は再計算を拒否する
-- (33章: 給与確定後の変更を再確定なしで反映してはならない/振込実行済みの給与を
-- 再確定してはならない)。

-- payslipsは本エンジンでは実PDFを生成しない(17.2でPDF発行は給与確定の後工程と
-- して明確に分離されているため)。生成済みだが未発行の状態を表現できるよう
-- file_pathをnullableにする。
alter table payslips alter column file_path drop not null;
alter table payslips add constraint payslips_run_employee_unique unique (payroll_run_id, employee_id);

create policy payslips_select_labor_manager on payslips
  for select using (is_labor_manager_plus());

-- ============================================================
-- 16.8 保険料の被保険者負担分端数: 50銭以下切捨て・50銭超切上げ
-- ============================================================
create or replace function round_half_yen(v numeric)
returns integer
language sql
immutable
as $$
  select case when (v - floor(v)) <= 0.5 then floor(v) else ceil(v) end::integer;
$$;

-- ============================================================
-- 職員1名・対象月分の給与明細を計算しpayroll_details/payslipsへ保存する。
-- ============================================================
create or replace function compute_and_upsert_payroll_detail(
  p_employee_id uuid,
  p_month_start date,
  p_month_end date,
  p_payroll_run_id uuid,
  p_computed_by uuid
)
returns boolean -- true=計算・保存した / false=入力不足でスキップした
language plpgsql
as $$
declare
  v_summary attendance_summaries%rowtype;
  v_salary_type salary_type;
  v_monthly_base_salary integer;
  v_hourly_wage integer;
  v_home_office_id uuid;
  v_birth_date date;
  v_age int;

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
  v_health_deduction int := 0;
  v_care_deduction int := 0;
  v_pension_deduction int := 0;
  v_ei_deduction int := 0;
  v_ei_wage_base int := 0;

  v_tax_column text;
  v_dependent_count int;
  v_taxable_base int := 0;
  v_income_tax int := 0;

  v_resident_fiscal_year int;
  v_resident_tax int := 0;

  v_burden_fee int := 0;
  v_housing_deduction int := 0;
  v_deductions_total int := 0;
  v_net_pay int := 0;

  v_earnings jsonb;
  v_deductions jsonb;
begin
  select * into v_summary from attendance_summaries
  where employee_id = p_employee_id and target_month = p_month_start;
  if v_summary.id is null then
    return false; -- 勤怠集計未実行のためスキップ
  end if;

  select w.monthly_base_salary, w.hourly_wage, w.salary_type
  into v_monthly_base_salary, v_hourly_wage, v_salary_type
  from wage_masters w
  where w.employee_id = p_employee_id
    and w.effective_start_date <= p_month_end
    and (w.effective_end_date is null or w.effective_end_date >= p_month_start)
  order by w.effective_start_date desc
  limit 1;
  if v_salary_type is null then
    return false; -- 給与単価未登録のためスキップ
  end if;

  select home_office_id, birth_date into v_home_office_id, v_birth_date
  from employees where id = p_employee_id;
  v_age := case when v_birth_date is null then null
    else extract(year from age(p_month_end, v_birth_date))::int end;

  -- 16.4 割増賃金の基礎単価
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

  if v_salary_type = '月給' then
    select fy.hours into v_avg_monthly_hours
    from average_monthly_working_hours fy
    where fy.fiscal_year = (case when extract(month from p_month_start) >= 4
      then extract(year from p_month_start) else extract(year from p_month_start) - 1 end)::int;
    if coalesce(v_avg_monthly_hours, 0) > 0 then
      v_ot_hourly_rate := (v_monthly_base_salary + v_ot_base_allowance_total) / v_avg_monthly_hours / 60.0;
    end if;
  else
    v_ot_hourly_rate := coalesce(v_hourly_wage, 0) / 60.0; -- 16.4: 時給者は時給そのもの
  end if;

  -- 16.10 特殊業務手当(当月分・確認済みのみ)
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

  -- 16.5 早番手当(7:00〜8:00勤務、15分125円)
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

  -- 16.6 交通費(職員×基本所属施設の通勤経路のみ。兼務按分はスコープ外)
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

  -- 割増(時間外/深夜/法定休日)。11.7の重複ルールは独立加算により再現(冒頭コメント参照)。
  v_overtime_premium := round(
    v_ot_hourly_rate * (
      (v_summary.overtime_minutes - v_summary.overtime_over_60h_minutes) * 0.25
      + v_summary.overtime_over_60h_minutes * 0.50
    )
  )::int;
  v_night_premium := round(v_ot_hourly_rate * v_summary.late_night_minutes * 0.25)::int;
  v_holiday_premium := round(v_ot_hourly_rate * v_summary.statutory_holiday_minutes * 0.35)::int;

  -- 16.2/16.3 基本給
  if v_salary_type = '月給' then
    v_base_salary := coalesce(v_monthly_base_salary, 0);

    -- 16.2 欠勤・遅刻・早退控除
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
    end if;
  else
    -- 16.3 時給制: 法定内(通常)分は時給×1.0、時間外/法定休日分は割増賃金側で全額計上済みのため
    -- 基本給からは除外する(二重計上防止)。深夜は独立加算のためここでは除外しない。
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
    v_absence_deduction := 0; -- 時給制は未勤務分がそもそも支給対象外のため欠勤控除の概念を適用しない
  end if;

  v_gross_total := v_base_salary + v_allowance_total + v_special_duty_amount + v_early_shift_allowance
    + v_overtime_premium + v_night_premium + v_holiday_premium + v_commute_amount;

  -- 16.8 社会保険・雇用保険控除
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

  if v_health_amount is not null and v_health_rate is not null and exists (
    select 1 from insurance_enrollments
    where employee_id = p_employee_id and insurance_type = '健康保険' and enrolled = true
      and acquisition_date <= p_month_end and (loss_date is null or loss_date >= p_month_start)
  ) then
    v_health_deduction := round_half_yen(v_health_amount * v_health_rate / 2);
    if v_age is not null and v_age between 40 and 64 and v_care_rate is not null then
      v_care_deduction := round_half_yen(v_health_amount * v_care_rate / 2);
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

  -- 16.8 源泉所得税(社保等控除後の課税対象額を税額表に照合)
  select tax_column, dependent_count into v_tax_column, v_dependent_count
  from tax_withholding_statuses
  where employee_id = p_employee_id
    and effective_start_year_month <= p_month_start
    and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
  order by effective_start_year_month desc limit 1;
  v_tax_column := coalesce(v_tax_column, '乙欄'); -- 6.6: 申告書提出なし=乙欄
  v_dependent_count := coalesce(v_dependent_count, 0);

  v_taxable_base := v_base_salary + v_taxable_allowance_total
    + (case when v_special_duty_taxable then v_special_duty_amount else 0 end)
    + v_early_shift_allowance + v_overtime_premium + v_night_premium + v_holiday_premium
    + v_commute_taxable_excess
    - v_health_deduction - v_care_deduction - v_pension_deduction - v_ei_deduction;
  v_taxable_base := greatest(v_taxable_base, 0);

  select tax_amount into v_income_tax
  from withholding_tax_tables
  where tax_column = v_tax_column and dependent_count = v_dependent_count
    and wage_lower_bound <= v_taxable_base
    and (wage_upper_bound is null or v_taxable_base < wage_upper_bound)
    and effective_start_year_month <= p_month_start
    and (effective_end_year_month is null or effective_end_year_month >= p_month_start)
  order by effective_start_year_month desc limit 1;
  v_income_tax := coalesce(v_income_tax, 0);

  -- 16.8 住民税(6月〜翌5月の年度、マスタ月額をそのまま適用)
  v_resident_fiscal_year := case when extract(month from p_month_start) >= 6
    then extract(year from p_month_start) else extract(year from p_month_start) - 1 end;
  select coalesce((monthly_amounts ->> to_char(p_month_start, 'YYYY-MM'))::int, 0)
  into v_resident_tax
  from resident_taxes
  where employee_id = p_employee_id and fiscal_year = v_resident_fiscal_year;
  v_resident_tax := coalesce(v_resident_tax, 0);

  -- 16.7 負担金(注文表由来・食数×単価は別途burden_fee_recordsへ集計済みの前提)
  select coalesce(amount, 0) into v_burden_fee
  from burden_fee_records where employee_id = p_employee_id and target_month = p_month_start;
  v_burden_fee := coalesce(v_burden_fee, 0);

  -- 16.9 借上宿舎本人負担金(労務管理者が手入力した確定額のみ使用。自動計算しない)
  select coalesce(deduction_amount, 0) into v_housing_deduction
  from company_housing_deductions where employee_id = p_employee_id and target_month = p_month_start;
  v_housing_deduction := coalesce(v_housing_deduction, 0);

  v_deductions_total := v_absence_deduction + v_health_deduction + v_care_deduction + v_pension_deduction
    + v_ei_deduction + v_income_tax + v_resident_tax + v_burden_fee + v_housing_deduction;
  v_net_pay := v_gross_total - v_deductions_total;

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
    jsonb_build_object(coalesce(v_home_office_id::text, 'unknown'), v_net_pay),
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

revoke execute on function compute_and_upsert_payroll_detail(uuid, date, date, uuid, uuid)
  from public, anon, authenticated;

-- ============================================================
-- 給与計算エンジン本体。
-- ============================================================
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

  for v_employee in
    select e.id from employees e
    where e.hire_date <= v_month_end
      and (e.resignation_date is null or e.resignation_date >= v_month_start)
  loop
    v_total_employees := v_total_employees + 1;
    if compute_and_upsert_payroll_detail(v_employee.id, v_month_start, v_month_end, v_run_id, my_employee_id()) then
      v_computed := v_computed + 1;
    end if;
  end loop;

  update payroll_runs set updated_at = now() where id = v_run_id;

  return v_run_id;
end;
$$;
