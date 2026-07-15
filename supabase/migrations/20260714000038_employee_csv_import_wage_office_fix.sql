-- import_employees_csv()のバグ修正。
--
-- 1. 新規職員のwage_masters自動生成(0円プレースホルダー)がoffice_idを渡して
--    おらず、20260714000024でwage_masters.office_idがNOT NULLになったことで
--    "null value in column office_id" エラーが発生していた。
-- 2. 既存職員の更新時、"現在有効なwage_masters行"の検索がemployee_idのみで
--    絞り込んでおりoffice_idを見ていなかった。施設別給与対応後は複数施設分の
--    wage_masters行が同時に存在し得るため、施設を区別せず任意の1行を誤って
--    上書きしてしまう可能性があった(office_idも検索条件に追加する)。

create or replace function import_employees_csv(
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
  v_inserted_count int := 0;
  v_updated_count int := 0;
  v_employee_id uuid;
  v_was_existing boolean;
  v_open_wage_id uuid;
  r record;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  for r in
    select * from jsonb_to_recordset(p_rows) as x(
      employee_number text,
      name text,
      name_kana text,
      birth_date date,
      hire_date date,
      office_id uuid,
      employment_type_id uuid,
      full_time_flag boolean,
      base_salary int
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    v_was_existing := v_employee_id is not null;

    if v_was_existing then
      update employees set
        name = r.name,
        name_kana = r.name_kana,
        birth_date = r.birth_date,
        hire_date = r.hire_date,
        home_office_id = r.office_id,
        employment_type_id = r.employment_type_id,
        full_time_flag = r.full_time_flag,
        salary_type = case when r.full_time_flag then '月給'::salary_type else '時給'::salary_type end,
        updated_at = now()
      where id = v_employee_id;
      v_updated_count := v_updated_count + 1;
    else
      insert into employees (
        employee_number, name, name_kana, birth_date, hire_date,
        home_office_id, employment_type_id, full_time_flag, salary_type
      ) values (
        r.employee_number, r.name, r.name_kana, r.birth_date, r.hire_date,
        r.office_id, r.employment_type_id, r.full_time_flag,
        case when r.full_time_flag then '月給'::salary_type else '時給'::salary_type end
      )
      returning id into v_employee_id;
      v_inserted_count := v_inserted_count + 1;
    end if;

    if r.base_salary is not null then
      select id into v_open_wage_id from wage_masters
      where employee_id = v_employee_id and office_id = r.office_id and effective_end_date is null
      order by effective_start_date desc limit 1;

      if v_open_wage_id is not null then
        update wage_masters set
          salary_type = case when r.full_time_flag then '月給'::salary_type else '時給'::salary_type end,
          monthly_base_salary = case when r.full_time_flag then r.base_salary else null end,
          hourly_wage = case when r.full_time_flag then null else r.base_salary end
        where id = v_open_wage_id;
      else
        insert into wage_masters (
          employee_id, office_id, salary_type, monthly_base_salary, hourly_wage, effective_start_date, created_by
        ) values (
          v_employee_id,
          r.office_id,
          case when r.full_time_flag then '月給'::salary_type else '時給'::salary_type end,
          case when r.full_time_flag then r.base_salary else null end,
          case when r.full_time_flag then null else r.base_salary end,
          coalesce(r.hire_date, current_date),
          my_employee_id()
        );
      end if;
    end if;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'employees', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_inserted_count + v_updated_count, 'applied',
    jsonb_build_object('inserted', v_inserted_count, 'updated', v_updated_count)
  )
  returning id into v_log_id;

  return jsonb_build_object(
    'log_id', v_log_id,
    'inserted_count', v_inserted_count,
    'updated_count', v_updated_count
  );
end;
$$;
