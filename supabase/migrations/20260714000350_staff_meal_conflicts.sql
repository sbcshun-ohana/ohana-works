-- 350: 職員給食の「別施設で同日重複」検知(俊指示 2026-08-26)。
--   前提: staff_meal_participation は unique(employee_id, business_date) が全施設横断で掛かっており、
--         給与・台帳の正データは1職員1日1件=二重計上は構造的に発生しない(別施設で算出されても on conflict で上書き)。
--   ただし食数ボードの職員数は施設別に算出されるため、同じ職員が同日に「2施設でフルカバー確定シフト」または
--   「2施設で自己発注」を持つ場合、各施設ボードに1ずつ計上され得る(=入力ミス由来の重複兆候)。
--   これを月内で検知し、職員食事表にアラート表示する。物理的にはあり得ないためデータ入力の誤りを早期発見する安全網。
create or replace function fetch_staff_meal_conflicts(p_month date)
returns table (employee_id uuid, employee_name text, business_date date, office_names text[])
language plpgsql stable security definer set search_path = public as $$
begin
  if not (is_labor_manager_plus() or is_childcare_admin_any()) then
    raise exception 'not authorized';
  end if;
  return query
  with bounds as (
    select date_trunc('month', p_month)::date as m0,
           (date_trunc('month', p_month) + interval '1 month')::date as m1
  ),
  -- 各職員×日で「給食が付きうる施設」= フルカバー確定シフト ∪ 自己発注
  elig as (
    select sh.employee_id as emp, sh.work_date as bdate, sh.office_id as oid
    from shifts sh, bounds b
    where sh.status = 'confirmed'
      and sh.start_time <= time '11:00' and sh.end_time >= time '13:00'
      and sh.work_date >= b.m0 and sh.work_date < b.m1
    union
    select s.employee_id, s.business_date, s.office_id
    from staff_meal_entries s, bounds b
    where s.will_eat = true and s.business_date >= b.m0 and s.business_date < b.m1
  ),
  dup as (
    select emp, bdate, array_agg(distinct oid) as oids
    from elig
    group by emp, bdate
    having count(distinct oid) >= 2
  )
  select d.emp, e.name, d.bdate,
         (select array_agg(o.name order by o.name) from offices o where o.id = any(d.oids)) as office_names
  from dup d
  join employees e on e.id = d.emp
  order by d.bdate, e.name;
end $$;
grant execute on function fetch_staff_meal_conflicts(date) to authenticated, service_role;
comment on function fetch_staff_meal_conflicts(date) is
  '職員給食の別施設同日重複(入力ミス兆候)を月内で検知。正データ(participation)はunique制約で1件のため実害はほぼないが、食数ボードの二重計上を早期発見する安全網(350)。';
