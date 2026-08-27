-- 372: 職員給食 自己注文モデル UI⑥ — シフト変更通知に「給食予定の確認」を促す一文を追加(俊指示 2026-08-27)。
--   既存の shift_changed 通知(120: upsert/delete_shift_exception)はそのまま活かし、給食が本人事前注文の
--   施設(meal_management_enabled)では、シフト変更時に給食の注文予定を確認するよう本文へ1行追記する。
--   ※自動で給食を増減はしない(通知のみ)。設計どおり給食の実体は本人の注文が源泉。

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
  v_office uuid;
  v_meal boolean;
  v_body text;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(coalesce(p_office_id, v_home_office_id)) then
    raise exception 'not authorized';
  end if;
  if not p_is_day_off and (p_start_time is null or p_end_time is null) then
    raise exception 'start_time/end_time are required unless is_day_off';
  end if;
  v_office := coalesce(p_office_id, v_home_office_id);
  v_meal := is_meal_management_enabled_for_office(v_office);

  insert into shift_exceptions (employee_id, work_date, is_day_off, office_id, start_time, end_time, break_minutes, note, created_by, updated_by)
  values (p_employee_id, p_work_date, p_is_day_off, p_office_id, p_start_time, p_end_time, p_break_minutes, p_note, my_employee_id(), my_employee_id())
  on conflict (employee_id, work_date) do update
    set is_day_off = excluded.is_day_off, office_id = excluded.office_id, start_time = excluded.start_time,
        end_time = excluded.end_time, break_minutes = excluded.break_minutes, note = excluded.note,
        updated_by = my_employee_id(), updated_at = now();

  v_body := to_char(p_work_date, 'yyyy年mm月dd日') || 'のシフトが' ||
    case when p_is_day_off then '休みに変更されました' else '変更されました(' || p_start_time::text || '〜' || p_end_time::text || ')' end;
  -- 給食が本人事前注文の施設では、給食の注文予定の確認を促す(自動増減はしない)。
  if v_meal then
    v_body := v_body || E'\n給食の注文予定も確認してください(給食の注文画面)。';
  end if;

  insert into notifications (
    notification_type, title, body, channels, target_employee_id, payload, status
  ) values (
    'shift_changed', 'シフトが変更されました', v_body, array['fcm', 'in_app'], p_employee_id,
    jsonb_build_object('work_date', p_work_date, 'check_meal', v_meal), 'pending'
  );
end;
$$;

create or replace function delete_shift_exception(p_employee_id uuid, p_work_date date)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_home_office_id uuid;
  v_meal boolean;
  v_existed boolean;
  v_body text;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(v_home_office_id) then
    raise exception 'not authorized';
  end if;
  v_meal := is_meal_management_enabled_for_office(v_home_office_id);

  v_existed := exists (select 1 from shift_exceptions where employee_id = p_employee_id and work_date = p_work_date);

  delete from shift_exceptions where employee_id = p_employee_id and work_date = p_work_date;

  if v_existed then
    v_body := to_char(p_work_date, 'yyyy年mm月dd日') || 'の特例予定が取り消され、通常のシフトに戻りました';
    if v_meal then
      v_body := v_body || E'\n給食の注文予定も確認してください(給食の注文画面)。';
    end if;
    insert into notifications (
      notification_type, title, body, channels, target_employee_id, payload, status
    ) values (
      'shift_changed', 'シフトが変更されました', v_body,
      array['fcm', 'in_app'], p_employee_id, jsonb_build_object('work_date', p_work_date, 'check_meal', v_meal), 'pending'
    );
  end if;
end;
$$;
