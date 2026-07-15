-- 施設別給与対応(3/3): 施設ごとの基本給・手当・通勤費を管理者Webから登録する
-- RPC。set_employee_tax_withholding_status(20260714000016)と同じパターン
-- (SECURITY DEFINER・is_labor_manager_plus()・旧有効行のクローズ→新規insert)。
-- 全職員共通の構造とし、3名専用の特別RPCは作らない。

-- 内部ヘルパー: 施設割当(employee_office_assignments)が無ければ登録する。
-- 3つのset_employee_facility_*から共通で呼び出される(単独のRPCとしては公開しない)。
create or replace function ensure_employee_office_assignment(
  p_employee_id uuid,
  p_office_id uuid,
  p_start_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_home_office_id uuid;
  v_assignment_type text;
begin
  if exists (
    select 1 from employee_office_assignments
    where employee_id = p_employee_id and office_id = p_office_id and end_date is null
  ) then
    return;
  end if;

  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  v_assignment_type := case when p_office_id = v_home_office_id then 'primary' else 'concurrent' end;

  insert into employee_office_assignments (employee_id, office_id, assignment_type, start_date, created_by)
  values (p_employee_id, p_office_id, v_assignment_type, p_start_date, my_employee_id());
end;
$$;

-- 施設ごとの基本給を登録する。
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
  v_other_active_offices int;
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

  -- 通勤費の二重計上防止: この登録により対象職員の施設数が2以上になる場合、
  -- 既存アクティブなcommute_masters行にper_day_roundtripがあれば拒否する
  -- (同日複数施設勤務時に日額×勤務日数が施設数分重複するため)。
  select count(distinct office_id) into v_other_active_offices
  from wage_masters
  where employee_id = p_employee_id and effective_end_date is null and office_id <> p_office_id;

  if v_other_active_offices >= 1 and exists (
    select 1 from commute_masters
    where employee_id = p_employee_id and effective_end_date is null and calc_type = 'per_day_roundtrip'
  ) then
    raise exception
      '複数施設を兼務する職員には日額×勤務日数(per_day_roundtrip)の通勤費を設定できません。先に月額固定(fixed_monthly)へ変更してください。';
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

-- 施設ごとの手当を登録する。
create or replace function set_employee_facility_allowance(
  p_employee_id uuid,
  p_office_id uuid,
  p_allowance_master_id uuid,
  p_amount integer,
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
  if p_amount is null or p_amount < 0 then
    raise exception 'amountは0以上で指定してください';
  end if;

  update employee_allowances
  set effective_end_date = (p_effective_start_date - interval '1 day')::date
  where employee_id = p_employee_id and office_id = p_office_id
    and allowance_master_id = p_allowance_master_id
    and effective_end_date is null and effective_start_date < p_effective_start_date;

  insert into employee_allowances (
    employee_id, office_id, allowance_master_id, amount, effective_start_date, created_by
  ) values (
    p_employee_id, p_office_id, p_allowance_master_id, p_amount, p_effective_start_date, my_employee_id()
  )
  returning id into v_new_id;

  perform ensure_employee_office_assignment(p_employee_id, p_office_id, p_effective_start_date);

  return v_new_id;
end;
$$;

-- 施設ごとの通勤費を登録する。
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
  v_active_offices int;
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

  -- 通勤費の二重計上防止: 対象職員が既に(この登録を含めて)2施設以上で
  -- アクティブなwage_masters行を持つ場合、per_day_roundtripは選択不可。
  if p_calc_type = 'per_day_roundtrip' then
    select count(distinct office_id) into v_active_offices
    from wage_masters
    where employee_id = p_employee_id and effective_end_date is null;

    if v_active_offices >= 2 then
      raise exception
        '複数施設を兼務する職員には日額×勤務日数(per_day_roundtrip)の通勤費を設定できません。月額固定(fixed_monthly)を使用してください。';
    end if;
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

-- 施設別の現在有効な基本給一覧。
create or replace function fetch_employee_facility_wages(p_employee_id uuid)
returns table (
  office_id uuid,
  office_name text,
  salary_type salary_type,
  monthly_base_salary integer,
  hourly_wage integer,
  effective_start_date date
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
  select w.office_id, o.name, w.salary_type, w.monthly_base_salary, w.hourly_wage, w.effective_start_date
  from wage_masters w
  join offices o on o.id = w.office_id
  where w.employee_id = p_employee_id
    and w.effective_start_date <= current_date
    and (w.effective_end_date is null or w.effective_end_date >= current_date)
  order by o.name;
end;
$$;

-- 施設別の現在有効な手当一覧。
create or replace function fetch_employee_facility_allowances(p_employee_id uuid)
returns table (
  office_id uuid,
  office_name text,
  allowance_master_id uuid,
  allowance_name text,
  amount integer,
  effective_start_date date
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
  select ea.office_id, o.name, ea.allowance_master_id, am.name, ea.amount, ea.effective_start_date
  from employee_allowances ea
  join offices o on o.id = ea.office_id
  join allowance_masters am on am.id = ea.allowance_master_id
  where ea.employee_id = p_employee_id
    and ea.effective_start_date <= current_date
    and (ea.effective_end_date is null or ea.effective_end_date >= current_date)
  order by o.name, am.name;
end;
$$;

-- 施設別の現在有効な通勤費一覧。
create or replace function fetch_employee_facility_commutes(p_employee_id uuid)
returns table (
  office_id uuid,
  office_name text,
  commute_method text,
  unit_price integer,
  calc_type text,
  taxable_limit integer,
  effective_start_date date
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
  select cm.office_id, o.name, cm.commute_method, cm.unit_price, cm.calc_type, cm.taxable_limit,
         cm.effective_start_date
  from commute_masters cm
  join offices o on o.id = cm.office_id
  where cm.employee_id = p_employee_id
    and cm.effective_start_date <= current_date
    and (cm.effective_end_date is null or cm.effective_end_date >= current_date)
  order by o.name;
end;
$$;
