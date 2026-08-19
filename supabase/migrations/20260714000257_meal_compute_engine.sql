-- 257: 給食管理 Phase 1 ③-b。食数算出エンジン + 9:31cron + クラス承認 + 期限内変更 + fetch。設計v1.0 §4.2/§6.1。
-- 園児=在籍×非欠席を行区分へ振り分け提供対象(通常食/共通除去食)を計上。職員=11:00-13:00フルカバーの
-- 確定シフト(除外設定なし)∪自己発注(will_eat)。確定済み行は再算出で上書きしない。

-- 内部: 施設×日の食数を算出し meal_count_rows へ upsert(authzなし=cron用)。
create or replace function meal_compute_internal(p_office uuid, p_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_staff int;
begin
  insert into meal_count_days (office_id, business_date, computed_at)
  values (p_office, p_date, now())
  on conflict (office_id, business_date) do update set computed_at = now();

  -- 職員(昼食): 11:00-13:00フルカバーの確定シフト(除外設定なし) ∪ 自己発注(will_eat=true)
  select count(*) into v_staff from (
    select sh.employee_id as emp
    from shifts sh
    where sh.office_id = p_office and sh.work_date = p_date and sh.status = 'confirmed'
      and sh.start_time <= time '11:00' and sh.end_time >= time '13:00'
      and not exists (
        select 1 from staff_meal_entries sme
        where sme.employee_id = sh.employee_id and sme.business_date = p_date and sme.will_eat = false
      )
    union
    select sme.employee_id
    from staff_meal_entries sme
    where sme.office_id = p_office and sme.business_date = p_date and sme.will_eat = true
  ) t;

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
    case when sl.row_type = 'children' then sl.child_cnt else 0 end,
    case when sl.row_type = 'staff' and sl.slot = 'lunch' then v_staff else 0 end
  from slots sl
  on conflict (office_id, business_date, row_key, meal_slot) do update
    set child_count = excluded.child_count, staff_count = excluded.staff_count, updated_at = now()
    where meal_count_rows.is_confirmed = false;
end;
$$;

-- 手動再算出(職員以上・機能ON施設)。
create or replace function compute_meal_counts(p_office_id uuid, p_business_date date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  if not is_meal_management_enabled_for_office(p_office_id) then raise exception 'feature disabled'; end if;
  perform meal_compute_internal(p_office_id, p_business_date);
end;
$$;
grant execute on function compute_meal_counts(uuid, date) to authenticated, service_role;

-- 9:31 JST(= 00:31 UTC)の暫定自動算出(機能ON施設)。
create or replace function cron_compute_meal_counts()
returns void
language plpgsql security definer set search_path = public
as $$
declare o record; v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  for o in
    select id as office_id from offices where is_feature_enabled_for_office('meal_management_enabled', id)
  loop
    perform meal_compute_internal(o.office_id, v_today);
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'compute-meal-counts') then
    perform cron.unschedule('compute-meal-counts');
  end if;
end $$;
select cron.schedule('compute-meal-counts', '31 0 * * *', $$select cron_compute_meal_counts();$$);

-- クラス承認(担任=自クラス or 主任以上 / 職員行=主任以上)。行の全食事区分を確定。
create or replace function confirm_meal_row(p_office_id uuid, p_business_date date, p_row_key text)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_class uuid; v_found boolean;
begin
  select class_id, true into v_class, v_found
  from meal_row_definitions where office_id = p_office_id and row_key = p_row_key and is_active;
  if not coalesce(v_found, false) then raise exception 'row not found'; end if;
  if v_class is not null then
    if not (has_childcare_class_access(v_class) or manages_childcare(p_office_id)) then raise exception 'not authorized'; end if;
  else
    if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  end if;
  update meal_count_rows
    set is_confirmed = true, confirmed_by = my_employee_id(), confirmed_at = now(), updated_at = now()
  where office_id = p_office_id and business_date = p_business_date and row_key = p_row_key;
end;
$$;
grant execute on function confirm_meal_row(uuid, date, text) to authenticated, service_role;

-- 期限内変更(当日のみ・昼食10:00/午後14:00/朝おやつ9:30)。変更前後を履歴化。
create or replace function change_meal_row(
  p_office_id uuid, p_business_date date, p_row_key text, p_meal_slot text, p_field text, p_new_count int)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_class uuid; v_now time; v_deadline time; v_old int; r meal_count_rows%rowtype;
begin
  if p_field not in ('child', 'staff') then raise exception 'invalid field'; end if;
  if p_new_count < 0 then raise exception 'invalid count'; end if;
  if p_business_date <> (now() at time zone 'Asia/Tokyo')::date then raise exception '変更は当日のみ可能です'; end if;

  select class_id into v_class from meal_row_definitions where office_id = p_office_id and row_key = p_row_key and is_active;
  if v_class is not null then
    if not (has_childcare_class_access(v_class) or manages_childcare(p_office_id)) then raise exception 'not authorized'; end if;
  else
    if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  end if;

  v_deadline := case p_meal_slot
    when 'am_snack' then time '09:30' when 'lunch' then time '10:00' when 'pm_snack' then time '14:00' else null end;
  if v_deadline is null then raise exception 'invalid meal_slot'; end if;
  v_now := (now() at time zone 'Asia/Tokyo')::time;
  if v_now > v_deadline then
    raise exception '変更期限(%)を過ぎています。厨房へ口頭で連絡してください', v_deadline;
  end if;

  select * into r from meal_count_rows
  where office_id = p_office_id and business_date = p_business_date and row_key = p_row_key and meal_slot = p_meal_slot;
  if not found then raise exception 'row not found'; end if;
  v_old := case when p_field = 'child' then r.child_count else r.staff_count end;

  update meal_count_rows set
    child_count = case when p_field = 'child' then p_new_count else child_count end,
    staff_count = case when p_field = 'staff' then p_new_count else staff_count end,
    updated_at = now()
  where id = r.id;

  insert into meal_count_changes
    (office_id, business_date, row_key, meal_slot, field, old_count, new_count, changed_by)
  values (p_office_id, p_business_date, p_row_key, p_meal_slot, p_field, v_old, p_new_count, my_employee_id());
end;
$$;
grant execute on function change_meal_row(uuid, date, text, text, text, int) to authenticated, service_role;

-- 食数ボード取得(行×食事区分・提供マトリクス順)。
create or replace function fetch_meal_board(p_office_id uuid, p_business_date date)
returns table (
  row_key text, row_label text, row_type text, sort_order int, meal_slot text,
  child_count int, staff_count int, is_confirmed boolean, confirmed_by_name text
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select rd.row_key, rd.row_label, rd.row_type, rd.sort_order, mr.meal_slot,
         mr.child_count, mr.staff_count, mr.is_confirmed, e.name
  from meal_row_definitions rd
  join meal_count_rows mr on mr.office_id = rd.office_id and mr.row_key = rd.row_key and mr.business_date = p_business_date
  left join employees e on e.id = mr.confirmed_by
  where rd.office_id = p_office_id and rd.is_active
  order by rd.sort_order,
    case mr.meal_slot when 'am_snack' then 1 when 'lunch' then 2 else 3 end;
end;
$$;
grant execute on function fetch_meal_board(uuid, date) to authenticated, service_role;

-- 変更履歴(厨房アラート/admin参照用)。
create or replace function fetch_meal_changes(p_office_id uuid, p_business_date date)
returns table (
  id uuid, row_key text, row_label text, meal_slot text, field text,
  old_count int, new_count int, changed_by_name text, changed_at timestamptz,
  acknowledged_at timestamptz
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_childcare_staff() then raise exception 'not authorized'; end if;
  return query
  select ch.id, ch.row_key, rd.row_label, ch.meal_slot, ch.field,
         ch.old_count, ch.new_count, e.name, ch.changed_at, ch.acknowledged_at
  from meal_count_changes ch
  left join meal_row_definitions rd on rd.office_id = ch.office_id and rd.row_key = ch.row_key
  left join employees e on e.id = ch.changed_by
  where ch.office_id = p_office_id and ch.business_date = p_business_date
  order by ch.changed_at desc;
end;
$$;
grant execute on function fetch_meal_changes(uuid, date) to authenticated, service_role;
