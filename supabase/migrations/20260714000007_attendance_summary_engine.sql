-- 11章/12章 月次勤怠集計エンジン(Phase C 給与計算エンジンの入力となる集計値)
--
-- 出勤日数・所定労働時間・実労働時間・時間外(日/週/月)・深夜時間・法定休日時間・
-- 欠勤日数・遅刻早退回数を月単位で集計し attendance_summaries へ保存する。
-- 1ヶ月単位変形労働時間制(6.2の3条件: employment_type=正社員 かつ salary_type=月給
-- かつ work_time_system=1ヶ月単位変形労働時間制)は11.6(b)の日→週→月カスケード判定、
-- それ以外(通常労働時間制)は11.6(a)の日→週判定のみを適用する。
--
-- 手動トリガー(管理者Web/アプリ)と将来のSupabase Scheduled Functionの両方から
-- 呼べるよう、run_attendance_summary()は20260714000006のrun_paid_leave_auto_grant()
-- と同じ認可方針(ユーザーコンテキストがあれば労務管理者以上を要求、無ければ
-- 無人実行として許可)を採用する。内部ヘルパー関数は直接のRPC呼び出しから
-- 保護するためEXECUTEをanon/authenticatedから明示的にREVOKEする。

-- ============================================================
-- 11.2 丸めルール(給与算定用の承認済み時間にのみ適用。実打刻は一切変更しない)
-- ============================================================
create or replace function round_up_15(ts timestamptz)
returns timestamptz
language sql
immutable
as $$
  select date_trunc('hour', ts) + (ceil(extract(minute from ts) / 15.0) * 15) * interval '1 minute';
$$;

create or replace function round_down_15(ts timestamptz)
returns timestamptz
language sql
immutable
as $$
  select date_trunc('hour', ts) + (floor(extract(minute from ts) / 15.0) * 15) * interval '1 minute';
$$;

-- ============================================================
-- 11.1/11.2/11.3 実打刻から承認済み時間(丸め後)を導出する。
-- 既にapproved_work_start_atが設定済み(管理者による手動承認・修正済み)の行は
-- 上書きしない。休憩は55〜65分を60分automatically認定、それ以外は実測値を
-- 暫定適用しalert_codesへ'break_irregular'を記録する(11.3: 管理者判断が必要な
-- ケースを可視化するのみで、自動で残業/短縮等の会社判断は行わない)。
-- ============================================================
create or replace function derive_approved_daily_attendance(p_month_start date, p_month_end date)
returns void
language sql
as $$
  update daily_attendances da
  set
    approved_work_start_at = round_up_15(da.actual_clock_in_at),
    approved_work_end_at = round_down_15(da.actual_clock_out_at),
    approved_break_minutes = case
      when da.actual_break_start_at is not null and da.actual_break_end_at is not null then
        case
          when round(extract(epoch from (da.actual_break_end_at - da.actual_break_start_at)) / 60)
            between 55 and 65 then 60
          else round(extract(epoch from (da.actual_break_end_at - da.actual_break_start_at)) / 60)::int
        end
      else 0
    end,
    alert_codes = case
      when da.actual_break_start_at is not null and da.actual_break_end_at is not null
        and round(extract(epoch from (da.actual_break_end_at - da.actual_break_start_at)) / 60)
          not between 55 and 65
        and not ('break_irregular' = any(da.alert_codes))
      then array_append(da.alert_codes, 'break_irregular')
      else da.alert_codes
    end
  where da.work_date between p_month_start and p_month_end
    and da.actual_clock_in_at is not null
    and da.actual_clock_out_at is not null
    and da.approved_work_start_at is null;
$$;

revoke execute on function derive_approved_daily_attendance(date, date) from public, anon, authenticated;

-- ============================================================
-- 集計結果テーブル
-- ============================================================
create table attendance_summaries (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  target_month date not null, -- 日=01で保存
  attendance_days int not null default 0,
  prescribed_minutes int not null default 0,
  actual_worked_minutes int not null default 0,
  daily_overtime_minutes int not null default 0,
  weekly_overtime_minutes int not null default 0,
  monthly_overtime_minutes int not null default 0,
  overtime_minutes int not null default 0, -- 日+週+月の時間外合計
  overtime_over_60h_minutes int not null default 0, -- 月60時間超過分(50%対象)
  late_night_minutes int not null default 0, -- 22:00〜翌5:00
  statutory_holiday_minutes int not null default 0, -- 法定休日(日曜)労働
  absence_days int not null default 0,
  tardiness_early_leave_count int not null default 0,
  work_time_system work_time_system_type not null,
  computed_by uuid references employees(id), -- null=無人実行
  computed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (employee_id, target_month)
);
create index idx_attendance_summaries_employee on attendance_summaries(employee_id);
create index idx_attendance_summaries_month on attendance_summaries(target_month);

create table attendance_summary_runs (
  id uuid primary key default gen_random_uuid(),
  target_month date not null,
  run_by uuid references employees(id), -- null=無人実行(将来のScheduled Function等)
  total_employees int not null default 0,
  created_at timestamptz not null default now()
);

alter table attendance_summaries enable row level security;
alter table attendance_summary_runs enable row level security;

create policy attendance_summaries_select_self on attendance_summaries
  for select using (employee_id = my_employee_id());
create policy attendance_summaries_select_managers on attendance_summaries
  for select using (
    exists (
      select 1 from employees e
      where e.id = attendance_summaries.employee_id and manages_office(e.home_office_id)
    )
  );
create policy attendance_summary_runs_select_labor_manager on attendance_summary_runs
  for select using (is_labor_manager_plus());

-- ============================================================
-- 職員1名分の集計をtmp_attendance_daily(1日1行)へ展開し、
-- 日→週→月の順にカスケード判定してattendance_summariesへupsertする。
-- ============================================================
create or replace function compute_and_upsert_attendance_summary(
  p_employee_id uuid,
  p_month_start date,
  p_month_end date,
  p_legal_frame_minutes int,
  p_is_deformed boolean,
  p_computed_by uuid
)
returns void
language plpgsql
as $$
declare
  v_attendance_days int;
  v_prescribed_minutes int;
  v_actual_minutes int;
  v_statutory_holiday_minutes int;
  v_night_minutes int;
  v_daily_ot_minutes int;
  v_weekly_ot_minutes int;
  v_monthly_ot_minutes int;
  v_total_ot_minutes int;
  v_over_60h_minutes int;
  v_absence_days int;
  v_tardiness_count int;
begin
  create temporary table if not exists tmp_attendance_daily (
    work_date date primary key,
    week_start date not null,
    is_sunday boolean not null,
    prescribed_minutes int not null,
    actual_minutes int not null,
    night_minutes int not null,
    daily_ot_minutes int not null
  );
  delete from tmp_attendance_daily;

  insert into tmp_attendance_daily (
    work_date, week_start, is_sunday, prescribed_minutes, actual_minutes, night_minutes, daily_ot_minutes
  )
  select
    d.work_date, d.week_start, d.is_sunday, d.prescribed_minutes, d.actual_minutes, d.night_minutes,
    case
      when d.is_sunday then 0 -- 11.7: 法定休日労働に時間外の概念は適用しない
      when p_is_deformed then greatest(d.actual_minutes - greatest(d.prescribed_minutes, 480), 0)
      else greatest(d.actual_minutes - 480, 0)
    end
  from (
    select
      da.work_date,
      (da.work_date - extract(dow from da.work_date)::int) as week_start,
      (extract(dow from da.work_date) = 0) as is_sunday,
      coalesce(sh.prescribed_minutes, 0) as prescribed_minutes,
      greatest((
        extract(epoch from (da.approved_work_end_at - da.approved_work_start_at)) / 60
        - coalesce(da.approved_break_minutes, 0)
      )::int, 0) as actual_minutes,
      (
        greatest(0, extract(epoch from (
          least(da.approved_work_end_at, (da.work_date::timestamp + interval '29 hours') at time zone 'Asia/Tokyo')
          - greatest(da.approved_work_start_at, (da.work_date::timestamp + interval '22 hours') at time zone 'Asia/Tokyo')
        )) / 60)
        +
        greatest(0, extract(epoch from (
          least(da.approved_work_end_at, (da.work_date::timestamp + interval '5 hours') at time zone 'Asia/Tokyo')
          - greatest(da.approved_work_start_at, (da.work_date::timestamp - interval '2 hours') at time zone 'Asia/Tokyo')
        )) / 60)
      )::int as night_minutes
    from daily_attendances da
    left join lateral (
      select (
        extract(epoch from (
          case when s.end_time < s.start_time
            then (s.end_time - s.start_time + interval '24 hours')
            else (s.end_time - s.start_time)
          end
        )) / 60 - s.break_minutes
      )::int as prescribed_minutes
      from shifts s
      where s.employee_id = da.employee_id and s.work_date = da.work_date and s.status = 'confirmed'
      limit 1
    ) sh on true
    where da.employee_id = p_employee_id
      and da.work_date between p_month_start and p_month_end
      and da.approved_work_start_at is not null
      and da.approved_work_end_at is not null
  ) d;

  select
    count(*) filter (where actual_minutes > 0),
    coalesce(sum(prescribed_minutes), 0),
    coalesce(sum(actual_minutes), 0),
    coalesce(sum(actual_minutes) filter (where is_sunday), 0),
    coalesce(sum(night_minutes), 0),
    coalesce(sum(daily_ot_minutes), 0)
  into v_attendance_days, v_prescribed_minutes, v_actual_minutes, v_statutory_holiday_minutes,
       v_night_minutes, v_daily_ot_minutes
  from tmp_attendance_daily;

  -- 11.6(b)(2)/31章-4: 起算日曜が当月内にある週のみ週単位判定を行う。
  -- 法定休日(日曜)は時間外の概念対象外のため週の実労働から除外する。
  select coalesce(sum(
    greatest(
      week_actual - week_daily_ot - greatest(case when p_is_deformed then week_prescribed else 0 end, 2400),
      0
    )
  ), 0)
  into v_weekly_ot_minutes
  from (
    select
      week_start,
      sum(actual_minutes) filter (where not is_sunday) as week_actual,
      sum(daily_ot_minutes) filter (where not is_sunday) as week_daily_ot,
      sum(prescribed_minutes) filter (where not is_sunday) as week_prescribed
    from tmp_attendance_daily
    where week_start >= p_month_start
    group by week_start
  ) w;

  if p_is_deformed then
    v_monthly_ot_minutes := greatest(
      (v_actual_minutes - v_statutory_holiday_minutes) - v_daily_ot_minutes - v_weekly_ot_minutes
        - p_legal_frame_minutes,
      0
    );
  else
    v_monthly_ot_minutes := 0;
  end if;

  v_total_ot_minutes := v_daily_ot_minutes + v_weekly_ot_minutes + v_monthly_ot_minutes;
  v_over_60h_minutes := greatest(v_total_ot_minutes - 3600, 0);

  select count(*) into v_absence_days
  from requests
  where employee_id = p_employee_id
    and request_type = 'absence'
    and status = 'approved'
    and target_date between p_month_start and p_month_end;

  select count(*) into v_tardiness_count
  from requests
  where employee_id = p_employee_id
    and request_type = 'tardiness_early_leave'
    and status = 'approved'
    and target_date between p_month_start and p_month_end;

  insert into attendance_summaries (
    employee_id, target_month, attendance_days, prescribed_minutes, actual_worked_minutes,
    daily_overtime_minutes, weekly_overtime_minutes, monthly_overtime_minutes, overtime_minutes,
    overtime_over_60h_minutes, late_night_minutes, statutory_holiday_minutes,
    absence_days, tardiness_early_leave_count, work_time_system, computed_by
  )
  select
    p_employee_id, p_month_start, v_attendance_days, v_prescribed_minutes, v_actual_minutes,
    v_daily_ot_minutes, v_weekly_ot_minutes, v_monthly_ot_minutes, v_total_ot_minutes,
    v_over_60h_minutes, v_night_minutes, v_statutory_holiday_minutes,
    v_absence_days, v_tardiness_count, e.work_time_system, p_computed_by
  from employees e where e.id = p_employee_id
  on conflict (employee_id, target_month) do update set
    attendance_days = excluded.attendance_days,
    prescribed_minutes = excluded.prescribed_minutes,
    actual_worked_minutes = excluded.actual_worked_minutes,
    daily_overtime_minutes = excluded.daily_overtime_minutes,
    weekly_overtime_minutes = excluded.weekly_overtime_minutes,
    monthly_overtime_minutes = excluded.monthly_overtime_minutes,
    overtime_minutes = excluded.overtime_minutes,
    overtime_over_60h_minutes = excluded.overtime_over_60h_minutes,
    late_night_minutes = excluded.late_night_minutes,
    statutory_holiday_minutes = excluded.statutory_holiday_minutes,
    absence_days = excluded.absence_days,
    tardiness_early_leave_count = excluded.tardiness_early_leave_count,
    work_time_system = excluded.work_time_system,
    computed_by = excluded.computed_by,
    computed_at = now();
end;
$$;

revoke execute on function compute_and_upsert_attendance_summary(uuid, date, date, int, boolean, uuid)
  from public, anon, authenticated;

-- ============================================================
-- 月次勤怠集計エンジン本体。
-- ============================================================
create or replace function run_attendance_summary(p_target_month date default date_trunc('month', current_date)::date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_month_start date := date_trunc('month', p_target_month)::date;
  v_month_end date := (date_trunc('month', p_target_month) + interval '1 month' - interval '1 day')::date;
  v_calendar_days int := extract(day from v_month_end)::int;
  v_legal_frame_minutes int := floor(40.0 * 60 * v_calendar_days / 7)::int; -- 11.6(b)(3): 分単位切捨て
  v_run_id uuid;
  v_employee record;
  v_is_deformed boolean;
  v_total_employees int := 0;
begin
  if auth.uid() is not null and not is_labor_manager_plus() then
    raise exception 'not authorized to run attendance summary';
  end if;

  perform derive_approved_daily_attendance(v_month_start, v_month_end);

  insert into attendance_summary_runs (target_month, run_by)
  values (v_month_start, my_employee_id())
  returning id into v_run_id;

  for v_employee in
    select e.id, e.work_time_system, e.salary_type, et.name as employment_type_name
    from employees e
    join employment_types et on et.id = e.employment_type_id
    where e.hire_date <= v_month_end
      and (e.resignation_date is null or e.resignation_date >= v_month_start)
  loop
    v_is_deformed := (
      v_employee.employment_type_name = '正社員'
      and v_employee.salary_type = '月給'
      and v_employee.work_time_system = '1ヶ月単位変形労働時間制'
    );

    perform compute_and_upsert_attendance_summary(
      v_employee.id, v_month_start, v_month_end, v_legal_frame_minutes, v_is_deformed, my_employee_id()
    );
    v_total_employees := v_total_employees + 1;
  end loop;

  update attendance_summary_runs set total_employees = v_total_employees where id = v_run_id;
  return v_run_id;
end;
$$;
