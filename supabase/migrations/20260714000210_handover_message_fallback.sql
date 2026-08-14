-- 210: 引き継ぎカードの既定文面フォールバック(209のE2Eで発覚した実バグ修正)。
-- childcare_office_settings に行が無い施設では guardian_message が NULL になっていた。
-- テンプレート(施設別)→無ければ共通既定文、の三段coalesceに修正。209の send_handover_card 全文差し替え。
-- 冪等: create or replace のみ。

create or replace function send_handover_card(
  p_case_id uuid,
  p_hives text,
  p_rash text,
  p_rash_locations text[] default null,
  p_rash_location_other text default null,
  p_free_note text default null,
  p_guardian_message text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_case infection_cases%rowtype;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
  v_snapshot jsonb;
  v_version int;
  v_card_id uuid;
  v_child_name text;
begin
  select * into v_case from infection_cases where id = p_case_id for update;
  if v_case.id is null then
    raise exception 'case not found';
  end if;
  if not has_childcare_office_access(v_case.office_id) then
    raise exception 'not authorized';
  end if;
  if v_case.status = 'closed' then
    raise exception 'case is closed';
  end if;

  v_snapshot := jsonb_build_object(
    'business_date', to_char(v_today, 'YYYY-MM-DD'),
    'temperatures', coalesce((
      select jsonb_agg(jsonb_build_object(
               'time', to_char(t.measured_at, 'HH24:MI'),
               'temperature', t.temperature,
               'recorded_by', e.name) order by t.measured_at)
      from child_temperature_records t
      left join employees e on e.id = t.recorded_by
      where t.child_id = v_case.child_id and t.business_date = v_today), '[]'::jsonb),
    'toileting', coalesce((
      select cdc.toileting_records from child_daily_contacts cdc
      where cdc.child_id = v_case.child_id and cdc.business_date = v_today), '[]'::jsonb),
    'family_report', (
      select jsonb_build_object(
        'temperature', fdr.temperature,
        'temperature_measured_at', to_char(fdr.temperature_measured_at, 'HH24:MI'),
        'night_bowel_count', fdr.night_bowel_count,
        'night_bowel_condition', fdr.night_bowel_condition,
        'morning_bowel_count', fdr.morning_bowel_count,
        'morning_bowel_condition', fdr.morning_bowel_condition)
      from family_daily_reports fdr
      where fdr.child_id = v_case.child_id and fdr.business_date = v_today),
    'reference_counts', coalesce((
      select jsonb_agg(jsonb_build_object('disease', x.name, 'count', x.cnt) order by x.cnt desc)
      from (
        select m.name, count(*) as cnt
        from infection_cases ic
        join infectious_disease_masters m on m.id = ic.disease_master_id
        where ic.office_id = v_case.office_id
          and ic.disease_master_id is not null
          and ic.confirmed_at >= now() - interval '7 days'
        group by m.name
      ) x), '[]'::jsonb)
  );

  select coalesce(max(version), 0) + 1 into v_version from infection_handover_cards where case_id = p_case_id;

  insert into infection_handover_cards (
    case_id, child_id, office_id, version, snapshot,
    hives, rash, rash_locations, rash_location_other, free_note, guardian_message,
    sent_by
  ) values (
    p_case_id, v_case.child_id, v_case.office_id, v_version, v_snapshot,
    p_hives, p_rash, p_rash_locations, p_rash_location_other, p_free_note,
    -- 210: 施設テンプレ→共通既定文の三段フォールバック(設定行が無い施設でも文面が空にならない)
    coalesce(
      p_guardian_message,
      (select handover_guardian_message_template from childcare_office_settings where office_id = v_case.office_id),
      '本日、園での様子に気になる点がありましたのでお知らせします。集団生活のため、必要に応じて医療機関の受診にご協力ください。受診されましたら、アプリから受診結果のご入力をお願いします。'),
    my_employee_id()
  ) returning id into v_card_id;

  select display_name || coalesce(honorific_suffix_resolved, '') into v_child_name
  from children where id = v_case.child_id;

  insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
  select
    'infection_handover_card',
    '園からの引き継ぎカードが届きました',
    v_child_name || 'の本日の様子をお知らせしています。アプリでご確認ください',
    array['push'],
    gcl.guardian_id,
    jsonb_build_object('child_id', v_case.child_id::text, 'case_id', p_case_id::text, 'card_id', v_card_id::text),
    'pending'
  from guardian_child_links gcl
  where gcl.child_id = v_case.child_id;

  return v_card_id;
end;
$$;
