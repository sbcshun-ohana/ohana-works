-- Phase 2 §2.3: 打刻漏れの代理登降園登録(主任以上)。
-- QR打刻と区別するため proxy_drop_off / proxy_pick_up として記録し、実行職員IDを残す
-- (child_attendance_events は監査トリガ対象=登録方法+実行職員が監査に残る。スキーマ変更なし)。
-- 変更と同時に承認扱い(別承認フロー無し)。daily_child_status は通常打刻と同じ
-- refresh_daily_child_status で更新する。
--
-- 保護者通知(2026-08-04 俊確定): 代理登録は職員記録のため、代理側のみ保護者へ通知する
-- (通常QRは保護者自身の操作=未通知の非対称は意図的仕様)。Phase E と同じ
-- notifications(outbox)→dispatch-pending-notifications(pg_cron毎分)→FCM 経路を再利用し、
-- opt-out(guardian_notification_settings)を生成時に尊重する。
-- 既存お知らせ('guardian_notice')と混ざらないよう type/category は 'childcare_attendance' を用いる。
-- 通知は最小構成(タイトル「○○ちゃんが登園/降園しました」+ body に時刻)。tap遷移結線は今回対象外。

create or replace function record_staff_manual_attendance(
  p_child_id uuid,
  p_event_type text,            -- 'drop_off' | 'pick_up'(意図)
  p_occurred_at timestamptz,    -- 職員が手入力した実時刻
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
  v_business_date date := (p_occurred_at at time zone 'Asia/Tokyo')::date;  -- occurred_atから導出しズレ防止
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
  if not manages_childcare(v_office_id) then   -- 主任以上のみ・変更=承認扱い
    raise exception 'not authorized';
  end if;

  v_event_type := case when p_event_type = 'drop_off' then 'proxy_drop_off' else 'proxy_pick_up' end;
  v_action_label := case when p_event_type = 'drop_off' then '登園' else '降園' end;

  insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_employee_id)
  values (p_child_id, v_event_type, p_occurred_at, my_employee_id())
  returning id into v_event_id;

  perform refresh_daily_child_status(p_child_id, v_business_date);

  -- 保護者通知(代理側のみ)。園児に紐づく保護者ごとに1プッシュ。
  -- category 'childcare_attendance' を明示OFFにした保護者にはプッシュ行を作らない(既定=行なし=ON)。
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
