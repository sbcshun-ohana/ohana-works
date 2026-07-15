-- 源泉徴収区分(甲欄/乙欄)・扶養人数の一括CSV取込。
-- 施設別基本給・手当の一括取込(20260714000028)と同じ方式で、既存の
-- set_employee_tax_withholding_status(20260714000016)をそのまま呼び出す。

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
      dependent_count int,
      submitted_flag boolean,
      effective_start_year_month date
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    perform set_employee_tax_withholding_status(
      v_employee_id, r.tax_column, r.dependent_count, r.submitted_flag, r.effective_start_year_month
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

create or replace function fetch_employee_tax_withholding_import_history()
returns table (id uuid, file_name text, imported_by_name text, imported_at timestamptz, imported_count int)
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
  select fil.id, fil.file_name, e.name, fil.imported_at, fil.imported_count
  from file_import_logs fil
  left join employees e on e.id = fil.imported_by
  where fil.import_target = 'employee_tax_withholding'
  order by fil.imported_at desc;
end;
$$;
