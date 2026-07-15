-- set_employee_facility_commute()に、扶養人数管理RPCと同種の同日付訂正
-- バグ(20260714000040で修正した問題と同じクラス)があるため先に修正する。
-- 開始年月日が完全一致する既存行は「同一期間の訂正」とみなし削除する。
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

  delete from commute_masters
  where employee_id = p_employee_id and office_id = p_office_id
    and effective_end_date is null and effective_start_date = p_effective_start_date;

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

-- 通勤費(commute_masters)の一括CSV取込。
--
-- 既存の施設別基本給・手当CSV取込(20260714000028)と同じ方式で、
-- 内部的には上記のset_employee_facility_commuteをそのまま呼び出す。

create or replace function import_employee_commutes_csv(
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
      commute_method text,
      calc_type text,
      unit_price int,
      taxable_limit int,
      effective_start_date date
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    perform set_employee_facility_commute(
      v_employee_id, r.office_id, r.commute_method, r.unit_price, r.calc_type, r.taxable_limit, r.effective_start_date
    );
    v_count := v_count + 1;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'employee_commutes', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_count, 'applied', '{}'::jsonb
  )
  returning id into v_log_id;

  return jsonb_build_object('log_id', v_log_id, 'imported_count', v_count);
end;
$$;

create or replace function fetch_employee_commutes_import_history()
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
  where fil.import_target = 'employee_commutes'
  order by fil.imported_at desc;
end;
$$;
