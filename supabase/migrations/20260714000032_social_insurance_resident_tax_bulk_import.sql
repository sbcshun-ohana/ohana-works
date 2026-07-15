-- 標準報酬月額・社会保険/雇用保険加入状況・住民税の一括CSV取込。
-- これまでと同じプレビュー確認→反映のパターン(admin_web側でパース・検証、
-- 確認後にこのRPCへ整形済みの行データを渡す)。

-- 標準報酬月額(等級はinsurance_rate_tablesが全等級同一レートのため、
-- レート計算上は意味を持たない識別子として扱う。金額(health_insurance_amount/
-- pension_amount)が控除額計算に使われる実体)。
-- 同一(employee_id, effective_year_month)への再取込は洗い替え(冪等)。
create or replace function import_standard_monthly_remunerations_csv(
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
      health_insurance_amount int,
      health_insurance_grade int,
      pension_amount int,
      pension_grade int,
      effective_year_month date,
      revision_reason text
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    delete from standard_monthly_remunerations
    where employee_id = v_employee_id and effective_year_month = r.effective_year_month;

    insert into standard_monthly_remunerations (
      employee_id, health_insurance_amount, health_insurance_grade,
      pension_amount, pension_grade, effective_year_month, revision_reason, created_by
    ) values (
      v_employee_id, r.health_insurance_amount, r.health_insurance_grade,
      r.pension_amount, r.pension_grade, r.effective_year_month, r.revision_reason, my_employee_id()
    );
    v_count := v_count + 1;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'standard_monthly_remunerations', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_count, 'applied', '{}'::jsonb
  )
  returning id into v_log_id;

  return jsonb_build_object('log_id', v_log_id, 'imported_count', v_count);
end;
$$;

-- 保険加入状況。同一(employee_id, insurance_type)のうち終了日未設定(現在有効)な行が
-- あれば上書き、無ければ新規insert(施設別給与のRPC群と同じ「現在値の一括修正」方針)。
create or replace function import_insurance_enrollments_csv(
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
  v_existing_id uuid;
  r record;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  for r in
    select * from jsonb_to_recordset(p_rows) as x(
      employee_number text,
      insurance_type text,
      enrolled boolean,
      acquisition_date date,
      loss_date date
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    select id into v_existing_id from insurance_enrollments
    where employee_id = v_employee_id and insurance_type = r.insurance_type and loss_date is null
    limit 1;

    if v_existing_id is not null then
      update insurance_enrollments set
        enrolled = r.enrolled, acquisition_date = r.acquisition_date, loss_date = r.loss_date
      where id = v_existing_id;
    else
      insert into insurance_enrollments (
        employee_id, insurance_type, enrolled, acquisition_date, loss_date, created_by
      ) values (
        v_employee_id, r.insurance_type, r.enrolled, r.acquisition_date, r.loss_date, my_employee_id()
      );
    end if;
    v_count := v_count + 1;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'insurance_enrollments', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_count, 'applied', '{}'::jsonb
  )
  returning id into v_log_id;

  return jsonb_build_object('log_id', v_log_id, 'imported_count', v_count);
end;
$$;

-- 住民税(月額)。CSVは1職員×1年度×1ヶ月=1行のロング形式で受け取り、
-- (employee_id, fiscal_year)単位でmonthly_amounts jsonbへ集約してupsertする。
create or replace function import_resident_taxes_csv(
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
  v_row_count int := 0;
  v_employee_id uuid;
  v_key text;
  v_grouped jsonb := '{}'::jsonb; -- key = employee_number||':'||fiscal_year -> {employee_id, fiscal_year, months: {}}
  r record;
  v_entry jsonb;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  for r in
    select * from jsonb_to_recordset(p_rows) as x(
      employee_number text,
      fiscal_year int,
      year_month text,
      amount int
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    v_key := r.employee_number || ':' || r.fiscal_year::text;
    v_entry := coalesce(
      v_grouped -> v_key,
      jsonb_build_object('employee_id', v_employee_id, 'fiscal_year', r.fiscal_year, 'months', '{}'::jsonb)
    );
    v_entry := jsonb_set(
      v_entry, '{months}', (v_entry -> 'months') || jsonb_build_object(r.year_month, r.amount)
    );
    v_grouped := jsonb_set(v_grouped, array[v_key], v_entry);
    v_row_count := v_row_count + 1;
  end loop;

  for v_key in select jsonb_object_keys(v_grouped) loop
    v_entry := v_grouped -> v_key;
    insert into resident_taxes (employee_id, fiscal_year, monthly_amounts)
    values (
      (v_entry ->> 'employee_id')::uuid,
      (v_entry ->> 'fiscal_year')::int,
      v_entry -> 'months'
    )
    on conflict (employee_id, fiscal_year) do update set
      monthly_amounts = resident_taxes.monthly_amounts || excluded.monthly_amounts;
    v_count := v_count + 1;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'resident_taxes', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_count, 'applied', jsonb_build_object('row_count', v_row_count)
  )
  returning id into v_log_id;

  return jsonb_build_object('log_id', v_log_id, 'imported_count', v_count, 'row_count', v_row_count);
end;
$$;

create or replace function fetch_social_insurance_import_history()
returns table (id uuid, file_name text, imported_by_name text, imported_at timestamptz, imported_count int, import_target text)
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
  select fil.id, fil.file_name, e.name, fil.imported_at, fil.imported_count, fil.import_target
  from file_import_logs fil
  left join employees e on e.id = fil.imported_by
  where fil.import_target in ('standard_monthly_remunerations', 'insurance_enrollments', 'resident_taxes')
  order by fil.imported_at desc;
end;
$$;
