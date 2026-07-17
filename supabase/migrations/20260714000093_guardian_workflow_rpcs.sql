-- 保護者アプリ Phase A: 登降園ステータス集約・家庭連絡帳・保護者申請・クラス写真公開のRPC

-- 登降園イベント記録後に呼び出し、当日の集約ステータスを再計算する。
-- 実際のイベントINSERT自体はEdge Function(service role)が行う想定(QR解決時等)。
create or replace function refresh_daily_child_status(p_child_id uuid, p_business_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_absent boolean;
  v_last_event child_attendance_events%rowtype;
  v_status text;
  v_day_start timestamptz;
  v_day_end timestamptz;
begin
  v_day_start := p_business_date::timestamp at time zone 'Asia/Tokyo';
  v_day_end := (p_business_date + 1)::timestamp at time zone 'Asia/Tokyo';

  select coalesce(is_absent, false) into v_is_absent
  from child_daily_attendance
  where child_id = p_child_id and business_date = p_business_date;

  select * into v_last_event
  from child_attendance_events
  where child_id = p_child_id
    and occurred_at >= v_day_start and occurred_at < v_day_end
    and event_type in ('drop_off', 'pick_up', 'proxy_drop_off', 'proxy_pick_up')
  order by occurred_at desc
  limit 1;

  if coalesce(v_is_absent, false) then
    v_status := 'absent';
  elsif v_last_event.event_type in ('pick_up', 'proxy_pick_up') then
    v_status := 'picked_up';
  elsif v_last_event.event_type in ('drop_off', 'proxy_drop_off') then
    v_status := 'present';
  else
    v_status := 'not_arrived';
  end if;

  insert into daily_child_status (child_id, business_date, status, last_event_id, updated_at)
  values (p_child_id, p_business_date, v_status, v_last_event.id, now())
  on conflict (child_id, business_date)
  do update set status = excluded.status, last_event_id = excluded.last_event_id, updated_at = excluded.updated_at;
end;
$$;

-- 家庭連絡帳の保存(下書き中のみ編集可)。変更のたびにfamily_daily_report_revisionsへ記録する。
create or replace function upsert_family_daily_report(
  p_child_id uuid,
  p_business_date date,
  p_temperature numeric,
  p_temperature_measured_at time,
  p_symptoms text,
  p_home_notes text
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
      child_id, business_date, guardian_id, temperature, temperature_measured_at, symptoms, home_notes
    ) values (
      p_child_id, p_business_date, my_guardian_id(), p_temperature, p_temperature_measured_at, p_symptoms, p_home_notes
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
      home_notes = p_home_notes
  where id = v_report.id
  returning to_jsonb(family_daily_reports.*) into v_after;

  insert into family_daily_report_revisions (report_id, revised_by, before_values, after_values)
  values (v_report.id, my_guardian_id(), v_before, v_after);

  return v_report.id;
end;
$$;

create or replace function submit_family_daily_report(p_report_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_report family_daily_reports%rowtype;
begin
  select * into v_report from family_daily_reports where id = p_report_id for update;
  if v_report.id is null then
    raise exception 'report not found';
  end if;
  if not guardian_has_child_access(v_report.child_id) then
    raise exception 'not authorized';
  end if;
  if v_report.status <> 'draft' then
    raise exception 'report is % and cannot be submitted', v_report.status;
  end if;

  update family_daily_reports set status = 'submitted', submitted_at = now() where id = p_report_id;
end;
$$;

-- 保護者申請の承認・差し戻し(申請作成自体はRLS経由の直接INSERTでよい。requestsテーブルと同じ方針)。
create or replace function approve_parent_request(p_request_id uuid, p_decision_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request parent_requests%rowtype;
begin
  select * into v_request from parent_requests where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'request not found';
  end if;
  if not staff_manages_guardian_data(v_request.child_id) then
    raise exception 'not authorized';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'request is % and cannot be approved', v_request.status;
  end if;

  update parent_requests
  set status = 'approved', approved_by = my_employee_id(), approved_at = now(), decision_reason = p_decision_reason
  where id = p_request_id;
end;
$$;

create or replace function reject_parent_request(p_request_id uuid, p_decision_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request parent_requests%rowtype;
begin
  if p_decision_reason is null or length(trim(p_decision_reason)) = 0 then
    raise exception 'reason is required';
  end if;
  select * into v_request from parent_requests where id = p_request_id for update;
  if v_request.id is null then
    raise exception 'request not found';
  end if;
  if not staff_manages_guardian_data(v_request.child_id) then
    raise exception 'not authorized';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'request is % and cannot be rejected', v_request.status;
  end if;

  update parent_requests
  set status = 'rejected', approved_by = my_employee_id(), approved_at = now(), decision_reason = p_decision_reason
  where id = p_request_id;
end;
$$;

-- クラス写真の手動チェック→公開(変更7: 掲載不可園児確認の手動ゲート)。
create or replace function check_class_daily_photo(p_photo_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_id uuid;
  v_office_id uuid;
begin
  select class_id into v_class_id from class_daily_photos where id = p_photo_id;
  if v_class_id is null then
    raise exception 'photo not found';
  end if;
  select office_id into v_office_id from childcare_classes where id = v_class_id;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  update class_daily_photos
  set status = 'checked', checked_by = my_employee_id(), checked_at = now()
  where id = p_photo_id and status = 'draft';
end;
$$;

create or replace function publish_class_daily_photo(p_photo_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_photo class_daily_photos%rowtype;
  v_office_id uuid;
begin
  select * into v_photo from class_daily_photos where id = p_photo_id for update;
  if v_photo.id is null then
    raise exception 'photo not found';
  end if;
  select office_id into v_office_id from childcare_classes where id = v_photo.class_id;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;
  if v_photo.status <> 'checked' then
    raise exception 'photo is % and must be checked before publishing', v_photo.status;
  end if;

  update class_daily_photos set status = 'published', published_at = now() where id = p_photo_id;
end;
$$;
