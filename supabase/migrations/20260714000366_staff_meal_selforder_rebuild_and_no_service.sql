-- 366: 職員給食 自己注文モデル M2(俊指示 2026-08-27・設計ロック)。
--   (1) 給食「提供なし」を日×区分で持てるよう meal_count_days に列追加 + set_meal_no_service。
--   (2) 職員参加(participation)を「本人注文(曜日テンプレ+日別上書き)−欠勤/有給(全日)−施設提供なし」から
--       再構築する rebuild_staff_meal_participation を新設。シフト由来の自動生成は廃止。
--   (3) meal_compute_internal を改修: 職員数=participation件数、提供なし区分はスキップ、旧シフト生成ブロックを撤去。
--   ※請求集計(aggregate)の勤怠除外撤去・欠勤申請の再構築フックは後続 M3。
--   ※テンプレが無い曜日=食べない(×)。稼働前に全職員の曜日テンプレを用意すること(go-live seed)。

-- ============================================================
-- (1) 給食「提供なし」列(施設×日×区分)
-- ============================================================
alter table meal_count_days
  add column no_service_am_snack boolean not null default false,
  add column no_service_lunch    boolean not null default false,
  add column no_service_pm_snack boolean not null default false;

-- 施設アクセスのある職員が、日×区分の「提供なし」をON/OFF。切替後は当日分を即再算出。
create or replace function set_meal_no_service(p_office uuid, p_date date, p_slot text, p_value boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office) then raise exception 'not authorized'; end if;
  if p_slot not in ('am_snack','lunch','pm_snack') then raise exception 'invalid slot'; end if;
  if p_value is null then raise exception 'value is required'; end if;
  insert into meal_count_days (office_id, business_date) values (p_office, p_date)
    on conflict (office_id, business_date) do nothing;
  update meal_count_days set
    no_service_am_snack = case when p_slot = 'am_snack' then p_value else no_service_am_snack end,
    no_service_lunch    = case when p_slot = 'lunch'    then p_value else no_service_lunch end,
    no_service_pm_snack = case when p_slot = 'pm_snack' then p_value else no_service_pm_snack end,
    updated_at = now()
  where office_id = p_office and business_date = p_date;
  perform meal_compute_internal(p_office, p_date);  -- 職員参加の再構築も内部で実行される
end $$;
grant execute on function set_meal_no_service(uuid, date, text, boolean) to authenticated, service_role;

-- ============================================================
-- (2) 職員参加の再構築(本人注文ベース)
--   ◯ = ①施設の当日昼食が提供なしでない かつ ②当日の全日欠勤/有給(pending/approved)が無い
--        かつ ③日別上書き > 曜日テンプレ > × の順で will_eat=true、かつ 喫食施設 = この施設
--   manual(管理者の手動◯/×)は温存し、auto/self_order のみ入替。
--   weekday は Mon=0..Sun=6(shift_weekly_templates/曜日テンプレ準拠)。
-- ============================================================
create or replace function rebuild_staff_meal_participation(p_office uuid, p_date date)
returns void language plpgsql security definer set search_path = public as $$
declare v_weekday int; v_no_lunch boolean;
begin
  v_weekday := (extract(dow from p_date)::int + 6) % 7;  -- Postgres dow(Sun=0..Sat=6)→ Mon=0..Sun=6
  select coalesce(no_service_lunch, false) into v_no_lunch
    from meal_count_days where office_id = p_office and business_date = p_date;
  v_no_lunch := coalesce(v_no_lunch, false);

  -- auto/self_order を入替。manual(手動◯×)は温存。
  delete from staff_meal_participation
    where office_id = p_office and business_date = p_date and source in ('auto', 'self_order');

  if v_no_lunch then
    return;  -- 施設が昼食提供なし → 自動/自己注文は作らない(全員キャンセル)
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
grant execute on function rebuild_staff_meal_participation(uuid, date) to authenticated, service_role;

-- ============================================================
-- (3) meal_compute_internal 改修
--   職員数=participation件数、提供なし区分はスキップ、旧シフト由来の participation生成を撤去。
--   園児カウント(在籍×非欠席・遅刻不要児除外)は 337 と同一。
-- ============================================================
create or replace function meal_compute_internal(p_office uuid, p_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_staff int; v_no_am boolean; v_no_lunch boolean; v_no_pm boolean;
begin
  insert into meal_count_days (office_id, business_date, computed_at)
  values (p_office, p_date, now())
  on conflict (office_id, business_date) do update set computed_at = now();

  select coalesce(no_service_am_snack, false), coalesce(no_service_lunch, false), coalesce(no_service_pm_snack, false)
    into v_no_am, v_no_lunch, v_no_pm
    from meal_count_days where office_id = p_office and business_date = p_date;

  -- 職員参加を本人注文ベースで再構築(シフト由来の自動生成は廃止)。
  perform rebuild_staff_meal_participation(p_office, p_date);
  select count(*) into v_staff from staff_meal_participation
   where office_id = p_office and business_date = p_date and ate;

  -- 提供なし区分の既存行は削除(暫定/確定に関わらず提供なしを優先)。
  delete from meal_count_rows
   where office_id = p_office and business_date = p_date
     and ( (v_no_am and meal_slot = 'am_snack')
        or (v_no_lunch and meal_slot = 'lunch')
        or (v_no_pm and meal_slot = 'pm_snack') );

  -- 園児(在籍×非欠席。加えて「当日承認済み・給食不要の遅刻連絡」の児は除外=337)
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
      and not exists (
        select 1 from parent_requests pr
        where pr.child_id = c.id and pr.target_date = p_date
          and pr.request_type = 'tardiness' and pr.status = 'approved'
          and pr.details->>'給食' = '不要'
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
      and not (v_no_am and sl.slot = 'am_snack')      -- 提供なし区分は生成しない
      and not (v_no_lunch and sl.slot = 'lunch')
      and not (v_no_pm and sl.slot = 'pm_snack')
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
