-- 209: 感染症 Phase 3 = 引き継ぎカード(起点A)+受診結果入力+受診結果待ちの自動消滅
--      (設計指示書 2026-08-13 §3.1/3.2/3.4/3.6/§5、Phase 2=206適用済みが前提)
--
-- 概要:
--  (1) childcare_office_settings に保護者向け既定文面テンプレート列を追加(施設別管理・コード固定禁止)。
--  (2) infection_handover_cards: カード本体。v1は「送信時に行を作成」(下書きは端末内)。
--      再送信=version+1 の新行(保護者には最新版を表示・旧版は履歴保持=§3.1)。
--      snapshot(jsonb)に送信時点の検温・排便・家庭連絡帳・園内感染症の参考表示を凍結(AC-03)。
--  (3) medical_visit_reports: 受診結果(保護者入力)。
--  (4) RPC:
--      - create_infection_handover_case: 起点Aの案件作成(受診結果待ち)。進行中があれば再利用
--      - send_handover_card: スナップショット固定+カード送信+保護者プッシュ(outbox)
--      - submit_medical_visit_report: 保護者の受診結果→案件遷移(感染症確定/該当なし終了/待ち継続)+園側通知
--      - fetch_infection_reference_counts: 園内感染症の参考表示(同一施設・過去7日・1件から。§3.2)
--  (5) refresh_daily_child_status(93) を再定義: 登園(present)時に「受診結果待ち」案件を
--      自動消滅(closed/auto_attended=§3.6)。QR・代理登園・実績修正の全経路が本関数を通るため1箇所で済む。
--      ※適用前に pg_get_functiondef('refresh_daily_child_status(uuid,date)'::regprocedure) を93と照合すること。
--
-- 冪等: 列追加=if not exists、関数=create or replace。テーブル/ポリシー/トリガーは初回適用前提の素create。

-- (1) 保護者向け既定文面(施設別テンプレート)
alter table childcare_office_settings add column if not exists handover_guardian_message_template text;

update childcare_office_settings
set handover_guardian_message_template =
  '本日、園での様子に気になる点がありましたのでお知らせします。集団生活のため、必要に応じて医療機関の受診にご協力ください。受診されましたら、アプリから受診結果のご入力をお願いします。'
where handover_guardian_message_template is null;

comment on column childcare_office_settings.handover_guardian_message_template is
  '引き継ぎカード(209)の保護者向け既定文面。施設別に編集可能(コード固定禁止=設計書§3.1)';

-- (2) 引き継ぎカード
create table infection_handover_cards (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references infection_cases(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  office_id uuid not null references offices(id),
  version int not null default 1,
  status text not null default 'sent' check (status in ('sent')),
  snapshot jsonb,
  hives text check (hives in ('yes', 'no', 'unchecked')),
  rash text check (rash in ('yes', 'no', 'unchecked')),
  rash_locations text[],
  rash_location_other text,
  free_note text,
  guardian_message text,
  sent_at timestamptz not null default now(),
  sent_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (case_id, version)
);

comment on table infection_handover_cards is
  '引き継ぎカード(209・起点A)。送信時に行を作成し、snapshotに検温/排便/家庭連絡帳/参考表示を凍結(AC-03)。'
  ' 訂正は再送信=version+1の新行。保護者には最新版を表示し旧版は履歴保持(§3.1)';

create trigger trg_infection_handover_cards_updated_at before update on infection_handover_cards
  for each row execute function set_updated_at();
create index idx_ihc_case on infection_handover_cards (case_id);
create index idx_ihc_child on infection_handover_cards (child_id);

alter table infection_handover_cards enable row level security;
-- 職員=施設アクセス / 保護者=自分の子のカード(sentのみ=v1は全行sent)。書き込みはRPCのみ。
create policy ihc_select on infection_handover_cards
  for select using (
    staff_has_guardian_data_access(child_id)
    or (guardian_has_child_access(child_id) and status = 'sent')
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'infection_handover_cards'
  );
end $$;

-- (3) 受診結果(保護者入力)
create table medical_visit_reports (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references infection_cases(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  visited boolean not null,
  visited_at timestamptz,
  medical_institution text,
  disease_master_id uuid references infectious_disease_masters(id),
  no_infection boolean not null default false,
  doctor_note text,
  note_to_school text,
  submitted_by_guardian_id uuid references guardians(id),
  created_at timestamptz not null default now()
);

comment on table medical_visit_reports is
  '受診結果(209・保護者入力)。感染症選択→案件確定/該当なし→案件終了/未確定→待ち継続(§3.4)';

create index idx_mvr_case on medical_visit_reports (case_id);

alter table medical_visit_reports enable row level security;
create policy mvr_select on medical_visit_reports
  for select using (guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'medical_visit_reports'
  );
end $$;

-- (4-1) 起点Aの案件作成(受診結果待ち)。進行中の handover 案件があれば再利用。
create or replace function create_infection_handover_case(p_child_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office uuid;
  v_case_id uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office) then
    raise exception 'not authorized';
  end if;
  if not is_infection_control_enabled_for_office(v_office) then
    raise exception 'infection control is not enabled for this office';
  end if;

  select id into v_case_id from infection_cases
    where child_id = p_child_id and origin = 'handover' and status <> 'closed'
    order by created_at desc limit 1;
  if v_case_id is not null then
    return v_case_id;
  end if;

  insert into infection_cases (child_id, office_id, origin, status, required_document, document_state, created_by)
  values (p_child_id, v_office, 'handover', 'awaiting_medical_result', 'none', 'not_required', my_employee_id())
  returning id into v_case_id;
  return v_case_id;
end;
$$;

grant execute on function create_infection_handover_case(uuid) to anon, authenticated, service_role;

-- (4-2) カード送信。スナップショットをサーバー側で固定し、保護者へプッシュ(outbox)。
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

  -- 送信時点のスナップショット(AC-03: 以後ボード側が修正されてもカードは不変)
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
    -- §3.2 園内感染症の参考表示(同一施設・過去7日・1件から。個人特定情報なし。
    -- 期間/最低件数は将来設定化する前提の定数=下のRPCと同じ値を使う)
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
    coalesce(p_guardian_message,
      (select handover_guardian_message_template from childcare_office_settings where office_id = v_case.office_id)),
    my_employee_id()
  ) returning id into v_card_id;

  -- 保護者へプッシュ(outbox→毎分dispatcher)。宛先=対象園児に紐づく全保護者。
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

grant execute on function send_handover_card(uuid, text, text, text[], text, text, text) to anon, authenticated, service_role;

-- (4-3) 受診結果の提出(保護者)。案件を遷移させ、園側(管理者)へ通知。
create or replace function submit_medical_visit_report(
  p_case_id uuid,
  p_visited boolean,
  p_visited_at timestamptz default null,
  p_medical_institution text default null,
  p_disease_master_id uuid default null,
  p_no_infection boolean default false,
  p_doctor_note text default null,
  p_note_to_school text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_case infection_cases%rowtype;
  v_master infectious_disease_masters%rowtype;
  v_required text;
  v_report_id uuid;
  v_child_name text;
begin
  select * into v_case from infection_cases where id = p_case_id for update;
  if v_case.id is null then
    raise exception 'case not found';
  end if;
  if not guardian_has_child_access(v_case.child_id) then
    raise exception 'not authorized';
  end if;
  if v_case.status = 'closed' then
    raise exception 'case is closed';
  end if;

  insert into medical_visit_reports (
    case_id, child_id, visited, visited_at, medical_institution,
    disease_master_id, no_infection, doctor_note, note_to_school, submitted_by_guardian_id
  ) values (
    p_case_id, v_case.child_id, p_visited, p_visited_at, p_medical_institution,
    p_disease_master_id, p_no_infection, p_doctor_note, p_note_to_school, my_guardian_id()
  ) returning id into v_report_id;

  if p_no_infection then
    -- 感染症ではない=書類不要・案件終了(§3.4)
    update infection_cases
    set status = 'closed', closed_reason = 'no_infection', closed_at = now()
    where id = p_case_id;
  elsif p_disease_master_id is not null then
    -- 感染症確定→必要書類判定(206トリガーと同一規則で凍結)
    select * into v_master from infectious_disease_masters where id = p_disease_master_id;
    if v_master.id is null then
      raise exception 'disease master not found';
    end if;
    v_required := case
      when v_master.requires_opinion_letter then 'opinion_letter'
      when v_master.requires_return_form then 'return_form'
      else 'none' end;
    update infection_cases
    set status = 'infection_confirmed',
        disease_master_id = p_disease_master_id,
        required_document = v_required,
        document_state = case when v_required = 'none' then 'not_required' else 'required_not_submitted' end,
        confirmed_at = now()
    where id = p_case_id;
  end if;
  -- 未受診/診断未確定 → awaiting_medical_result のまま(§3.6の自動消滅対象)

  -- 園側(当該施設の管理者層)へ通知(既存の施設管理者宛パターン踏襲)
  select display_name || coalesce(honorific_suffix_resolved, '') into v_child_name
  from children where id = v_case.child_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select distinct
    'infection_medical_report',
    '受診結果が提出されました',
    v_child_name || 'の受診結果が保護者から提出されました',
    array['push', 'in_app'],
    er.employee_id,
    jsonb_build_object('child_id', v_case.child_id::text, 'case_id', p_case_id::text),
    'pending'
  from employee_roles er
  join roles r on r.id = er.role_id
  where r.code in ('director', 'chief', 'office_manager')
    and (er.office_id is null or er.office_id = v_case.office_id);

  return v_report_id;
end;
$$;

grant execute on function submit_medical_visit_report(uuid, boolean, timestamptz, text, uuid, boolean, text, text)
  to anon, authenticated, service_role;

-- (4-4) 園内感染症の参考表示(職員のカード作成画面プレビュー用。数値はsnapshotと同一規則)
create or replace function fetch_infection_reference_counts(p_office_id uuid)
returns table (disease_name text, report_count bigint)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not has_childcare_office_access(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  select m.name, count(*)
  from infection_cases ic
  join infectious_disease_masters m on m.id = ic.disease_master_id
  where ic.office_id = p_office_id
    and ic.disease_master_id is not null
    and ic.confirmed_at >= now() - interval '7 days'  -- 期間7日・1件から(§3.2俊確定・将来設定化)
  group by m.name
  order by count(*) desc;
end;
$$;

grant execute on function fetch_infection_reference_counts(uuid) to anon, authenticated, service_role;

-- (5) 登園時の「受診結果待ち」自動消滅(§3.6)。93の全文ベース+末尾に自動クローズを追加。
--     全登園経路(QR/代理/実績修正)が本関数を通るため、ここ1箇所で担保する。
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

  -- 209(§3.6): 受診結果未入力のまま登園した場合、「受診結果待ち」案件を自動消滅させる
  -- (closed/auto_attended)。カード自体は履歴として残る。職員の操作は不要。
  if v_status in ('present', 'picked_up') then
    update infection_cases
    set status = 'closed', closed_reason = 'auto_attended',
        close_note = '登園により自然終了(受診結果待ちの自動消滅)', closed_at = now()
    where child_id = p_child_id
      and status = 'awaiting_medical_result';
  end if;
end;
$$;
