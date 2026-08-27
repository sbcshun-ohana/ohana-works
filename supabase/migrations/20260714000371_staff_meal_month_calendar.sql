-- 371: 職員給食 自己注文モデル M5 — 月カレンダー取得(俊指示 2026-08-27・設計ロック / Fableレビュー反映)。
--   職員アプリの給食注文カレンダー用。呼び出し本人の当月各日の実効状態を返す。
--   実効(will_eat)の決め方(rebuild=367/369と整合):
--     ・manual(手動◯×)がある日 → その ate(常に優先)
--     ・locked日(過去日 or 当日8:55以降=凍結)→ participation実体のみ coalesce(part_ate,false)
--     ・編集可能日(未来 or 当日8:55前)→ 投影: 日別上書き>曜日テンプレ>× − 在職期間外 − 全日欠勤/有給 − 施設昼食提供なし − 施設未解決
--   ※未locked日で participation を優先しないのは、曜日テンプレ変更(365)に再構築フックが無く、
--     同僚の未来日操作で materialize された古い◯が残り得るため(投影が最新)。
--   ※旧 fetch_staff_meal_order_days(336・シフトベース)を置き換える読み取り専用RPC。
create or replace function fetch_staff_meal_month(p_year int, p_month int)
returns table (business_date date, will_eat boolean, office_id uuid, locked boolean, blocked_reason text)
language plpgsql stable security definer set search_path = public as $$
declare v_emp uuid := my_employee_id();
        v_start date; v_end date;
        v_today date := (now() at time zone 'Asia/Tokyo')::date;
        v_time  time := (now() at time zone 'Asia/Tokyo')::time;
        v_hire date; v_resign date; v_home uuid;
begin
  if v_emp is null then raise exception 'not authorized'; end if;
  if p_month not between 1 and 12 then raise exception 'invalid month'; end if;
  select hire_date, resignation_date, home_office_id into v_hire, v_resign, v_home
    from employees where id = v_emp;
  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + interval '1 month - 1 day')::date;
  return query
  with days as (
    select gs::date as d, (extract(dow from gs)::int + 6) % 7 as wd
    from generate_series(v_start, v_end, interval '1 day') gs
  ),
  resolved as (
    select dy.d,
      (dy.d < v_today or (dy.d = v_today and v_time >= time '08:55')) as is_locked,
      (v_hire <= dy.d and (v_resign is null or v_resign >= dy.d)) as in_emp,
      coalesce(ent.will_eat, tmpl.will_eat, false) as base_will,
      coalesce(ent.office_id, tmpl.office_id, v_home) as res_office,
      part.ate as part_ate, part.office_id as part_office, part.source as part_source,
      exists (
        select 1 from requests rq
        where rq.employee_id = v_emp and rq.status in ('pending', 'approved')
          and dy.d between rq.target_date and coalesce(rq.target_end_date, rq.target_date)
          and ( rq.request_type = 'absence'
             or (rq.request_type = 'paid_leave' and coalesce(rq.details ->> 'usage_unit', 'day') = 'day') )
      ) as has_absence
    from days dy
    left join staff_meal_weekly_templates tmpl on tmpl.employee_id = v_emp and tmpl.weekday = dy.wd
    left join staff_meal_entries ent on ent.employee_id = v_emp and ent.business_date = dy.d
    left join staff_meal_participation part on part.employee_id = v_emp and part.business_date = dy.d
  ),
  computed as (
    select r.*,
      coalesce((select mcd.no_service_lunch from meal_count_days mcd
                where mcd.office_id = coalesce(r.part_office, r.res_office) and mcd.business_date = r.d), false) as no_svc
    from resolved r
  ),
  final as (
    select c.*,
      case
        when c.part_source = 'manual' then coalesce(c.part_ate, false)                 -- 手動は常に優先
        when c.is_locked then coalesce(c.part_ate, false)                              -- 締切後/過去は凍結実体のみ
        else (c.base_will and c.in_emp and not c.has_absence and not c.no_svc and c.res_office is not null)  -- 編集可能日=投影
      end as eff_will
    from computed c
  )
  select f.d,
    f.eff_will as will_eat,
    case when (f.part_source = 'manual' or f.is_locked) and f.part_office is not null then f.part_office
         else f.res_office end as office_id,
    f.is_locked as locked,
    case when not f.eff_will and f.has_absence then 'absence'
         when not f.eff_will and f.no_svc then 'no_service'
         else null end as blocked_reason
  from final f
  order by f.d;
end $$;
grant execute on function fetch_staff_meal_month(int, int) to authenticated, service_role;
