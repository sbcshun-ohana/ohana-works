-- 373: 372の是正(Fableレビュー指摘・俊確認 2026-08-27)。
--   upsert_shift_exception は 120(通知)→ 351(別施設重複ガード・ただし通知insertを落としていた)→ 372(通知復活・
--   給食リマインド・ただし351のガードを落としていた)と変遷し、351のガードと120/372の通知が両立していなかった。
--   本migrationで「351の別施設重複ガード」+「120/372のシフト変更通知(給食有効施設は給食予定の確認を追記)」を
--   マージした正版に統一する。delete_shift_exception は372版(通知+給食リマインド)のままで整合。

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
  v_other_name text;
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

  -- 351: 出勤例外は「別施設で同日・時間帯の重なる確定シフト」があれば重複エラー(休みは対象外)。
  if not p_is_day_off then
    select o.name into v_other_name
      from shifts sh join offices o on o.id = sh.office_id
      where sh.employee_id = p_employee_id and sh.work_date = p_work_date
        and sh.office_id <> v_office
        and sh.start_time < p_end_time and p_start_time < sh.end_time
      limit 1;
    if v_other_name is not null then
      raise exception '同じ職員が別施設(%)の同じ日(%)に時間帯の重なる勤務があります。重複するため登録できません。', v_other_name, p_work_date;
    end if;
  end if;

  insert into shift_exceptions (employee_id, work_date, is_day_off, office_id, start_time, end_time, break_minutes, note, created_by, updated_by)
  values (p_employee_id, p_work_date, p_is_day_off, p_office_id, p_start_time, p_end_time, p_break_minutes, p_note, my_employee_id(), my_employee_id())
  on conflict (employee_id, work_date) do update
    set is_day_off = excluded.is_day_off, office_id = excluded.office_id, start_time = excluded.start_time,
        end_time = excluded.end_time, break_minutes = excluded.break_minutes, note = excluded.note,
        updated_by = my_employee_id(), updated_at = now();

  -- 120 + 372: シフト変更通知。給食が本人事前注文の施設では給食予定の確認を追記(自動増減はしない)。
  v_meal := is_meal_management_enabled_for_office(v_office);
  v_body := to_char(p_work_date, 'yyyy年mm月dd日') || 'のシフトが' ||
    case when p_is_day_off then '休みに変更されました' else '変更されました(' || p_start_time::text || '〜' || p_end_time::text || ')' end;
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
