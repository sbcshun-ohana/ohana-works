-- P0: イベント駆動プッシュ通知の自動化(3/4: シフト変更)。
--
-- 週次テンプレート(shift_weekly_templates)は職員の基本パターン設定であり、対象日単位の
-- 「予定変更」の実感が薄いため通知対象としない。イレギュラー例外(shift_exceptions)は
-- 特定日を通常予定から変更する操作そのものであるため、ここを「シフト変更」イベントの
-- 発火点とする(upsert=登録・変更、delete=特例の取り消し=通常予定への復帰)。

create or replace function upsert_shift_exception(
  p_employee_id uuid, p_work_date date, p_is_day_off boolean, p_office_id uuid default null,
  p_start_time time default null, p_end_time time default null, p_break_minutes int default null,
  p_note text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_home_office_id uuid;
  v_body text;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(coalesce(p_office_id, v_home_office_id)) then
    raise exception 'not authorized';
  end if;
  if not p_is_day_off and (p_start_time is null or p_end_time is null) then
    raise exception 'start_time/end_time are required unless is_day_off';
  end if;

  insert into shift_exceptions (employee_id, work_date, is_day_off, office_id, start_time, end_time, break_minutes, note, created_by, updated_by)
  values (p_employee_id, p_work_date, p_is_day_off, p_office_id, p_start_time, p_end_time, p_break_minutes, p_note, my_employee_id(), my_employee_id())
  on conflict (employee_id, work_date) do update
    set is_day_off = excluded.is_day_off, office_id = excluded.office_id, start_time = excluded.start_time,
        end_time = excluded.end_time, break_minutes = excluded.break_minutes, note = excluded.note,
        updated_by = my_employee_id(), updated_at = now();

  v_body := to_char(p_work_date, 'yyyy年mm月dd日') || 'のシフトが' ||
    case when p_is_day_off then '休みに変更されました' else '変更されました(' || p_start_time::text || '〜' || p_end_time::text || ')' end;

  insert into notifications (
    notification_type, title, body, channels, target_employee_id, payload, status
  ) values (
    'shift_changed', 'シフトが変更されました', v_body, array['fcm', 'in_app'], p_employee_id,
    jsonb_build_object('work_date', p_work_date), 'pending'
  );
end;
$$;

create or replace function delete_shift_exception(p_employee_id uuid, p_work_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_home_office_id uuid;
  v_existed boolean;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(v_home_office_id) then
    raise exception 'not authorized';
  end if;

  v_existed := exists (select 1 from shift_exceptions where employee_id = p_employee_id and work_date = p_work_date);

  delete from shift_exceptions where employee_id = p_employee_id and work_date = p_work_date;

  if v_existed then
    insert into notifications (
      notification_type, title, body, channels, target_employee_id, payload, status
    ) values (
      'shift_changed', 'シフトが変更されました',
      to_char(p_work_date, 'yyyy年mm月dd日') || 'の特例予定が取り消され、通常のシフトに戻りました',
      array['fcm', 'in_app'], p_employee_id, jsonb_build_object('work_date', p_work_date), 'pending'
    );
  end if;
end;
$$;
