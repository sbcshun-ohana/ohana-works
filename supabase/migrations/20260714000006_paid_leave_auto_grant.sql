-- 15.1 有給自動付与エンジン
--
-- 労基法39条準拠: 継続勤務6ヶ月(以後1年ごと)の基準日に、直前の基準期間の
-- 出勤率が8割以上の職員へ所定日数を付与する。付与日数は「通常の付与日数表」
-- (週5日以上または full_time_flag=true)と「比例付与日数表」(週1〜4日の
-- パート・非常勤)のいずれかを適用する。時効は付与日から2年(expiry_date)。
--
-- 手動トリガー(管理者Webからの実行)と将来のSupabase Scheduled Function
-- (pg_cron/Edge Function経由の無人実行)の両方から呼べるよう、
-- run_paid_leave_auto_grant() は「ユーザーコンテキストがあれば労務管理者以上を要求し、
-- ユーザーコンテキストが無い(service_role等の無人実行)場合はそのまま実行を許可する」
-- という認可方針にしている。

-- 同一職員・同一基準日への重複付与を防ぐ(手動実行の連打やレース条件への安全策)。
create unique index idx_leave_grants_employee_grant_date on leave_grants(employee_id, grant_date);

-- 実行履歴(サマリー)
create table leave_grant_runs (
  id uuid primary key default gen_random_uuid(),
  target_date date not null,
  run_by uuid references employees(id), -- null=無人実行(将来のScheduled Function等)
  total_evaluated int not null default 0,
  total_granted int not null default 0,
  total_skipped int not null default 0,
  created_at timestamptz not null default now()
);

-- 実行履歴(職員ごとの評価結果。監査・管理者への結果表示用)
create table leave_grant_run_results (
  id uuid primary key default gen_random_uuid(),
  leave_grant_run_id uuid not null references leave_grant_runs(id) on delete cascade,
  employee_id uuid not null references employees(id),
  milestone_date date not null, -- 評価した基準日
  prescribed_days int not null, -- 基準期間の所定労働日数
  attended_days int not null,   -- 出勤(みなし含む)日数
  attendance_rate numeric(5,4) not null,
  eligible boolean not null,
  granted_days numeric(5,1),
  basis text, -- 法定付与 / 比例付与
  leave_grant_id uuid references leave_grants(id),
  skip_reason text, -- 例: 出勤率8割未満
  created_at timestamptz not null default now()
);
create index idx_leave_grant_run_results_run on leave_grant_run_results(leave_grant_run_id);
create index idx_leave_grant_run_results_employee on leave_grant_run_results(employee_id);

alter table leave_grant_runs enable row level security;
alter table leave_grant_run_results enable row level security;

create policy leave_grant_runs_select_labor_manager on leave_grant_runs
  for select using (is_labor_manager_plus());
create policy leave_grant_run_results_select_labor_manager on leave_grant_run_results
  for select using (is_labor_manager_plus());

-- 継続勤務年数の区分(1=6ヶ月, 2=1年6ヶ月, ... 7以上=6年6ヶ月以上)に対する
-- 付与日数表(厚生労働省の法定付与日数表・比例付与日数表)。
create or replace function statutory_paid_leave_days(p_milestone_index int, p_weekly_scheduled_days int)
returns numeric
language sql
immutable
as $$
  select case
    when p_weekly_scheduled_days >= 5 then
      (array[10, 11, 12, 14, 16, 18, 20])[least(greatest(p_milestone_index, 1), 7)]
    when p_weekly_scheduled_days = 4 then
      (array[7, 8, 9, 10, 12, 13, 15])[least(greatest(p_milestone_index, 1), 7)]
    when p_weekly_scheduled_days = 3 then
      (array[5, 6, 6, 8, 9, 10, 11])[least(greatest(p_milestone_index, 1), 7)]
    when p_weekly_scheduled_days = 2 then
      (array[3, 4, 4, 5, 6, 6, 7])[least(greatest(p_milestone_index, 1), 7)]
    when p_weekly_scheduled_days = 1 then
      (array[1, 2, 2, 2, 3, 3, 3])[least(greatest(p_milestone_index, 1), 7)]
    else 0
  end::numeric;
$$;

-- 比例付与の週所定労働日数の判定。full_time_flag=trueは常に通常表(5)を適用する
-- (常勤は契約上週5日30h以上のため)。非常勤はp_as_of以前8週間の確定シフト実績
-- (休日区分を除く)から週平均日数を算出し1〜5に丸める。シフト実績が無い場合は
-- 判定不能のため通常表を暫定適用する(15.1の簡易ルール、実データ蓄積後に要見直し)。
create or replace function employee_weekly_scheduled_days(p_employee_id uuid, p_as_of date)
returns int
language plpgsql
stable
as $$
declare
  v_full_time boolean;
  v_days int;
begin
  select full_time_flag into v_full_time from employees where id = p_employee_id;
  if coalesce(v_full_time, true) then
    return 5;
  end if;

  select count(distinct work_date) into v_days
  from shifts
  where employee_id = p_employee_id
    and work_date >= p_as_of - 56
    and work_date < p_as_of
    and status = 'confirmed'
    and shift_type not in ('company_holiday', 'national_holiday', 'year_end_new_year_holiday');

  if v_days is null or v_days = 0 then
    return 5;
  end if;

  return greatest(1, least(5, round(v_days / 8.0)::int));
end;
$$;

-- 有給自動付与エンジン本体。
-- 職員ごとにhire_dateからの基準日(6ヶ月, 1年6ヶ月, ...)を順に評価し、
-- p_target_date以前で未付与のものについて基準期間の出勤率(8割要件)を判定、
-- 該当すればleave_grantsへ1行挿入する。leave_grants(employee_id, grant_date)の
-- unique indexにより同一基準日への重複付与は防止される。
create or replace function run_paid_leave_auto_grant(p_target_date date default current_date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_id uuid;
  v_employee record;
  v_milestone_index int;
  v_milestone_date date;
  v_period_start date;
  v_prescribed_days int;
  v_attended_days int;
  v_rate numeric;
  v_eligible boolean;
  v_weekly_days int;
  v_basis text;
  v_granted_days numeric;
  v_grant_id uuid;
  v_total_evaluated int := 0;
  v_total_granted int := 0;
  v_total_skipped int := 0;
begin
  -- ユーザーコンテキストがある(=アプリからの手動実行)場合は労務管理者以上を要求する。
  -- ユーザーコンテキストが無い(service_role等の無人実行、将来のScheduled Function用)
  -- 場合は認可済みの実行環境からの呼び出しとみなしてそのまま実行する。
  if auth.uid() is not null and not is_labor_manager_plus() then
    raise exception 'not authorized to run paid leave auto grant';
  end if;

  insert into leave_grant_runs (target_date, run_by)
  values (p_target_date, my_employee_id())
  returning id into v_run_id;

  for v_employee in
    select id, hire_date from employees
    where resignation_date is null or resignation_date >= p_target_date
  loop
    v_milestone_index := 1;
    loop
      v_milestone_date := (
        v_employee.hire_date + interval '6 months' + (v_milestone_index - 1) * interval '1 year'
      )::date;

      exit when v_milestone_date > p_target_date;

      if exists (
        select 1 from leave_grants
        where employee_id = v_employee.id and grant_date = v_milestone_date
      ) then
        v_milestone_index := v_milestone_index + 1;
        continue;
      end if;

      v_period_start := case
        when v_milestone_index = 1 then v_employee.hire_date
        else (
          v_employee.hire_date + interval '6 months' + (v_milestone_index - 2) * interval '1 year'
        )::date
      end;

      select count(*) into v_prescribed_days
      from shifts
      where employee_id = v_employee.id
        and work_date >= v_period_start and work_date < v_milestone_date
        and status = 'confirmed'
        and shift_type not in ('company_holiday', 'national_holiday', 'year_end_new_year_holiday');

      select count(distinct work_date) into v_attended_days
      from (
        select work_date from daily_attendances
        where employee_id = v_employee.id
          and work_date >= v_period_start and work_date < v_milestone_date
          and actual_clock_in_at is not null
        union
        select target_date from leave_usages
        where employee_id = v_employee.id
          and target_date >= v_period_start and target_date < v_milestone_date
      ) attended;

      v_rate := case when v_prescribed_days = 0 then 1.0
                     else v_attended_days::numeric / v_prescribed_days end;
      v_eligible := v_rate >= 0.8;
      v_total_evaluated := v_total_evaluated + 1;

      if v_eligible then
        v_weekly_days := employee_weekly_scheduled_days(v_employee.id, v_milestone_date);
        v_granted_days := statutory_paid_leave_days(v_milestone_index, v_weekly_days);
        v_basis := case when v_weekly_days >= 5 then '法定付与' else '比例付与' end;

        insert into leave_grants (employee_id, granted_days, grant_date, expiry_date, basis, created_by)
        values (
          v_employee.id, v_granted_days, v_milestone_date,
          (v_milestone_date + interval '2 years')::date, v_basis, my_employee_id()
        )
        returning id into v_grant_id;

        v_total_granted := v_total_granted + 1;

        insert into leave_grant_run_results (
          leave_grant_run_id, employee_id, milestone_date, prescribed_days, attended_days,
          attendance_rate, eligible, granted_days, basis, leave_grant_id
        ) values (
          v_run_id, v_employee.id, v_milestone_date, v_prescribed_days, v_attended_days,
          v_rate, true, v_granted_days, v_basis, v_grant_id
        );
      else
        v_total_skipped := v_total_skipped + 1;
        insert into leave_grant_run_results (
          leave_grant_run_id, employee_id, milestone_date, prescribed_days, attended_days,
          attendance_rate, eligible, granted_days, skip_reason
        ) values (
          v_run_id, v_employee.id, v_milestone_date, v_prescribed_days, v_attended_days,
          v_rate, false, 0, '出勤率8割未満'
        );
      end if;

      v_milestone_index := v_milestone_index + 1;
    end loop;
  end loop;

  update leave_grant_runs set
    total_evaluated = v_total_evaluated,
    total_granted = v_total_granted,
    total_skipped = v_total_skipped
  where id = v_run_id;

  return v_run_id;
end;
$$;
