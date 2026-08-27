-- 369: 職員給食 自己注文モデル M4a(俊指示 2026-08-27・設計ロック)。
--   (1) rebuild を「過去日 + 当日8:55以降」は凍結に変更(締切後は自動再構築しない=変更は手動のみ)。
--   (2) set_staff_meal_day: 職員給食表/朝の発注画面から職員×日の◯を追加/削除。
--       締切前(未来 or 当日8:55前)= 日別上書き(staff_meal_entries)+再算出。
--       締切後(当日8:55以降)・過去日 = participation を手動(manual)で直接補正。
--       過去月は管理者以上のみ。それ以外は施設アクセスのある職員(誰でも)。
--   (3) fetch_staff_meal_day_orderers: その日◯の職員一覧(朝の発注画面の名前一覧)。
--   (4) 自己注文の締切を 9:00 → 8:55 に統一。
--   ※締切前の participation 生成cron・9:31自動確定・未承認アラートは後続 M4b。

-- ============================================================
-- (1) rebuild を 8:55凍結付きで再作成
-- ============================================================
create or replace function rebuild_staff_meal_participation(p_office uuid, p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare v_weekday int; v_no_lunch boolean; v_today date; v_time time;
begin
  v_today := (now() at time zone 'Asia/Tokyo')::date;
  v_time  := (now() at time zone 'Asia/Tokyo')::time;
  -- 過去日 + 当日8:55以降は凍結(締切後は自動再構築しない)。過去/締切後の補正は手動(manual)で行う。
  if p_date < v_today or (p_date = v_today and v_time >= time '08:55') then
    return;
  end if;

  v_weekday := (extract(dow from p_date)::int + 6) % 7;
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
    where coalesce(ent.will_eat, tmpl.will_eat, false) = true
      and coalesce(ent.office_id, tmpl.office_id, emp.home_office_id) = p_office
      and emp.hire_date <= p_date
      and (emp.resignation_date is null or emp.resignation_date >= p_date)
      and not exists (
        select 1 from requests r
        where r.employee_id = emp.id
          and r.status in ('pending', 'approved')
          and p_date between r.target_date and coalesce(r.target_end_date, r.target_date)
          and ( r.request_type = 'absence'
             or (r.request_type = 'paid_leave' and coalesce(r.details ->> 'usage_unit', 'day') = 'day') )
      )
  ) e
  where not exists (
    select 1 from staff_meal_participation p
    where p.employee_id = e.emp and p.business_date = p_date and p.source = 'manual'
  )
  on conflict (employee_id, business_date) do update
    set office_id = excluded.office_id, ate = true, source = excluded.source, updated_at = now();
end $$;
revoke execute on function rebuild_staff_meal_participation(uuid, date) from public, anon, authenticated;
grant execute on function rebuild_staff_meal_participation(uuid, date) to service_role;

-- ============================================================
-- (2) set_staff_meal_day: 職員×日の◯を追加/削除(職員給食表・朝の発注画面 共通)
-- ============================================================
create or replace function set_staff_meal_day(p_office uuid, p_date date, p_employee uuid, p_will_eat boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
        v_time  time := (now() at time zone 'Asia/Tokyo')::time;
        v_actor uuid := my_employee_id();
        v_src   text;
        v_prev  uuid;   -- 変更前にこの職員が食べていた施設(施設移動時の元施設再算出用)
begin
  if v_actor is null then raise exception 'not authorized'; end if;
  if not has_childcare_office_access(p_office) then raise exception 'not authorized'; end if;
  if not is_meal_management_enabled_for_office(p_office) then raise exception 'feature disabled'; end if;
  if p_will_eat is null then raise exception 'will_eat is required'; end if;
  -- 過去月は管理者以上のみ
  if p_date < date_trunc('month', v_today)::date
     and not (is_childcare_admin_any() or is_labor_manager_plus()) then
    raise exception '過去月の変更は管理者のみ可能です';
  end if;

  v_src := case when p_employee = v_actor then 'self_order' else 'admin' end;
  select office_id into v_prev from staff_meal_participation
    where employee_id = p_employee and business_date = p_date;

  if p_date > v_today or (p_date = v_today and v_time < time '08:55') then
    -- 締切前(未来 or 当日8:55前): 日別上書き + 再算出(rebuildが反映)
    insert into staff_meal_entries (employee_id, office_id, business_date, will_eat, source, created_by)
      values (p_employee, p_office, p_date, p_will_eat, v_src, v_actor)
    on conflict (employee_id, business_date) do update
      set will_eat = excluded.will_eat, office_id = excluded.office_id, source = excluded.source, created_by = v_actor;
    perform meal_compute_internal(p_office, p_date);  -- 内部でrebuildも実行
    if v_prev is not null and v_prev <> p_office then perform meal_compute_internal(v_prev, p_date); end if;
  else
    -- 締切後(当日8:55以降)または過去日: participation を手動(manual)で直接補正
    insert into staff_meal_participation (employee_id, office_id, business_date, ate, source)
      values (p_employee, p_office, p_date, p_will_eat, 'manual')
    on conflict (employee_id, business_date) do update
      set office_id = excluded.office_id, ate = excluded.ate, source = 'manual', updated_at = now();
    -- 当日は食数行も再算出(確定行はis_confirmedで保護)。過去日は行更新しない。
    if p_date = v_today then
      perform meal_compute_internal(p_office, p_date);
      if v_prev is not null and v_prev <> p_office then perform meal_compute_internal(v_prev, p_date); end if;
    end if;
  end if;
end $$;
grant execute on function set_staff_meal_day(uuid, date, uuid, boolean) to authenticated, service_role;

-- ============================================================
-- (3) fetch_staff_meal_day_orderers: その日◯の職員一覧(朝の発注画面)
-- ============================================================
create or replace function fetch_staff_meal_day_orderers(p_office uuid, p_date date)
returns table (employee_id uuid, employee_name text, source text)
language sql stable security definer set search_path = public as $$
  select p.employee_id, e.name, p.source
  from staff_meal_participation p
  join employees e on e.id = p.employee_id
  where p.office_id = p_office and p.business_date = p_date and p.ate
    and has_childcare_office_access(p_office)
  order by e.name;
$$;
grant execute on function fetch_staff_meal_day_orderers(uuid, date) to authenticated, service_role;

-- ============================================================
-- (4) 自己注文の締切を 9:00 → 8:55 に統一
-- ============================================================
create or replace function set_staff_meal_entry(p_date date, p_will_eat boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_office uuid; v_today date;
begin
  v_emp := my_employee_id();
  if v_emp is null then raise exception 'not authorized'; end if;
  select home_office_id into v_office from employees where id = v_emp;
  if v_office is null then raise exception '所属施設が未設定です'; end if;
  v_today := (now() at time zone 'Asia/Tokyo')::date;
  if p_date < v_today then raise exception '過去日は変更できません'; end if;
  if p_date = v_today and (now() at time zone 'Asia/Tokyo')::time >= time '08:55' then
    raise exception '当日分の締め切り(8:55)を過ぎています';
  end if;
  insert into staff_meal_entries (employee_id, office_id, business_date, will_eat, source, created_by)
    values (v_emp, v_office, p_date, p_will_eat, 'self_order', v_emp)
  on conflict (employee_id, business_date) do update
    set will_eat = excluded.will_eat, source = 'self_order', created_by = v_emp;
  perform meal_compute_internal(v_office, p_date);
end $$;
grant execute on function set_staff_meal_entry(date, boolean) to authenticated, service_role;

create or replace function clear_staff_meal_entry(p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_office uuid; v_today date;
begin
  v_emp := my_employee_id();
  if v_emp is null then raise exception 'not authorized'; end if;
  select home_office_id into v_office from employees where id = v_emp;
  v_today := (now() at time zone 'Asia/Tokyo')::date;
  if p_date < v_today then raise exception '過去日は変更できません'; end if;
  if p_date = v_today and (now() at time zone 'Asia/Tokyo')::time >= time '08:55' then
    raise exception '当日分の締め切り(8:55)を過ぎています';
  end if;
  -- 実際に登録されていた施設で再算出(他施設で入れられていた可能性があるため)。無ければ主所属。
  delete from staff_meal_entries where employee_id = v_emp and business_date = p_date
    returning office_id into v_office;
  if v_office is null then select home_office_id into v_office from employees where id = v_emp; end if;
  if v_office is not null then perform meal_compute_internal(v_office, p_date); end if;
end $$;
grant execute on function clear_staff_meal_entry(date) to authenticated, service_role;

-- ============================================================
-- (5) 締切前(8:50)に participation を materialize する定時cron
--   rebuildは当日8:55以降 no-op のため、締切前に一度 全対象施設×当日を算出しておく。
--   これで「当日誰も操作しなかった施設」でもテンプレ由来の◯が participation に載る。
--   既存 cron_compute_meal_counts(休園日/非稼働曜日スキップ付き)を8:50 JST=23:50 UTC で再利用。
-- ============================================================
do $$ begin
  perform cron.unschedule('materialize-meal-counts');
exception when others then null;
end $$;
select cron.schedule('materialize-meal-counts', '50 23 * * *', $$select cron_compute_meal_counts();$$);
