-- 367: 366(M2)の是正(Fableレビュー指摘・俊確認 2026-08-27)。
--   (1) rebuild が退職者・未入社者を participation に混入させていた → 在職期間フィルタ追加。
--   (2) rebuild に過去日ガード無し + authenticated grant のため、過去日で叩くと請求正データを現在テンプレで
--       上書き/削除できた → 過去日は no-op、直接実行は service_role のみに縮小(内部performは影響なし)。
--   (3) set_meal_no_service に過去日ガード + 機能ON確認を追加。
--   (4) 365のseedが「昼食フルカバー(11:00≦開始・13:00≦終了)でない」曜日まで will_eat=true にしていた
--       → 該当を false に補正(staging は対象0行=無害、本番の過大計上を防止)。

-- ============================================================
-- (1)(2) rebuild を在職フィルタ+過去日ガード付きで再作成
-- ============================================================
create or replace function rebuild_staff_meal_participation(p_office uuid, p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare v_weekday int; v_no_lunch boolean;
begin
  -- 過去日は凍結(過去の participation=給与控除の正データを現在テンプレで書き換えない)。
  -- 過去分の補正は職員給食表の手動上書き(source='manual')で行う。
  if p_date < (now() at time zone 'Asia/Tokyo')::date then return; end if;

  v_weekday := (extract(dow from p_date)::int + 6) % 7;  -- Postgres dow(Sun=0..Sat=6)→ Mon=0..Sun=6
  select coalesce(no_service_lunch, false) into v_no_lunch
    from meal_count_days where office_id = p_office and business_date = p_date;
  v_no_lunch := coalesce(v_no_lunch, false);

  delete from staff_meal_participation
    where office_id = p_office and business_date = p_date and source in ('auto', 'self_order');

  if v_no_lunch then
    return;
  end if;

  insert into staff_meal_participation (employee_id, office_id, business_date, ate, source)
  select e.emp, p_office, p_date, true,
         case when e.entry_will_eat is not null then 'self_order' else 'auto' end
  from (
    select emp.id as emp, ent.will_eat as entry_will_eat
    from employees emp
    left join staff_meal_weekly_templates tmpl
      on tmpl.employee_id = emp.id and tmpl.weekday = v_weekday
    left join staff_meal_entries ent
      on ent.employee_id = emp.id and ent.business_date = p_date
    where coalesce(ent.will_eat, tmpl.will_eat, false) = true                    -- ③ 日別 > テンプレ > ×
      and coalesce(ent.office_id, tmpl.office_id, emp.home_office_id) = p_office  -- この施設で食べる人だけ
      and emp.hire_date <= p_date                                                -- 在職期間(入社済)
      and (emp.resignation_date is null or emp.resignation_date >= p_date)       -- 在職期間(退職前)
      and not exists (                                                           -- ② 全日欠勤/有給(本人申請)
        select 1 from requests r
        where r.employee_id = emp.id
          and r.status in ('pending', 'approved')
          and p_date between r.target_date and coalesce(r.target_end_date, r.target_date)
          and ( r.request_type = 'absence'
             or (r.request_type = 'paid_leave' and coalesce(r.details ->> 'usage_unit', 'day') = 'day') )
      )
  ) e
  where not exists (                                                             -- manual職員は温存
    select 1 from staff_meal_participation p
    where p.employee_id = e.emp and p.business_date = p_date and p.source = 'manual'
  )
  on conflict (employee_id, business_date) do update
    set office_id = excluded.office_id, ate = true, source = excluded.source, updated_at = now();
end $$;
-- 直接実行は service_role のみ(内部の meal_compute_internal / set_meal_no_service は SECURITY DEFINER で呼ぶため影響なし)。
revoke execute on function rebuild_staff_meal_participation(uuid, date) from authenticated;
grant execute on function rebuild_staff_meal_participation(uuid, date) to service_role;

-- ============================================================
-- (3) set_meal_no_service に過去日ガード + 機能ON確認を追加
-- ============================================================
create or replace function set_meal_no_service(p_office uuid, p_date date, p_slot text, p_value boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office) then raise exception 'not authorized'; end if;
  if not is_meal_management_enabled_for_office(p_office) then raise exception 'feature disabled'; end if;
  if p_slot not in ('am_snack','lunch','pm_snack') then raise exception 'invalid slot'; end if;
  if p_value is null then raise exception 'value is required'; end if;
  if p_date < (now() at time zone 'Asia/Tokyo')::date then raise exception '過去日は変更できません'; end if;
  insert into meal_count_days (office_id, business_date) values (p_office, p_date)
    on conflict (office_id, business_date) do nothing;
  update meal_count_days set
    no_service_am_snack = case when p_slot = 'am_snack' then p_value else no_service_am_snack end,
    no_service_lunch    = case when p_slot = 'lunch'    then p_value else no_service_lunch end,
    no_service_pm_snack = case when p_slot = 'pm_snack' then p_value else no_service_pm_snack end,
    updated_at = now()
  where office_id = p_office and business_date = p_date;
  perform meal_compute_internal(p_office, p_date);
end $$;
grant execute on function set_meal_no_service(uuid, date, text, boolean) to authenticated, service_role;

-- ============================================================
-- (4) 365 seed の補正: 昼食フルカバーでない曜日は will_eat=false に
--   (旧モデルの職員昼食条件 start<=11:00 かつ end>=13:00 を満たさない移行行を除外)
-- ============================================================
update staff_meal_weekly_templates smt
set will_eat = false, updated_at = now()
from shift_weekly_templates swt
where smt.employee_id = swt.employee_id
  and smt.weekday = swt.weekday
  and smt.will_eat = true
  and not (swt.start_time <= time '11:00' and swt.end_time >= time '13:00');
