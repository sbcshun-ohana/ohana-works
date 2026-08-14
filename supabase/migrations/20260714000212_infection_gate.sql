-- 212: 感染症 Phase 5 = 登園ゲート(設計指示書 2026-08-13 §3.8/AC-11/13/14/17/18)
--      Phase 4=211適用済みが前提。俊確定(2026-08-14): admin_override(災害用例外)も感染症ゲートは突破不可。
--
-- 概要:
--  (1) 導出関数(状態の二重管理をしない=§5):
--      - fetch_infection_gate_status: 園児の未充足案件一覧+gate有効可否(キオスク/クライアント表示用。
--        AC-18: gate OFF施設では blocked=false のまま警告表示に使う)
--      - assert_infection_gate_for_checkin: gate ON かつ 未充足案件あり なら例外
--        (確定済み(infection_confirmed)+書類未提出のみブロック。受診結果待ちはブロックしない=AC-13。
--         複数案件はすべて充足するまでブロック=AC-14。案件取消(cancel_infection_case)で解除=AC-17)
--  (2) 職員経路への差し込み(3関数の再定義):
--      - record_staff_manual_attendance(165): 代理「登園」時にassert(降園は対象外)
--      - set_child_attendance_actuals(187): 出欠編集で「入」を新規に立てる時のみassert
--      - admin_override_attendance_check_in(100): 突破不可(俊確定③)=assertを追加
--      ※キオスクQR(resolve-guardian-qr)はEdge Function側で判定を追加(別途デプロイ)。
--  (3) 適用前照合: pg_get_functiondef で 165/187/100 の3関数が既存定義どおりか確認すること。
--
-- 冪等: 全て create or replace。

-- (1-1) ゲート状態の取得(キオスク=service_role/職員/保護者本人)
create or replace function fetch_infection_gate_status(p_child_id uuid)
returns table (
  gate_enabled boolean,
  blocked boolean,
  case_id uuid,
  disease_name text,
  required_document text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_office uuid;
  v_gate boolean;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then
    raise exception 'child not found';
  end if;
  if not (auth.role() = 'service_role'
          or has_childcare_office_access(v_office)
          or guardian_has_child_access(p_child_id)) then
    raise exception 'not authorized';
  end if;

  v_gate := is_infection_gate_enabled_for_office(v_office);

  return query
  select
    v_gate,
    v_gate,  -- gate ON のときのみ「ブロック」。OFF なら行=警告表示のみ(AC-18)
    ic.id,
    m.name,
    ic.required_document
  from infection_cases ic
  left join infectious_disease_masters m on m.id = ic.disease_master_id
  where ic.child_id = p_child_id
    and ic.status = 'infection_confirmed'
    and ic.document_state = 'required_not_submitted';
end;
$$;

grant execute on function fetch_infection_gate_status(uuid) to anon, authenticated, service_role;

-- (1-2) 登園時のゲート判定(gate ON かつ 未充足あり→例外)。職員経路3関数から呼ぶ。
create or replace function assert_infection_gate_for_checkin(p_child_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_office uuid;
  v_msg text;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then
    return;
  end if;
  if not is_infection_gate_enabled_for_office(v_office) then
    return;  -- control のみON=警告表示のみでブロックしない(AC-18)
  end if;

  select string_agg(
           coalesce(m.name, '感染症') || 'の' ||
           case ic.required_document
             when 'opinion_letter' then '登園許可書'
             when 'return_form' then '登園届'
             else '書類' end,
           '、')
    into v_msg
  from infection_cases ic
  left join infectious_disease_masters m on m.id = ic.disease_master_id
  where ic.child_id = p_child_id
    and ic.status = 'infection_confirmed'
    and ic.document_state = 'required_not_submitted';

  if v_msg is not null then
    raise exception '感染症の必要書類が未提出のため登園できません: %(提出または紙受領の記録、もしくは主任以上の案件取消で解除できます)', v_msg;
  end if;
end;
$$;

grant execute on function assert_infection_gate_for_checkin(uuid) to anon, authenticated, service_role;

-- (2-1) 代理登降園(165ベース+登園時assert)
create or replace function record_staff_manual_attendance(
  p_child_id uuid,
  p_event_type text,
  p_occurred_at timestamptz,
  p_notify_guardian boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_display_name text;
  v_honorific text;
  v_business_date date := (p_occurred_at at time zone 'Asia/Tokyo')::date;
  v_event_type text;
  v_action_label text;
  v_event_id uuid;
begin
  if p_event_type not in ('drop_off', 'pick_up') then
    raise exception 'invalid event_type';
  end if;

  select office_id, display_name, honorific_suffix_resolved
    into v_office_id, v_display_name, v_honorific
  from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  -- 212: 感染症ゲート(登園のみ。gate ON+書類未充足なら例外=AC-11)
  if p_event_type = 'drop_off' then
    perform assert_infection_gate_for_checkin(p_child_id);
  end if;

  v_event_type := case when p_event_type = 'drop_off' then 'proxy_drop_off' else 'proxy_pick_up' end;
  v_action_label := case when p_event_type = 'drop_off' then '登園' else '降園' end;

  insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_employee_id)
  values (p_child_id, v_event_type, p_occurred_at, my_employee_id())
  returning id into v_event_id;

  perform refresh_daily_child_status(p_child_id, v_business_date);

  if p_notify_guardian then
    insert into notifications (notification_type, title, body, channels, target_guardian_id, payload, status)
    select
      'childcare_attendance',
      v_display_name || coalesce(v_honorific, '') || 'が' || v_action_label || 'しました',
      to_char(p_occurred_at at time zone 'Asia/Tokyo', 'HH24:MI') || ' に' || v_action_label || 'しました',
      array['push'],
      gcl.guardian_id,
      jsonb_build_object('child_id', p_child_id::text, 'event_type', v_event_type),
      'pending'
    from guardian_child_links gcl
    where gcl.child_id = p_child_id
      and not exists (
        select 1 from guardian_notification_settings s
        where s.guardian_id = gcl.guardian_id
          and s.category = 'childcare_attendance' and s.enabled = false
      );
  end if;

  return v_event_id;
end;
$$;

-- (2-2) 出欠編集の実績保存(187ベース+「入」を新規に立てる時のみassert)
create or replace function set_child_attendance_actuals(
  p_child_id uuid,
  p_business_date date,
  p_in     time default null,
  p_out    time default null,
  p_return time default null,
  p_depart time default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_cur_in time; v_cur_out time; v_cur_return time; v_cur_depart time;
  v_changed boolean := false;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  if p_in is not null and p_depart is not null and p_depart < p_in then
    raise exception 'depart before in';
  end if;
  if p_out is not null and p_return is not null and p_return < p_out then
    raise exception 'return before out';
  end if;

  select
    (min(occurred_at) filter (where event_type in ('drop_off','proxy_drop_off')) at time zone 'Asia/Tokyo')::time,
    (max(occurred_at) filter (where event_type in ('pick_up','proxy_pick_up'))   at time zone 'Asia/Tokyo')::time,
    (max(occurred_at) filter (where event_type = 'out')    at time zone 'Asia/Tokyo')::time,
    (max(occurred_at) filter (where event_type = 'return') at time zone 'Asia/Tokyo')::time
  into v_cur_in, v_cur_depart, v_cur_out, v_cur_return
  from child_attendance_events
  where child_id = p_child_id and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date;

  -- 212: 感染症ゲート(「入」を新規に立てる場合のみ=AC-11。削除・降園・外出/戻りは対象外)
  if p_in is distinct from v_cur_in and p_in is not null then
    perform assert_infection_gate_for_checkin(p_child_id);
  end if;

  if (p_in is distinct from v_cur_in) or (p_depart is distinct from v_cur_depart) then
    update daily_child_status set last_event_id = null
      where child_id = p_child_id and business_date = p_business_date;
  end if;

  if p_in is distinct from v_cur_in then
    delete from child_attendance_events
      where child_id = p_child_id and event_type in ('drop_off','proxy_drop_off')
        and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date;
    if p_in is not null then
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_employee_id)
      values (p_child_id, 'proxy_drop_off', (p_business_date::timestamp + p_in) at time zone 'Asia/Tokyo', my_employee_id());
    end if;
    v_changed := true;
  end if;

  if p_depart is distinct from v_cur_depart then
    delete from child_attendance_events
      where child_id = p_child_id and event_type in ('pick_up','proxy_pick_up')
        and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date;
    if p_depart is not null then
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_employee_id)
      values (p_child_id, 'proxy_pick_up', (p_business_date::timestamp + p_depart) at time zone 'Asia/Tokyo', my_employee_id());
    end if;
    v_changed := true;
  end if;

  if p_out is distinct from v_cur_out then
    delete from child_attendance_events
      where child_id = p_child_id and event_type = 'out'
        and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date;
    if p_out is not null then
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_employee_id)
      values (p_child_id, 'out', (p_business_date::timestamp + p_out) at time zone 'Asia/Tokyo', my_employee_id());
    end if;
    v_changed := true;
  end if;

  if p_return is distinct from v_cur_return then
    delete from child_attendance_events
      where child_id = p_child_id and event_type = 'return'
        and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date;
    if p_return is not null then
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_employee_id)
      values (p_child_id, 'return', (p_business_date::timestamp + p_return) at time zone 'Asia/Tokyo', my_employee_id());
    end if;
    v_changed := true;
  end if;

  if v_changed then
    perform refresh_daily_child_status(p_child_id, p_business_date);
  end if;
end; $$;

-- (2-3) 管理者例外オーバーライド(100ベース+感染症ゲートは突破不可=俊確定③)
create or replace function admin_override_attendance_check_in(
  p_child_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason is required';
  end if;
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  -- 212: 感染症ゲートはオーバーライドでも突破不可(俊確定 2026-08-14)。
  -- 例外は主任以上の案件取消(cancel_infection_case)のみ(§3.8)。
  perform assert_infection_gate_for_checkin(p_child_id);

  insert into child_attendance_events (
    child_id, event_type, occurred_at, recorded_by_employee_id, admin_override_by, admin_override_reason
  ) values (
    p_child_id, 'drop_off', now(), my_employee_id(), my_employee_id(), p_reason
  );

  perform refresh_daily_child_status(p_child_id, (now() at time zone 'Asia/Tokyo')::date);
end;
$$;
