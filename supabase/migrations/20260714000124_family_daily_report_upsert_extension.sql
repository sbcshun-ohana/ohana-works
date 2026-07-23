-- upsert_family_daily_report() を機嫌・排便・睡眠・食事・お迎え変更連絡の新項目に対応させる。
-- 既存呼び出し(旧クライアント)との後方互換のため、新パラメータは全てdefault nullで末尾に追加する。

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
  p_pickup_time_to time default null
)
returns uuid
language plpgsql
security definer
set search_path = public
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
      pickup_person_name, pickup_person_relationship, pickup_time_from, pickup_time_to
    ) values (
      p_child_id, p_business_date, my_guardian_id(), p_temperature, p_temperature_measured_at, p_symptoms, p_home_notes,
      p_night_mood, p_morning_mood, p_night_bowel_count, p_night_bowel_condition, p_morning_bowel_count, p_morning_bowel_condition,
      p_sleep_start_at, p_sleep_end_at, p_dinner_content, p_dinner_at, p_breakfast_content, p_breakfast_at,
      p_pickup_person_name, p_pickup_person_relationship, p_pickup_time_from, p_pickup_time_to
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
      pickup_time_to = p_pickup_time_to
  where id = v_report.id
  returning to_jsonb(family_daily_reports.*) into v_after;

  insert into family_daily_report_revisions (report_id, revised_by, before_values, after_values)
  values (v_report.id, my_guardian_id(), v_before, v_after);

  return v_report.id;
end;
$$;
