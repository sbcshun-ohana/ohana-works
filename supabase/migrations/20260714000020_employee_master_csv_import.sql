-- 20.2 職員マスタCSV取込。
--
-- admin_web /settings 画面でファイル選択→パース→プレビュー→管理者確認の流れを行い
-- (33章: 取込結果を管理者確認なしで確定してはならない)、確認後にこのRPCへ
-- 整形済みの行データを渡して初めてDBへ反映する(withholding_tax_tables CSV取込
-- (20260714000015)と同じ方式)。
--
-- CSV仕様(職員側=admin_webで検証・変換済みの値を渡す想定):
--   employee_number, name(姓+名結合), name_kana(姓+名かな結合。空欄可),
--   birth_date(空欄可), hire_date, office_id(施設UUID), employment_type_id
--   (雇用形態UUID。CSV上は名称だがadmin_web側でoffices/employment_typesの
--   マスタと突き合わせてIDに解決してから渡す), full_time_flag, base_salary(空欄可)。
--
-- 既存のemployee_number(employees_employee_number_key)は上書き更新する。
-- base_salaryはfull_time_flagに応じてwage_masters.monthly_base_salary
-- (月給)またはhourly_wage(時給)へ格納する。CSVにsalary_type相当の列が無いため、
-- full_time_flag=true→月給、false→時給という単純化した対応関係を採用している
-- (これに当てはまらない職員は職員マスタ画面/給与マスタで個別に修正すること)。
-- wage_masters は「現在有効(effective_end_date未設定)」な行があれば値を上書きし、
-- 無ければ effective_start_date=hire_date で新規行を作る(昇給イベントとしての
-- 履歴追加ではなく、現在値の一括修正としての取込のため)。base_salaryが空欄の行は
-- wage_masters に一切触れない。

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
      where employee_id = v_employee_id and effective_end_date is null
      order by effective_start_date desc limit 1;

      if v_open_wage_id is not null then
        update wage_masters set
          salary_type = case when r.full_time_flag then '月給'::salary_type else '時給'::salary_type end,
          monthly_base_salary = case when r.full_time_flag then r.base_salary else null end,
          hourly_wage = case when r.full_time_flag then null else r.base_salary end
        where id = v_open_wage_id;
      else
        insert into wage_masters (
          employee_id, salary_type, monthly_base_salary, hourly_wage, effective_start_date, created_by
        ) values (
          v_employee_id,
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

-- 反映履歴の表示用(withholding_tax_tablesと同形式・import_target='employees'のみ抽出)。
create or replace function fetch_employee_import_history()
returns table (
  id uuid,
  file_name text,
  imported_by_name text,
  imported_at timestamptz,
  target_period text,
  imported_count int,
  detail jsonb
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
  select fil.id, fil.file_name, e.name, fil.imported_at, fil.target_period, fil.imported_count, fil.detail
  from file_import_logs fil
  left join employees e on e.id = fil.imported_by
  where fil.import_target = 'employees'
  order by fil.imported_at desc;
end;
$$;
