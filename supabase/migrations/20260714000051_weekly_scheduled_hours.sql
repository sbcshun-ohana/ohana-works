-- 週20時間 社会保険加入判定チェックのためのデータ基盤。
--
-- 週の所定労働時間(契約上の値)を保持する場所がこれまで一切存在しなかった
-- (attendance_summaries.prescribed_minutesは月次の実績シフトから算出される
-- 変動値で、契約上の週所定労働時間とは別概念)。wage_masters等と同じ
-- 効力発生日ベースの履歴管理パターンで新規追加する。

create table weekly_scheduled_hours (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  weekly_hours numeric not null check (weekly_hours >= 0),
  effective_start_date date not null,
  effective_end_date date,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);

create index idx_weekly_scheduled_hours_employee on weekly_scheduled_hours(employee_id);

alter table weekly_scheduled_hours enable row level security;

create policy weekly_scheduled_hours_labor_manager_only on weekly_scheduled_hours
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

-- 個別登録・履歴管理RPC(20260714000040/000041で修正した同日付訂正の
-- バグと同じ問題を避けるため、最初から同日付の既存行は削除する設計にする)。
create or replace function set_employee_weekly_scheduled_hours(
  p_employee_id uuid,
  p_weekly_hours numeric,
  p_effective_start_date date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;
  if p_weekly_hours is null or p_weekly_hours < 0 then
    raise exception 'weekly_hours must be 0 or greater';
  end if;

  delete from weekly_scheduled_hours
  where employee_id = p_employee_id
    and effective_end_date is null and effective_start_date = p_effective_start_date;

  update weekly_scheduled_hours
  set effective_end_date = (p_effective_start_date - interval '1 day')::date
  where employee_id = p_employee_id
    and effective_end_date is null and effective_start_date < p_effective_start_date;

  insert into weekly_scheduled_hours (employee_id, weekly_hours, effective_start_date, created_by)
  values (p_employee_id, p_weekly_hours, p_effective_start_date, my_employee_id())
  returning id into v_id;

  return v_id;
end;
$$;

-- 一括CSV取込RPC(既存のfacility_wages等と同じパターン)。
create or replace function import_weekly_scheduled_hours_csv(
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
      weekly_hours numeric,
      effective_start_date date
    )
  loop
    select id into v_employee_id from employees where employee_number = r.employee_number;
    if v_employee_id is null then
      raise exception 'employee_number % が見つかりません', r.employee_number;
    end if;

    perform set_employee_weekly_scheduled_hours(v_employee_id, r.weekly_hours, r.effective_start_date);
    v_count := v_count + 1;
  end loop;

  insert into file_import_logs (
    import_target, file_name, imported_by, target_period, imported_count, status, detail
  ) values (
    'weekly_scheduled_hours', p_file_name, my_employee_id(),
    to_char(now(), 'YYYY-MM-DD'), v_count, 'applied', '{}'::jsonb
  )
  returning id into v_log_id;

  return jsonb_build_object('log_id', v_log_id, 'imported_count', v_count);
end;
$$;

create or replace function fetch_weekly_scheduled_hours_import_history()
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
  where fil.import_target = 'weekly_scheduled_hours'
  order by fil.imported_at desc;
end;
$$;
