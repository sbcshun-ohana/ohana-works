-- 304: 厨房専用アプリ基盤。①厨房専用アカウント識別 ②その日の残量(グラム) ③日別/月別集計 ④食事区分横断集計。
-- 対象施設=その職員の施設割当(employee_office_assignments)。委託(安田物産)は大和/BABYMAHALO/Station、ハレレアは自園。

-- ① 厨房専用アカウント
alter table employees add column if not exists is_kitchen_only boolean not null default false;

create or replace function is_kitchen_only_employee()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_kitchen_only from employees where id = my_employee_id()), false);
$$;
grant execute on function is_kitchen_only_employee() to authenticated, service_role;

-- 厨房アカウントが管理する施設(割当 × 給食管理ON)。委託は複数、自園は1。
create or replace function fetch_my_kitchen_offices()
returns table (office_id uuid, office_name text, office_code text)
language plpgsql stable security definer set search_path = public as $$
begin
  return query
    select o.id, o.name, o.office_code
    from employee_office_assignments eoa
    join offices o on o.id = eoa.office_id
    where eoa.employee_id = my_employee_id()
      and eoa.start_date <= current_date and (eoa.end_date is null or eoa.end_date >= current_date)
      and is_meal_management_enabled_for_office(o.id)
    order by o.office_code;
end $$;
grant execute on function fetch_my_kitchen_offices() to authenticated, service_role;

-- ② その日の残量(グラム・施設×日×1項目)
alter table meal_count_days add column if not exists leftover_grams int;

create or replace function set_meal_leftover(p_office_id uuid, p_business_date date, p_grams int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  if not is_meal_management_enabled_for_office(p_office_id) then raise exception 'meal management disabled'; end if;
  insert into meal_count_days (office_id, business_date, leftover_grams)
    values (p_office_id, p_business_date, p_grams)
  on conflict (office_id, business_date) do update set leftover_grams = excluded.leftover_grams;
end $$;
grant execute on function set_meal_leftover(uuid, date, int) to authenticated, service_role;

-- ③ 月別集計(施設・暦月)。日別に食事区分すべて分けて園児/職員を集計 + 残量。UI/Excelで月合計を算出。
create or replace function fetch_meal_monthly_summary(p_office_id uuid, p_year int, p_month int)
returns table (
  business_date date,
  am_child int, am_staff int,
  lunch_child int, lunch_staff int,
  pm_child int, pm_staff int,
  leftover_grams int
)
language plpgsql stable security definer set search_path = public as $$
declare v_start date; v_end date;
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + interval '1 month - 1 day')::date;
  return query
    with days as (
      select distinct mr.business_date from meal_count_rows mr
        where mr.office_id = p_office_id and mr.business_date between v_start and v_end
      union
      select cd.business_date from meal_count_days cd
        where cd.office_id = p_office_id and cd.business_date between v_start and v_end and cd.leftover_grams is not null
    )
    select d.business_date,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'am_snack'), 0)::int,
      coalesce(sum(mr.staff_count) filter (where mr.meal_slot = 'am_snack'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'lunch'), 0)::int,
      coalesce(sum(mr.staff_count) filter (where mr.meal_slot = 'lunch'), 0)::int,
      coalesce(sum(mr.child_count) filter (where mr.meal_slot = 'pm_snack'), 0)::int,
      coalesce(sum(mr.staff_count) filter (where mr.meal_slot = 'pm_snack'), 0)::int,
      cd.leftover_grams
    from days d
    left join meal_count_rows mr on mr.office_id = p_office_id and mr.business_date = d.business_date
    left join meal_count_days cd on cd.office_id = p_office_id and cd.business_date = d.business_date
    group by d.business_date, cd.leftover_grams
    order by d.business_date;
end $$;
grant execute on function fetch_meal_monthly_summary(uuid, int, int) to authenticated, service_role;

-- ④ 食事区分横断集計(指定日・複数施設)。食事区分ごとに各施設の必要数を一覧化。
-- 厨房アプリ=fetch_my_kitchen_offices の全施設、admin=選択施設を渡す。各施設のアクセス権を検証。
create or replace function fetch_meal_slot_crossoffice(p_office_ids uuid[], p_business_date date)
returns table (office_id uuid, office_name text, office_code text, meal_slot text, child_total int, staff_total int)
language plpgsql stable security definer set search_path = public as $$
declare v_oid uuid;
begin
  foreach v_oid in array p_office_ids loop
    if not has_childcare_office_access(v_oid) then raise exception 'not authorized for office %', v_oid; end if;
  end loop;
  return query
    select o.id, o.name, o.office_code, mr.meal_slot,
           coalesce(sum(mr.child_count), 0)::int, coalesce(sum(mr.staff_count), 0)::int
    from offices o
    join meal_count_rows mr on mr.office_id = o.id and mr.business_date = p_business_date
    where o.id = any(p_office_ids)
    group by o.id, o.name, o.office_code, mr.meal_slot
    order by o.office_code,
      case mr.meal_slot when 'am_snack' then 1 when 'lunch' then 2 else 3 end;
end $$;
grant execute on function fetch_meal_slot_crossoffice(uuid[], date) to authenticated, service_role;
