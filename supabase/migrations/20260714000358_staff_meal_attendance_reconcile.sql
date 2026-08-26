-- 358: 職員給食の請求ダブルチェック(俊指示 2026-08-26)。
--   シフト由来で給食が計上(participation)されても、その日の実勤怠(daily_attendances.actual_clock_in_at)が無ければ
--   請求する術がないため請求から除外する。台帳では 青丸(実勤務あり=請求可)/ 赤丸(勤怠なし=請求不可)を判別できるよう
--   has_attendance を返す。実際の通知(アラート表示)はフロント側で赤丸を明示。
--   勤怠判定: daily_attendances に実出勤打刻(actual_clock_in_at) があれば実勤務あり。

-- (1) 月次台帳に has_attendance を追加(戻り値変更のため drop→再作成)。
drop function if exists fetch_staff_meal_ledger(uuid, date);
create function fetch_staff_meal_ledger(p_office uuid, p_month date)
returns table (employee_id uuid, employee_name text, business_date date, source text, has_attendance boolean)
language sql stable security definer set search_path = public as $$
  select p.employee_id, e.name, p.business_date, p.source,
         exists (
           select 1 from daily_attendances da
           where da.employee_id = p.employee_id and da.work_date = p.business_date
             and da.actual_clock_in_at is not null
         ) as has_attendance
  from staff_meal_participation p
  join employees e on e.id = p.employee_id
  where p.office_id = p_office and p.ate
    and p.business_date >= date_trunc('month', p_month)::date
    and p.business_date <  (date_trunc('month', p_month) + interval '1 month')::date
    and (is_childcare_admin(p_office) or is_labor_manager_plus())
  order by e.name, p.business_date;
$$;
grant execute on function fetch_staff_meal_ledger(uuid, date) to authenticated, service_role;

-- (2) 給与控除の集計: 実勤怠のある日のみ請求(勤怠なし=請求できないため除外)。
create or replace function aggregate_staff_meal_deductions(p_month date)
returns int language plpgsql security definer set search_path = public as $$
declare v_month date := date_trunc('month', p_month)::date; v_cnt int;
begin
  if not (is_labor_manager_plus() or is_childcare_admin_any()) then raise exception 'not authorized'; end if;
  with agg as (
    select p.employee_id,
           count(*) as cnt,
           sum(coalesce(bm.unit_price, 0)) as amt
    from staff_meal_participation p
    left join burden_fee_masters bm on bm.office_id = p.office_id
    where p.ate
      and p.business_date >= v_month
      and p.business_date <  (v_month + interval '1 month')::date
      -- 実勤怠のある日のみ請求対象(勤怠なし=赤丸は除外)。
      and exists (
        select 1 from daily_attendances da
        where da.employee_id = p.employee_id and da.work_date = p.business_date
          and da.actual_clock_in_at is not null
      )
    group by p.employee_id
  )
  insert into burden_fee_records (employee_id, target_month, meal_count, amount, source)
  select employee_id, v_month, cnt, amt, '給食管理'
  from agg
  on conflict (employee_id, target_month) do update
    set meal_count = excluded.meal_count, amount = excluded.amount, source = '給食管理';
  get diagnostics v_cnt = row_count;
  return v_cnt;
end $$;
grant execute on function aggregate_staff_meal_deductions(date) to authenticated, service_role;

-- (3) 施設×月の「請求できない(勤怠なし)」職員給食の一覧(通知/警告バナー用)。
create or replace function fetch_staff_meal_unbillable(p_month date)
returns table (employee_id uuid, employee_name text, office_id uuid, office_name text, business_date date, source text)
language sql stable security definer set search_path = public as $$
  select p.employee_id, e.name, p.office_id, o.name, p.business_date, p.source
  from staff_meal_participation p
  join employees e on e.id = p.employee_id
  join offices o on o.id = p.office_id
  where (is_labor_manager_plus() or is_childcare_admin_any())
    and p.ate
    and p.business_date >= date_trunc('month', p_month)::date
    and p.business_date <  (date_trunc('month', p_month) + interval '1 month')::date
    and not exists (
      select 1 from daily_attendances da
      where da.employee_id = p.employee_id and da.work_date = p.business_date
        and da.actual_clock_in_at is not null
    )
  order by p.business_date, e.name;
$$;
grant execute on function fetch_staff_meal_unbillable(date) to authenticated, service_role;
