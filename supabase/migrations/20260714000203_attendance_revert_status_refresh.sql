-- 203: 欠席を出席へ戻した際の表示不整合の修正(俊承認 2026-08-14)
--
-- 症状: 期間欠席(197)承認後に特定日を出席へ戻しても、行の状態表示が「欠席」のまま残る。
--   ・欠席表示は daily_child_status.status(承認時に'absent'で書込) と 出欠種別(病欠/都合欠) から決まるが、
--     戻す操作のRPCが refresh_daily_child_status(93) を呼んでいなかった。
--   ・Kidsの主任以上だけ実績RPC(187)が偶然refreshを呼ぶため正しく見えていた。
--   ・簡易トグル(61)は attendance_kind(病欠/都合欠) も残すため、種別由来の欠席表示にも固定されていた。
--
-- 修正(関数2本の差し替えのみ・テーブル/クライアント変更なし):
--  (1) set_child_attendance_status(185) の末尾に refresh_daily_child_status を追加。
--  (2) set_child_daily_attendance(61・簡易トグル) に refresh を追加し、
--      出席に戻す(p_is_absent=false)時は attendance_kind='none' にクリア
--      (病欠/都合欠の残骸で欠席表示に固定されるのを防ぐ)。
--      欠席にする(p_is_absent=true)時は既存の attendance_kind を変更しない(種別なし簡易欠席の従来仕様)。
--
-- ※適用前に pg_get_functiondef で両関数が 61/185 の定義どおりか照合すること。
-- 冪等: いずれも create or replace。

-- (1) 出欠編集モーダルの保存(185ベース+refresh追加)
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

  -- 203: 状態表示(daily_child_status)を即時再計算する。欠席へ/欠席から戻す いずれの保存でも
  -- ボードの状態チップ・欠席児童一覧が is_absent と一致するようにする。
  perform refresh_daily_child_status(p_child_id, p_business_date);
end; $$;

-- (2) 簡易トグル(61ベース+kindクリア+refresh追加)
create or replace function set_child_daily_attendance(
  p_child_id uuid,
  p_business_date date,
  p_is_absent boolean,
  p_absence_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  -- 203: 出席に戻す時は attendance_kind も 'none' にクリアする
  -- (期間欠席承認(197)が書いた病欠/都合欠が残ると、種別由来の欠席表示に固定されるため)。
  -- 欠席にする時は既存の種別を変更しない(種別なしの簡易欠席=従来仕様)。
  insert into child_daily_attendance (child_id, business_date, is_absent, absence_reason, attendance_kind, changed_by, changed_at)
  values (
    p_child_id, p_business_date, p_is_absent,
    case when p_is_absent then p_absence_reason else null end,
    case when p_is_absent then null else 'none' end,
    my_employee_id(), now()
  )
  on conflict (child_id, business_date)
  do update set
    is_absent = excluded.is_absent,
    absence_reason = excluded.absence_reason,
    attendance_kind = case when excluded.is_absent
                           then child_daily_attendance.attendance_kind
                           else 'none' end,
    changed_by = excluded.changed_by,
    changed_at = excluded.changed_at;

  -- 203: 状態表示(daily_child_status)を即時再計算する。
  perform refresh_daily_child_status(p_child_id, p_business_date);
end;
$$;
