-- 326: 登降園 Phase G(保護者向け実績表示)。保護者が自分の子の月間登降園実績(出欠+登降園時刻)を閲覧するRPC。
-- 料金・要確認・備考(職員内部)は返さない(俊方針: 実績時刻は即時表示・料金は請求公開後のみ)。
-- 権限=guardian_has_child_access(自分に紐づく子のみ)。
create or replace function fetch_child_attendance_month_for_guardian(p_child_id uuid, p_year int, p_month int)
returns table (
  business_date date, in_time time, out_time time, return_time time, depart_time time,
  is_absent boolean, absence_kind text
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_start date; v_end date;
begin
  if not guardian_has_child_access(p_child_id) then raise exception 'not authorized'; end if;
  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + interval '1 month - 1 day')::date;
  return query
  with ev as (
    select (e.occurred_at at time zone 'Asia/Tokyo')::date as bd,
      min(e.occurred_at) filter (where e.event_type in ('drop_off','proxy_drop_off')) as in_ts,
      max(e.occurred_at) filter (where e.event_type in ('pick_up','proxy_pick_up'))   as depart_ts,
      max(e.occurred_at) filter (where e.event_type = 'out')    as out_ts,
      max(e.occurred_at) filter (where e.event_type = 'return') as ret_ts
    from child_attendance_events e
    where e.child_id = p_child_id
      and (e.occurred_at at time zone 'Asia/Tokyo')::date between v_start and v_end
    group by (e.occurred_at at time zone 'Asia/Tokyo')::date
  ),
  ab as (
    select a.business_date as bd, a.is_absent, a.attendance_kind
    from child_daily_attendance a
    where a.child_id = p_child_id and a.business_date between v_start and v_end
  ),
  days as (select ev.bd from ev union select ab.bd from ab)
  select d.bd,
    (ev.in_ts     at time zone 'Asia/Tokyo')::time,
    (ev.out_ts    at time zone 'Asia/Tokyo')::time,
    (ev.ret_ts    at time zone 'Asia/Tokyo')::time,
    (ev.depart_ts at time zone 'Asia/Tokyo')::time,
    coalesce(ab.is_absent, false), ab.attendance_kind
  from days d
  left join ev on ev.bd = d.bd
  left join ab on ab.bd = d.bd
  order by d.bd;
end $$;
grant execute on function fetch_child_attendance_month_for_guardian(uuid, int, int) to authenticated, service_role;
