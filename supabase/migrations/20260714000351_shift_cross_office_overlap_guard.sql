-- 351: シフト作成時の「別施設・同日/同曜日の重複」ガード(俊指示 2026-08-26)。
--   背景: shifts/shift_exceptions は unique(employee_id, work_date)、shift_weekly_templates は
--         unique(employee_id, weekday) のため二重計上は構造的に起きない。だが現状の on conflict do update は
--         別施設の既存シフトを「黙って上書き」してしまい、管理者が重複入力に気づけない。
--   対応: 登録時点で「同じ職員が別施設に同曜日(テンプレート)/同日・同時間帯(例外)で既に登録済み」なら
--         登録を止めて明示エラー(UIはこのメッセージをアラート表示)。同一施設の更新は従来どおり許可。

-- (1) 週次テンプレート: 別施設で同じ曜日に既存があれば重複エラー。
create or replace function upsert_shift_weekly_template(
  p_employee_id uuid, p_office_id uuid, p_weekday int,
  p_start_time time, p_end_time time, p_break_minutes int default 0
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_other_office uuid; v_other_name text;
begin
  if not manages_office(p_office_id) then
    raise exception 'not authorized';
  end if;

  -- 別施設で同じ曜日に既にテンプレートがある場合は重複(1職員=1曜日1施設)。
  select office_id into v_other_office from shift_weekly_templates
    where employee_id = p_employee_id and weekday = p_weekday and office_id <> p_office_id;
  if v_other_office is not null then
    select name into v_other_name from offices where id = v_other_office;
    raise exception '同じ職員が別施設(%)の同じ曜日に既にシフト登録されています。時間帯が重複するため登録できません。先に該当シフトを削除してください。', coalesce(v_other_name, '別施設');
  end if;

  insert into shift_weekly_templates (employee_id, office_id, weekday, start_time, end_time, break_minutes, created_by, updated_by)
  values (p_employee_id, p_office_id, p_weekday, p_start_time, p_end_time, p_break_minutes, my_employee_id(), my_employee_id())
  on conflict (employee_id, weekday) do update
    set office_id = excluded.office_id, start_time = excluded.start_time, end_time = excluded.end_time,
        break_minutes = excluded.break_minutes, updated_by = my_employee_id(), updated_at = now();
end;
$$;

-- (2) 例外(単日シフト): 別施設で同日に時間帯が重なる確定シフトがあれば重複エラー。
create or replace function upsert_shift_exception(
  p_employee_id uuid, p_work_date date, p_is_day_off boolean, p_office_id uuid default null,
  p_start_time time default null, p_end_time time default null, p_break_minutes int default null,
  p_note text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_home_office_id uuid; v_office uuid; v_other_name text;
begin
  select home_office_id into v_home_office_id from employees where id = p_employee_id;
  if v_home_office_id is null or not manages_office(coalesce(p_office_id, v_home_office_id)) then
    raise exception 'not authorized';
  end if;
  if not p_is_day_off and (p_start_time is null or p_end_time is null) then
    raise exception 'start_time/end_time are required unless is_day_off';
  end if;

  -- 出勤例外の場合のみ重複チェック(休みは重複対象外)。
  if not p_is_day_off then
    v_office := coalesce(p_office_id, v_home_office_id);
    -- 別施設で同日に時間帯が重なる確定シフトがあれば重複。
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
end;
$$;
