-- 314: 登降園管理 Phase A。期間×園児の登降園実績マトリクス(日別ビュー=1日、月間ビュー=1ヶ月で共用)。
-- 登降園時刻は child_attendance_events(入=drop_off/退=pick_up/外=out/戻=return)、出欠は child_daily_attendance から集約。主任以上。
create or replace function fetch_attendance_matrix_for_office(p_office_id uuid, p_start date, p_end date)
returns table (
  child_id uuid, child_name text, class_name text, business_date date,
  in_time time, out_time time, return_time time, depart_time time,
  is_absent boolean, absence_reason text
)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  return query
  with ev as (
    select e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date as bd,
      min(e.occurred_at) filter (where e.event_type in ('drop_off','proxy_drop_off')) as in_ts,
      max(e.occurred_at) filter (where e.event_type in ('pick_up','proxy_pick_up'))   as depart_ts,
      max(e.occurred_at) filter (where e.event_type = 'out')    as out_ts,
      max(e.occurred_at) filter (where e.event_type = 'return') as ret_ts
    from child_attendance_events e
    join children c on c.id = e.child_id
    where c.office_id = p_office_id
      and (e.occurred_at at time zone 'Asia/Tokyo')::date between p_start and p_end
    group by e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date
  ),
  ab as (
    select a.child_id, a.business_date as bd, a.is_absent, a.absence_reason
    from child_daily_attendance a
    join children c on c.id = a.child_id
    where c.office_id = p_office_id and a.business_date between p_start and p_end
  ),
  days as (
    select child_id, bd from ev
    union
    select child_id, bd from ab
    union
    -- 単日ビュー(日別)は在籍児全員を含める(打刻漏れの入力用)。
    select c.id, p_start from children c
    where p_start = p_end and c.office_id = p_office_id and c.enrollment_status = '在籍中'
  )
  select c.id, c.display_name, cc.class_name, d.bd,
    (ev.in_ts     at time zone 'Asia/Tokyo')::time,
    (ev.out_ts    at time zone 'Asia/Tokyo')::time,
    (ev.ret_ts    at time zone 'Asia/Tokyo')::time,
    (ev.depart_ts at time zone 'Asia/Tokyo')::time,
    coalesce(ab.is_absent, false), ab.absence_reason
  from days d
  join children c on c.id = d.child_id
  left join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null
  left join childcare_classes cc on cc.id = cce.class_id
  left join ev on ev.child_id = d.child_id and ev.bd = d.bd
  left join ab on ab.child_id = d.child_id and ab.bd = d.bd
  where c.enrollment_status = '在籍中'
  order by cc.class_name nulls last, c.display_name, d.bd;
end $$;
grant execute on function fetch_attendance_matrix_for_office(uuid, date, date) to authenticated, service_role;
