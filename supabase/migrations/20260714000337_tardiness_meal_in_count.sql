-- 337: 遅刻・給食希望連絡の食数反映(給食管理 §4.4・俊指示 2026-08-25)。
--   保護者アプリの遅刻連絡(tardiness)に「給食の要否(要/不要)」を追加した(details['給食'])。
--   当日に承認済み(approved)で「給食 不要」の遅刻児は、9:31の食数(園児)から除外する。
--   ※「要」は既定の在籍(非欠席)に含まれるため増減なし。9:31前に承認された分が自動反映され、
--     以降の承認は既存の変更期限ルール(手動)で扱う。meal_compute_internal(336)に除外条件を1つ追加。
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
    select sh.employee_id as emp
    from shifts sh
    where sh.office_id = p_office and sh.work_date = p_date and sh.status = 'confirmed'
      and sh.start_time <= time '11:00' and sh.end_time >= time '13:00'
      and coalesce(
        (select s.will_eat from staff_meal_entries s where s.employee_id = sh.employee_id and s.business_date = p_date),
        (select ms.eats_default from employee_meal_settings ms where ms.employee_id = sh.employee_id),
        true) = true
    union
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
