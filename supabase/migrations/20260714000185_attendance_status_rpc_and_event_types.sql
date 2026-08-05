-- 185: 出欠状況の保存RPC + 登降園イベント種別に外出/戻りを追加
-- デイリーボード刷新 Phase B の第2弾。184で追加した列(attendance_kind/scheduled_*/attendance_note)へ
-- 出欠モーダルから保存する RPC を新設。event_type に out(外出)/return(戻り) を許可(中抜け表現用)。
-- 権限: 出欠状況の記録は日次運用のため担当施設の職員(has_childcare_office_access)。
--       既存の簡易トグル set_child_daily_attendance(61) と同格。

-- (1) 登降園イベント種別の拡張: 外出/戻りを許可(既存値はそのまま。既存行は違反しない)
alter table child_attendance_events
  drop constraint child_attendance_events_event_type_check,
  add constraint child_attendance_events_event_type_check
    check (event_type in ('drop_off','pick_up','rejected','proxy_drop_off','proxy_pick_up','out','return'));

comment on constraint child_attendance_events_event_type_check on child_attendance_events is
  'drop_off/pick_up/rejected/proxy_*(既存) + out(外出)/return(戻り)。out/return は日中の中抜け(退室〜再入室)を表す';

-- (2) 出欠状況の保存(出欠モーダル)。種別/当日予定override/メモをまとめて upsert し、is_absent を種別から同期。
--     is_absent と同期するのは病欠・都合欠のみ(遅刻/早退/none は出席側)。既存の簡易トグル(set_child_daily_attendance)は不変。
create or replace function set_child_attendance_status(
  p_child_id uuid,
  p_business_date date,
  p_attendance_kind text,                 -- none/late/early_leave/sick_absence/personal_absence (NULL可=未設定)
  p_scheduled_start time default null,    -- 当日の登園予定(週次標準の上書き)
  p_scheduled_end   time default null,    -- 当日の降園予定
  p_scheduled_slot  text default null,    -- 予定枠
  p_attendance_note text default null     -- 出欠メモ(absence_reason=欠席理由 とは別)
) returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_is_absent boolean;
begin
  if p_attendance_kind is not null
     and p_attendance_kind not in ('none','late','early_leave','sick_absence','personal_absence') then
    raise exception 'invalid attendance_kind';
  end if;
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  -- 権限の非対称(意図): 週次標準(184)=主任以上=契約に基づく設定 / 日別の出欠・予定override(185)=現場の日常記録=担当施設の職員。

  -- 欠席は病欠・都合欠のみ(サマリー163の欠席数=病欠+都合欠 と整合)。遅刻/早退/none/NULL は出席側。
  -- coalesce で NULL を false に畳む(kind=NULL 時に is_absent=NULL という第3状態を書かないため)。
  v_is_absent := coalesce(p_attendance_kind in ('sick_absence','personal_absence'), false);

  insert into child_daily_attendance (
    child_id, business_date, is_absent, attendance_kind,
    scheduled_start_at, scheduled_end_at, scheduled_slot, attendance_note,
    changed_by, changed_at
  ) values (
    p_child_id, p_business_date, v_is_absent, p_attendance_kind,
    p_scheduled_start, p_scheduled_end, p_scheduled_slot, p_attendance_note,
    my_employee_id(), now()
  )
  on conflict (child_id, business_date) do update set
    is_absent          = excluded.is_absent,
    attendance_kind    = excluded.attendance_kind,
    scheduled_start_at = excluded.scheduled_start_at,
    scheduled_end_at   = excluded.scheduled_end_at,
    scheduled_slot     = excluded.scheduled_slot,
    attendance_note    = excluded.attendance_note,
    changed_by         = excluded.changed_by,
    changed_at         = excluded.changed_at;
  -- 注: absence_reason(既存の簡易トグル用)はこのRPCでは触らない。監査は child_daily_attendance の trg_audit で記録。
end; $$;
