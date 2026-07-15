-- パートタイム給与計算仕様書対応(1/2続き): 通勤費が所属施設のみ参照になった
-- ことに伴い、RPC側のガードを更新する。
--
-- set_employee_facility_wage: 従来の「施設数が2以上になる場合、既存の
-- per_day_roundtrip commuteがあれば拒否」ガードは、通勤費が所属施設のみ
-- 参照される新設計では意味を持たなくなったため撤去する。
--
-- set_employee_facility_commute: 従来の「施設数2以上でper_day_roundtrip拒否」
-- ガードを撤去し、代わりに「所属施設(home_office_id)以外への登録を拒否する」
-- ガードに置き換える(通勤費は所属施設のみ支給という仕様のため、兼務施設への
-- 登録自体を認めない)。

create or replace function set_employee_facility_wage(
  p_employee_id uuid,
  p_office_id uuid,
  p_salary_type salary_type,
  p_monthly_base_salary integer,
  p_hourly_wage integer,
  p_effective_start_date date
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
  if p_salary_type not in ('月給', '時給') then
    raise exception 'invalid salary_type: %', p_salary_type;
  end if;
  if p_salary_type = '月給' and (p_monthly_base_salary is null or p_hourly_wage is not null) then
    raise exception '月給の場合はmonthly_base_salaryのみ指定してください';
  end if;
  if p_salary_type = '時給' and (p_hourly_wage is null or p_monthly_base_salary is not null) then
    raise exception '時給の場合はhourly_wageのみ指定してください';
  end if;

  update wage_masters
  set effective_end_date = (p_effective_start_date - interval '1 day')::date
  where employee_id = p_employee_id and office_id = p_office_id
    and effective_end_date is null and effective_start_date < p_effective_start_date;

  insert into wage_masters (
    employee_id, office_id, salary_type, monthly_base_salary, hourly_wage, effective_start_date, created_by
  ) values (
    p_employee_id, p_office_id, p_salary_type, p_monthly_base_salary, p_hourly_wage, p_effective_start_date,
    my_employee_id()
  )
  returning id into v_new_id;

  perform ensure_employee_office_assignment(p_employee_id, p_office_id, p_effective_start_date);

  return v_new_id;
end;
$$;

create or replace function set_employee_facility_commute(
  p_employee_id uuid,
  p_office_id uuid,
  p_commute_method text,
  p_unit_price integer,
  p_calc_type text,
  p_taxable_limit integer,
  p_effective_start_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid;
  v_home_office_id uuid;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;
  if p_calc_type not in ('fixed_monthly', 'per_day_roundtrip') then
    raise exception 'invalid calc_type: %', p_calc_type;
  end if;
  if p_unit_price is null or p_unit_price < 0 then
    raise exception 'unit_priceは0以上で指定してください';
  end if;

  -- 通勤費は所属施設(home_office_id)からのみ支給する(兼務施設には計上しない)。
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if p_office_id <> v_home_office_id then
    raise exception '通勤費は所属施設(home_office_id)のみ登録できます。兼務施設への通勤費は計上されません。';
  end if;

  update commute_masters
  set effective_end_date = (p_effective_start_date - interval '1 day')::date
  where employee_id = p_employee_id and office_id = p_office_id
    and effective_end_date is null and effective_start_date < p_effective_start_date;

  insert into commute_masters (
    employee_id, office_id, commute_method, unit_price, calc_type, taxable_limit, effective_start_date, created_by
  ) values (
    p_employee_id, p_office_id, p_commute_method, p_unit_price, p_calc_type, p_taxable_limit,
    p_effective_start_date, my_employee_id()
  )
  returning id into v_new_id;

  perform ensure_employee_office_assignment(p_employee_id, p_office_id, p_effective_start_date);

  return v_new_id;
end;
$$;
