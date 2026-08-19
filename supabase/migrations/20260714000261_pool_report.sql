-- 261: 夏期のプール活動◯×連絡(家庭連絡帳)。俊確定2026-08-20。
-- 施設設定 pool_report_enabled をON(夏期のみ)にすると、保護者アプリの家庭連絡帳に「プール ◯/×」欄が出る。
-- 任意入力(毎日必須ではない)。園はこれを見て当日のプール可否を確認。送り忘れは保護者管理。

-- 施設別トグル(既定OFF・管理者以上がON/OFF)
alter table childcare_office_settings
  add column if not exists pool_report_enabled boolean not null default false;

-- 家庭連絡帳のプール参加(◯=true / ×=false / null=未回答)
alter table family_daily_reports
  add column if not exists pool_participation boolean;

-- 施設のプール連絡が有効か(保護者アプリの欄表示・園側表示の出し分け)
create or replace function is_pool_report_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select pool_report_enabled from childcare_office_settings where office_id = p_office_id), false);
$$;
grant execute on function is_pool_report_enabled_for_office(uuid) to anon, authenticated, service_role;

-- プール連絡の有効化/無効化(管理者以上・夏期トグル)
create or replace function set_pool_report_enabled(p_office_id uuid, p_enabled boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not is_childcare_admin(p_office_id) then raise exception 'not authorized'; end if;
  insert into childcare_office_settings (office_id, pool_report_enabled, updated_by)
  values (p_office_id, p_enabled, my_employee_id())
  on conflict (office_id) do update set pool_report_enabled = p_enabled, updated_by = my_employee_id(), updated_at = now();
end;
$$;
grant execute on function set_pool_report_enabled(uuid, boolean) to authenticated, service_role;

-- 家庭連絡帳の保存に p_pool_participation を追加(124から拡張)。引数追加=別シグネチャのため旧版をdrop。
drop function if exists upsert_family_daily_report(
  uuid, date, numeric, time, text, text, text, text, int, text, int, text, time, time,
  text, time, text, time, text, text, time, time
);
create or replace function upsert_family_daily_report(
  p_child_id uuid,
  p_business_date date,
  p_temperature numeric,
  p_temperature_measured_at time,
  p_symptoms text,
  p_home_notes text,
  p_night_mood text default null,
  p_morning_mood text default null,
  p_night_bowel_count int default null,
  p_night_bowel_condition text default null,
  p_morning_bowel_count int default null,
  p_morning_bowel_condition text default null,
  p_sleep_start_at time default null,
  p_sleep_end_at time default null,
  p_dinner_content text default null,
  p_dinner_at time default null,
  p_breakfast_content text default null,
  p_breakfast_at time default null,
  p_pickup_person_name text default null,
  p_pickup_person_relationship text default null,
  p_pickup_time_from time default null,
  p_pickup_time_to time default null,
  p_pool_participation boolean default null
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_report family_daily_reports%rowtype;
  v_report_id uuid;
  v_before jsonb;
  v_after jsonb;
begin
  if not guardian_has_child_access(p_child_id) then
    raise exception 'not authorized';
  end if;

  select * into v_report from family_daily_reports
  where child_id = p_child_id and business_date = p_business_date
  for update;

  if v_report.id is null then
    insert into family_daily_reports (
      child_id, business_date, guardian_id, temperature, temperature_measured_at, symptoms, home_notes,
      night_mood, morning_mood, night_bowel_count, night_bowel_condition, morning_bowel_count, morning_bowel_condition,
      sleep_start_at, sleep_end_at, dinner_content, dinner_at, breakfast_content, breakfast_at,
      pickup_person_name, pickup_person_relationship, pickup_time_from, pickup_time_to, pool_participation
    ) values (
      p_child_id, p_business_date, my_guardian_id(), p_temperature, p_temperature_measured_at, p_symptoms, p_home_notes,
      p_night_mood, p_morning_mood, p_night_bowel_count, p_night_bowel_condition, p_morning_bowel_count, p_morning_bowel_condition,
      p_sleep_start_at, p_sleep_end_at, p_dinner_content, p_dinner_at, p_breakfast_content, p_breakfast_at,
      p_pickup_person_name, p_pickup_person_relationship, p_pickup_time_from, p_pickup_time_to, p_pool_participation
    )
    returning id into v_report_id;
    return v_report_id;
  end if;

  if v_report.status <> 'draft' then
    raise exception 'family daily report is % and cannot be edited', v_report.status;
  end if;

  v_before := to_jsonb(v_report);
  update family_daily_reports
  set temperature = p_temperature,
      temperature_measured_at = p_temperature_measured_at,
      symptoms = p_symptoms,
      home_notes = p_home_notes,
      night_mood = p_night_mood,
      morning_mood = p_morning_mood,
      night_bowel_count = p_night_bowel_count,
      night_bowel_condition = p_night_bowel_condition,
      morning_bowel_count = p_morning_bowel_count,
      morning_bowel_condition = p_morning_bowel_condition,
      sleep_start_at = p_sleep_start_at,
      sleep_end_at = p_sleep_end_at,
      dinner_content = p_dinner_content,
      dinner_at = p_dinner_at,
      breakfast_content = p_breakfast_content,
      breakfast_at = p_breakfast_at,
      pickup_person_name = p_pickup_person_name,
      pickup_person_relationship = p_pickup_person_relationship,
      pickup_time_from = p_pickup_time_from,
      pickup_time_to = p_pickup_time_to,
      pool_participation = p_pool_participation
  where id = v_report.id
  returning to_jsonb(family_daily_reports.*) into v_after;

  insert into family_daily_report_revisions (report_id, revised_by, before_values, after_values)
  values (v_report.id, my_guardian_id(), v_before, v_after);

  return v_report.id;
end;
$$;
grant execute on function upsert_family_daily_report(
  uuid, date, numeric, time, text, text, text, text, int, text, int, text, time, time,
  text, time, text, time, text, text, time, time, boolean
) to authenticated, service_role;
