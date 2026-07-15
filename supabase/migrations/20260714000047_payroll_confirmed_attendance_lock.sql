-- 17.4: 給与確定後の勤怠ロック。
--
-- 現状、correct_daily_attendanceは対象月の給与確定状態を一切確認せず、
-- 給与確定(confirmed)・振込済み(transferred)後も無制限に勤怠を編集できて
-- しまっていた。対象月にpayroll_runsが存在し、かつstatusがconfirmed/
-- transferredの場合は編集を拒否する。
--
-- 修正が必要な場合のフロー: 給与確定解除(unlock_payroll_run、
-- system_admin限定)→勤怠修正→給与再計算(run_payroll、既存draft行を
-- 再利用して再計算する設計のため二重登録は発生しない)→再確定
-- (confirm_payroll_run)。既存のconfirm/unlock/mark_transferredの
-- ステータス遷移(draft⇄confirmed→transferred、transferredは解除不可)と
-- 矛盾なく組み合わさる。

create or replace function correct_daily_attendance(
  p_employee_id uuid,
  p_work_date date,
  p_field text,
  p_reason text,
  p_new_timestamp_value timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_new_int_value integer DEFAULT NULL::integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_home_office_id uuid;
  v_row_id uuid;
  v_actual_clock_out timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_payroll_status payroll_run_status;
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

  select status into v_payroll_status from payroll_runs
  where target_month = date_trunc('month', p_work_date)::date;

  if v_payroll_status = 'transferred' then
    raise exception '振込実行済み(%)の勤怠は編集できません(33章)', to_char(p_work_date, 'YYYY年MM月');
  elsif v_payroll_status = 'confirmed' then
    raise exception '給与確定済み(%)の勤怠は編集できません。/payroll画面で給与確定を解除してから修正し、再計算・再確定してください(17.4)', to_char(p_work_date, 'YYYY年MM月');
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
$function$;

-- /attendance画面で対象月の給与確定状態を事前に表示できるようにする
-- (payroll_runsはis_labor_manager_plus()限定のRLSのため、主任等では
-- 直接SELECTできない。ステータスのみを返す軽量なSECURITY DEFINER RPCを
-- 別途用意する)。
create or replace function fetch_payroll_lock_status(p_month date)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select status::text from payroll_runs where target_month = date_trunc('month', p_month)::date;
$$;
