-- 336: 給食管理 Phase 3 — 職員自己発注・喫食既定・食事参加スナップショット・食事管理表・給与控除転記
--   (設計指示書 給食管理 §6 / §14-3。俊指示 2026-08-25)。
-- 方針:
--  ・職員の昼食は「フルカバー確定シフト(11:00≦開始 かつ 13:00≦終了)で実効喫食=true」または「自己発注=true」。
--    実効喫食 = coalesce(当日エントリのwill_eat, 職員の喫食既定 eats_default, true)。
--  ・9:31算出(meal_compute_internal)を拡張し、その日昼食を数えた職員を staff_meal_participation に
--    スナップショット保存(auto/self_order)。管理者の手動追加(manual)は保持。月次台帳・給与控除の正データ。
--  ・給与控除は「確認付き一括反映」: 管理者以上/労務が月次で aggregate_staff_meal_deductions を実行し、
--    職員別 食数×施設単価(burden_fee_masters)を burden_fee_records へ upsert。既存給与エンジンが控除計上(改修不要)。
--  ・自己発注の締め=当日9:00 JST。単価未設定・過去日はガード。既存 staff_meal_entries を書込口として使用。

-- ============================================================
-- (1) 職員の喫食既定(恒常的に食べない設定)
-- ============================================================
create table employee_meal_settings (
  employee_id uuid primary key references employees(id) on delete cascade,
  eats_default boolean not null default true,   -- false=既定で喫食しない(自己発注で当日のみtrue可)
  updated_at timestamptz not null default now()
);
alter table employee_meal_settings enable row level security;
create policy ems_select on employee_meal_settings
  for select using (employee_id = my_employee_id() or is_labor_manager_plus() or is_childcare_admin_any());

-- ============================================================
-- (2) 職員の食事参加スナップショット(日次・給与/台帳の正)
-- ============================================================
create table staff_meal_participation (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  office_id uuid not null references offices(id),
  business_date date not null,
  ate boolean not null default true,
  source text not null check (source in ('auto', 'self_order', 'manual')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, business_date)
);
create index idx_staff_meal_participation_office on staff_meal_participation(office_id, business_date);
alter table staff_meal_participation enable row level security;
create policy smp_select on staff_meal_participation
  for select using (
    employee_id = my_employee_id() or manages_childcare(office_id) or is_labor_manager_plus()
  );

-- ============================================================
-- (3) 9:31算出エンジンの拡張(職員判定に喫食既定を反映+参加スナップショット)
--   ※園児部分は既存(260)と同一。職員部分のみ変更し participation を同期。
-- ============================================================
create or replace function meal_compute_internal(p_office uuid, p_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_staff int;
begin
  insert into meal_count_days (office_id, business_date, computed_at)
  values (p_office, p_date, now())
  on conflict (office_id, business_date) do update set computed_at = now();

  -- 昼食を数える職員をスナップショット同期(auto/self_orderのみ入替、manualは保持)。
  delete from staff_meal_participation
   where office_id = p_office and business_date = p_date and source in ('auto', 'self_order');

  insert into staff_meal_participation (employee_id, office_id, business_date, ate, source)
  select e.emp, p_office, p_date, true,
    case when exists (
      select 1 from staff_meal_entries s
      where s.employee_id = e.emp and s.business_date = p_date and s.will_eat = true
    ) then 'self_order' else 'auto' end
  from (
    -- フルカバー確定シフト かつ 実効喫食=true
    select sh.employee_id as emp
    from shifts sh
    where sh.office_id = p_office and sh.work_date = p_date and sh.status = 'confirmed'
      and sh.start_time <= time '11:00' and sh.end_time >= time '13:00'
      and coalesce(
        (select s.will_eat from staff_meal_entries s where s.employee_id = sh.employee_id and s.business_date = p_date),
        (select ms.eats_default from employee_meal_settings ms where ms.employee_id = sh.employee_id),
        true) = true
    union
    -- 自己発注=true(フルカバーでない職員も含む)
    select s.employee_id
    from staff_meal_entries s
    where s.office_id = p_office and s.business_date = p_date and s.will_eat = true
  ) e
  where not exists (
    select 1 from staff_meal_participation p
    where p.employee_id = e.emp and p.business_date = p_date and p.source = 'manual'
  )
  on conflict (employee_id, business_date) do update
    set office_id = excluded.office_id, ate = true, source = excluded.source, updated_at = now();

  select count(*) into v_staff from staff_meal_participation
   where office_id = p_office and business_date = p_date and ate;

  -- 園児(既存ロジックと同一)
  with attending as (
    select cce.class_id, s.meal_status, s.current_stage
    from children c
    join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
    cross join lateral fetch_child_meal_status_internal(c.id) s
    where c.office_id = p_office and c.enrollment_status = '在籍中'
      and not exists (
        select 1 from child_daily_attendance a
        where a.child_id = c.id and a.business_date = p_date and a.is_absent
      )
  ),
  row_counts as (
    select rd.row_key, rd.row_type, rd.am_snack, rd.lunch, rd.pm_snack,
      count(at.class_id) filter (where at.meal_status in ('通常食', '共通除去食')) as child_cnt
    from meal_row_definitions rd
    left join attending at
      on rd.row_type = 'children' and at.class_id = rd.class_id
         and (rd.meal_stage is null or rd.meal_stage = at.current_stage)
    where rd.office_id = p_office and rd.is_active
    group by rd.row_key, rd.row_type, rd.am_snack, rd.lunch, rd.pm_snack
  ),
  slots as (
    select rc.row_key, rc.row_type, rc.child_cnt, sl.slot
    from row_counts rc
    cross join lateral (values ('am_snack', rc.am_snack), ('lunch', rc.lunch), ('pm_snack', rc.pm_snack)) as sl(slot, enabled)
    where sl.enabled
  )
  insert into meal_count_rows (office_id, business_date, row_key, meal_slot, child_count, staff_count)
  select p_office, p_date, sl.row_key, sl.slot,
    greatest(0, (case when sl.row_type = 'children' then sl.child_cnt else 0 end) + coalesce(adj_c.delta, 0)),
    greatest(0, (case when sl.row_type = 'staff' and sl.slot = 'lunch' then v_staff else 0 end) + coalesce(adj_s.delta, 0))
  from slots sl
  left join meal_count_adjustments adj_c
    on adj_c.office_id = p_office and adj_c.business_date = p_date
       and adj_c.row_key = sl.row_key and adj_c.meal_slot = sl.slot and adj_c.field = 'child'
  left join meal_count_adjustments adj_s
    on adj_s.office_id = p_office and adj_s.business_date = p_date
       and adj_s.row_key = sl.row_key and adj_s.meal_slot = sl.slot and adj_s.field = 'staff'
  on conflict (office_id, business_date, row_key, meal_slot) do update
    set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now()
    where meal_count_rows.is_confirmed = false;
end;
$$;

-- ============================================================
-- (4) 自己発注・喫食既定(本人)
-- ============================================================
-- 当日9:00締め・過去日不可。source='self_order'で staff_meal_entries に upsert。
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
  if p_date = v_today and (now() at time zone 'Asia/Tokyo')::time >= time '09:00' then
    raise exception '当日分の締め切り(9:00)を過ぎています';
  end if;
  insert into staff_meal_entries (employee_id, office_id, business_date, will_eat, source, created_by)
    values (v_emp, v_office, p_date, p_will_eat, 'self_order', v_emp)
  on conflict (employee_id, business_date) do update
    set will_eat = excluded.will_eat, source = 'self_order', created_by = v_emp;
end $$;
grant execute on function set_staff_meal_entry(date, boolean) to authenticated, service_role;

-- 当日分の自己発注を取り消し(既定に戻す)。同じ締め切り。
create or replace function clear_staff_meal_entry(p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid; v_today date;
begin
  v_emp := my_employee_id();
  if v_emp is null then raise exception 'not authorized'; end if;
  v_today := (now() at time zone 'Asia/Tokyo')::date;
  if p_date < v_today then raise exception '過去日は変更できません'; end if;
  if p_date = v_today and (now() at time zone 'Asia/Tokyo')::time >= time '09:00' then
    raise exception '当日分の締め切り(9:00)を過ぎています';
  end if;
  delete from staff_meal_entries where employee_id = v_emp and business_date = p_date;
end $$;
grant execute on function clear_staff_meal_entry(date) to authenticated, service_role;

-- 恒常的な喫食既定(食べない職員のOFF設定)。
create or replace function set_staff_meal_default(p_eats boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_emp uuid;
begin
  v_emp := my_employee_id();
  if v_emp is null then raise exception 'not authorized'; end if;
  insert into employee_meal_settings (employee_id, eats_default) values (v_emp, p_eats)
  on conflict (employee_id) do update set eats_default = excluded.eats_default, updated_at = now();
end $$;
grant execute on function set_staff_meal_default(boolean) to authenticated, service_role;

-- 発注画面用: 期間の各日の状態(自動対象/当日エントリ/既定/実効/締め)。
create or replace function fetch_staff_meal_order_days(p_from date, p_to date)
returns table (business_date date, auto_eligible boolean, day_will_eat boolean,
               default_eats boolean, will_eat_effective boolean, locked boolean)
language sql stable security definer set search_path = public as $$
  with jst as (select (now() at time zone 'Asia/Tokyo') as n)
  select d::date,
    exists (select 1 from shifts sh where sh.employee_id = my_employee_id()
              and sh.work_date = d::date and sh.status = 'confirmed'
              and sh.start_time <= time '11:00' and sh.end_time >= time '13:00') as auto_eligible,
    (select s.will_eat from staff_meal_entries s where s.employee_id = my_employee_id() and s.business_date = d::date) as day_will_eat,
    coalesce((select ms.eats_default from employee_meal_settings ms where ms.employee_id = my_employee_id()), true) as default_eats,
    coalesce(
      (select s.will_eat from staff_meal_entries s where s.employee_id = my_employee_id() and s.business_date = d::date),
      (exists (select 1 from shifts sh where sh.employee_id = my_employee_id()
                 and sh.work_date = d::date and sh.status = 'confirmed'
                 and sh.start_time <= time '11:00' and sh.end_time >= time '13:00')
       and coalesce((select ms.eats_default from employee_meal_settings ms where ms.employee_id = my_employee_id()), true))
    ) as will_eat_effective,
    (d::date < (select n from jst)::date
     or (d::date = (select n from jst)::date and (select n from jst)::time >= time '09:00')) as locked
  from generate_series(p_from, p_to, interval '1 day') d
  order by d;
$$;
grant execute on function fetch_staff_meal_order_days(date, date) to authenticated, service_role;

-- ============================================================
-- (5) 月次食事管理表(管理者以上/労務)・給与控除転記・賃金明細添付
-- ============================================================
-- 施設の月次台帳(職員×日の参加行)。
create or replace function fetch_staff_meal_ledger(p_office uuid, p_month date)
returns table (employee_id uuid, employee_name text, business_date date, source text)
language sql stable security definer set search_path = public as $$
  select p.employee_id, e.name, p.business_date, p.source
  from staff_meal_participation p
  join employees e on e.id = p.employee_id
  where p.office_id = p_office and p.ate
    and p.business_date >= date_trunc('month', p_month)::date
    and p.business_date <  (date_trunc('month', p_month) + interval '1 month')::date
    and (is_childcare_admin(p_office) or is_labor_manager_plus())
  order by e.name, p.business_date;
$$;
grant execute on function fetch_staff_meal_ledger(uuid, date) to authenticated, service_role;

-- 月次の給食控除を給与へ反映(確認付き一括)。職員別 食数×施設単価 → burden_fee_records upsert。
-- 全施設横断で職員ごとに集計(1職員=当月の全施設分の食数・金額を合算)。既存給与エンジンが控除計上。
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

-- 賃金明細添付用(本人の当月の食事日一覧+単価)。
create or replace function fetch_my_meal_days(p_month date)
returns table (business_date date, source text, unit_price int)
language sql stable security definer set search_path = public as $$
  select p.business_date, p.source, coalesce(bm.unit_price, 0)
  from staff_meal_participation p
  left join burden_fee_masters bm on bm.office_id = p.office_id
  where p.employee_id = my_employee_id() and p.ate
    and p.business_date >= date_trunc('month', p_month)::date
    and p.business_date <  (date_trunc('month', p_month) + interval '1 month')::date
  order by p.business_date;
$$;
grant execute on function fetch_my_meal_days(date) to authenticated, service_role;
