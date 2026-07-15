-- 管理者Web(Next.js) 施設選択・施設別勤怠一覧・実打刻管理
-- 追加指示書(docs/Ohana_Works_追加指示書_施設選択_施設別勤怠_実打刻管理.md)準拠
--
-- attendance_segments は現状どの打刻経路からも書き込まれておらず(打刻はtime_punches/
-- daily_attendancesのみを更新)、施設別の実データは持っていない。そのため
-- 「施設で勤務した勤怠」の判定は、その日最初のtime_punches.office_id(打刻施設)を
-- 代表施設とし、打刻が無い日は職員の基本所属(home_office_id)を代表施設として扱う
-- 簡易ルールで実装する(2.1の「attendance_segmentsのoffice_id単位」という理想形に対する
-- 現時点の近似。真の複数施設セグメント按分は14章の別実装が必要)。
--
-- 実打刻・承認済み時刻の修正はcorrect_daily_attendance()経由のみとし、直接のUPDATEは
-- 許可しない(RLSのUPDATEポリシーは追加せず、SECURITY DEFINER関数内で3.3の権限
-- (主任以上=manages_office)を検証する)。daily_attendancesは27章のDBトリガーにより
-- UPDATE時に自動でevent_logsへ記録されるが、trigger起因のログには理由(reason)が
-- 含まれないため、本関数はさらにoperation_source='app'の行を理由付きで追加記録する
-- (20260710160005のコメント通り「DBトリガーによる自動記録+アプリ層ログの二重化」)。

-- 1.1/1.2 施設選択フィルターの選択肢(権限に応じて出し分け)
create or replace function fetch_my_manageable_offices()
returns table (id uuid, name text, can_select_all boolean)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if is_labor_manager_plus() then
    return query select o.id, o.name, true from offices o where o.status = '稼働中' order by o.name;
  else
    return query
    select distinct o.id, o.name, false
    from offices o
    where o.status = '稼働中'
      and (
        exists (
          select 1 from employee_roles er
          where er.employee_id = my_employee_id() and er.office_id = o.id
        )
        or exists (
          select 1 from employee_office_assignments eoa
          where eoa.employee_id = my_employee_id() and eoa.office_id = o.id
            and eoa.end_date is null
        )
      )
    order by o.name;
  end if;
end;
$$;

-- 2.2 施設選択時はその施設で勤務した勤怠のみ、p_office_id=nullは「全体」(労務管理者以上のみ)
create or replace function fetch_attendance_by_office(
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
  actual_clock_in_at timestamptz,
  approved_work_start_at timestamptz,
  actual_clock_out_at timestamptz,
  approved_work_end_at timestamptz,
  actual_break_start_at timestamptz,
  actual_break_end_at timestamptz,
  approved_break_minutes int,
  shift_type text,
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
  select
    da.employee_id,
    e.name,
    da.work_date,
    coalesce(rep.office_id, e.home_office_id),
    o.name,
    da.actual_clock_in_at,
    da.approved_work_start_at,
    da.actual_clock_out_at,
    da.approved_work_end_at,
    da.actual_break_start_at,
    da.actual_break_end_at,
    da.approved_break_minutes,
    da.shift_type::text,
    da.alert_codes
  from daily_attendances da
  join employees e on e.id = da.employee_id
  left join lateral (
    select tp.office_id
    from time_punches tp
    where tp.employee_id = da.employee_id
      and tp.punched_at >= (da.work_date::timestamp) at time zone 'Asia/Tokyo'
      and tp.punched_at < (da.work_date::timestamp + interval '1 day') at time zone 'Asia/Tokyo'
    order by tp.punched_at asc
    limit 1
  ) rep on true
  join offices o on o.id = coalesce(rep.office_id, e.home_office_id)
  where da.work_date between p_month_start and p_month_end
    and (p_office_id is null or coalesce(rep.office_id, e.home_office_id) = p_office_id)
  order by da.work_date, e.name;
end;
$$;

-- 3.3 実打刻・承認済み勤務時刻の個別修正(主任以上)。理由は必須。
create or replace function correct_daily_attendance(
  p_employee_id uuid,
  p_work_date date,
  p_field text,
  p_reason text,
  p_new_timestamp_value timestamptz default null,
  p_new_int_value int default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_home_office_id uuid;
  v_row_id uuid;
  v_actual_clock_out timestamptz;
  v_before jsonb;
  v_after jsonb;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason is required';
  end if;
  if p_field not in (
    'actual_clock_in_at', 'actual_clock_out_at', 'actual_break_start_at', 'actual_break_end_at',
    'approved_work_start_at', 'approved_work_end_at', 'approved_break_minutes'
  ) then
    raise exception 'unknown field: %', p_field;
  end if;

  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(v_home_office_id) then
    raise exception 'not authorized to correct attendance for this employee';
  end if;

  select id, to_jsonb(da) into v_row_id, v_before
  from daily_attendances da
  where employee_id = p_employee_id and work_date = p_work_date;

  if v_row_id is null then
    insert into daily_attendances (employee_id, work_date)
    values (p_employee_id, p_work_date)
    returning id into v_row_id;
  end if;

  if p_field = 'approved_work_end_at' then
    select actual_clock_out_at into v_actual_clock_out from daily_attendances where id = v_row_id;
    if v_actual_clock_out is not null and p_new_timestamp_value is not null
      and p_new_timestamp_value > v_actual_clock_out then
      raise exception '承認済み退勤時刻は実退勤打刻を超えて設定できません(11.2)';
    end if;
  end if;

  if p_field = 'actual_clock_in_at' then
    update daily_attendances set actual_clock_in_at = p_new_timestamp_value where id = v_row_id;
  elsif p_field = 'actual_clock_out_at' then
    update daily_attendances set actual_clock_out_at = p_new_timestamp_value where id = v_row_id;
  elsif p_field = 'actual_break_start_at' then
    update daily_attendances set actual_break_start_at = p_new_timestamp_value where id = v_row_id;
  elsif p_field = 'actual_break_end_at' then
    update daily_attendances set actual_break_end_at = p_new_timestamp_value where id = v_row_id;
  elsif p_field = 'approved_work_start_at' then
    update daily_attendances set approved_work_start_at = p_new_timestamp_value where id = v_row_id;
  elsif p_field = 'approved_work_end_at' then
    update daily_attendances set approved_work_end_at = p_new_timestamp_value where id = v_row_id;
  elsif p_field = 'approved_break_minutes' then
    update daily_attendances set approved_break_minutes = p_new_int_value where id = v_row_id;
  end if;

  select to_jsonb(da) into v_after from daily_attendances da where id = v_row_id;

  -- 27章のDBトリガー(operation_source='db_trigger')に加え、理由付きのアプリ層ログを記録する。
  insert into event_logs (
    operator_id, target_type, target_id, action, before_data, after_data, reason, operation_source
  ) values (
    my_employee_id(), 'daily_attendances', v_row_id, 'correct:' || p_field, v_before, v_after, p_reason, 'app'
  );
end;
$$;
