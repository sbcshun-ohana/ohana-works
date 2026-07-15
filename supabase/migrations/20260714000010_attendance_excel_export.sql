-- 追加指示書2.2/2.3 月間勤怠Excel出力(施設ごとシート分割)用のデータ取得RPC。
--
-- fetch_attendance_by_office(20260714000009)は画面一覧向けの列構成だが、Excel出力
-- (2.3)は「シフト開始・終了/実休憩時間/承認済み休憩時間/有給/欠勤/遅刻/早退/勤務区分/
-- アラート」等、より多くの列を必要とするため専用のRPCとして分離する。
--
-- 対象日は「daily_attendancesが存在する日」だけでなく「有給/欠勤/遅刻早退の承認済み
-- 申請がある日」も含める(打刻が一切無い終日有給・終日欠勤の日もシートに表示するため)。
-- 代表施設の決定ロジック(その日最初のtime_punches.office_id、無ければhome_office_id)は
-- 20260714000009と同じ簡易ルールを踏襲する。
create or replace function fetch_attendance_export_by_office(
  p_office_id uuid,
  p_month_start date,
  p_month_end date
)
returns table (
  employee_id uuid,
  employee_name text,
  work_date date,
  office_id uuid,
  office_name text,
  shift_start_time time,
  shift_end_time time,
  shift_break_minutes int,
  shift_type text,
  actual_clock_in_at timestamptz,
  approved_work_start_at timestamptz,
  actual_clock_out_at timestamptz,
  approved_work_end_at timestamptz,
  actual_break_start_at timestamptz,
  actual_break_end_at timestamptz,
  approved_break_minutes int,
  has_paid_leave boolean,
  has_absence boolean,
  has_tardiness boolean,
  has_early_leave boolean,
  alert_codes text[]
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_office_id is not null and not manages_office(p_office_id) then
    raise exception 'not authorized to view attendance for this office';
  end if;
  if p_office_id is null and not is_labor_manager_plus() then
    raise exception 'not authorized to view all offices attendance ("全体" is labor manager and above only)';
  end if;

  return query
  with relevant_dates as (
    select da.employee_id, da.work_date
    from daily_attendances da
    where da.work_date between p_month_start and p_month_end
    union
    select r.employee_id, r.target_date as work_date
    from requests r
    where r.target_date between p_month_start and p_month_end
      and r.status = 'approved'
      and r.request_type in ('paid_leave', 'absence', 'tardiness_early_leave')
  )
  select
    rd.employee_id,
    e.name,
    rd.work_date,
    coalesce(rep.office_id, e.home_office_id),
    o.name,
    sh.start_time,
    sh.end_time,
    sh.break_minutes,
    sh.shift_type::text,
    da.actual_clock_in_at,
    da.approved_work_start_at,
    da.actual_clock_out_at,
    da.approved_work_end_at,
    da.actual_break_start_at,
    da.actual_break_end_at,
    da.approved_break_minutes,
    exists (
      select 1 from requests r
      where r.employee_id = rd.employee_id and r.target_date = rd.work_date
        and r.request_type = 'paid_leave' and r.status = 'approved'
    ),
    exists (
      select 1 from requests r
      where r.employee_id = rd.employee_id and r.target_date = rd.work_date
        and r.request_type = 'absence' and r.status = 'approved'
    ),
    exists (
      select 1 from requests r
      where r.employee_id = rd.employee_id and r.target_date = rd.work_date
        and r.request_type = 'tardiness_early_leave' and r.status = 'approved'
        and (r.details ->> 'sub_type') = 'tardiness'
    ),
    exists (
      select 1 from requests r
      where r.employee_id = rd.employee_id and r.target_date = rd.work_date
        and r.request_type = 'tardiness_early_leave' and r.status = 'approved'
        and (r.details ->> 'sub_type') = 'early_leave'
    ),
    coalesce(da.alert_codes, '{}')
  from relevant_dates rd
  join employees e on e.id = rd.employee_id
  left join daily_attendances da on da.employee_id = rd.employee_id and da.work_date = rd.work_date
  left join lateral (
    select tp.office_id
    from time_punches tp
    where tp.employee_id = rd.employee_id
      and tp.punched_at >= (rd.work_date::timestamp) at time zone 'Asia/Tokyo'
      and tp.punched_at < (rd.work_date::timestamp + interval '1 day') at time zone 'Asia/Tokyo'
    order by tp.punched_at asc
    limit 1
  ) rep on true
  join offices o on o.id = coalesce(rep.office_id, e.home_office_id)
  left join shifts sh on sh.employee_id = rd.employee_id and sh.work_date = rd.work_date and sh.status = 'confirmed'
  where (p_office_id is null or coalesce(rep.office_id, e.home_office_id) = p_office_id)
  order by e.name, rd.work_date;
end;
$$;
