-- 施設別基本給・手当の一括CSV取込。
--
-- 52名分を1件ずつUIから登録するのは非現実的なため、既存の職員マスタCSV取込
-- (20260714000020)と同じ方式(admin_web側でパース→プレビュー→確認→RPC反映)で
-- 施設別基本給・手当を一括登録できるようにする。内部的には20260714000026の
-- set_employee_facility_wage/set_employee_facility_allowance をそのまま
-- 呼び出す(通勤費の二重計上防止バリデーション等のロジックを重複させない)。

create or replace function import_employee_facility_wages_csv(
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
      office_id uuid,
      salary_type salary_type,
      monthly_base_salary int,
      hourly_wage int,
      effective_start_date date
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    perform set_employee_facility_wage(
      v_employee_id, r.office_id, r.salary_type, r.monthly_base_salary, r.hourly_wage, r.effective_start_date
    );
    v_count := v_count + 1;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'employee_facility_wages', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_count, 'applied', '{}'::jsonb
  )
  returning id into v_log_id;

  return jsonb_build_object('log_id', v_log_id, 'imported_count', v_count);
end;
$$;

create or replace function import_employee_facility_allowances_csv(
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
  v_allowance_master_id uuid;
  r record;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  for r in
    select * from jsonb_to_recordset(p_rows) as x(
      employee_number text,
      office_id uuid,
      allowance_name text,
      amount int,
      effective_start_date date
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    select id into v_allowance_master_id from allowance_masters where name = r.allowance_name;
    if v_allowance_master_id is null then
      raise exception '手当種別 % が見つかりません', r.allowance_name;
    end if;

    perform set_employee_facility_allowance(
      v_employee_id, r.office_id, v_allowance_master_id, r.amount, r.effective_start_date
    );
    v_count := v_count + 1;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'employee_facility_allowances', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_count, 'applied', '{}'::jsonb
  )
  returning id into v_log_id;

  return jsonb_build_object('log_id', v_log_id, 'imported_count', v_count);
end;
$$;
