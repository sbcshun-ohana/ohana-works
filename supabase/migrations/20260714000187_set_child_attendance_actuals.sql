-- 187: 登降園実績(入/外/戻/退)の手動修正RPC
-- 出欠モーダル(K7)の「登降園(実績)」欄。入(drop)/外(out)/戻(return)/退(pick)を職員が手修正。
--
-- 【全置換セマンティクス】本RPCは4実績の全置換。NULL=当該実績の削除(クリア)。
--   呼び出し側(K7モーダル)は現在値をプリフィルした完全な4値を常に渡すこと(部分更新ではない)。
-- 各種別の代表イベントを1件に置換(既存同種別を delete→insert)。ただし渡された値が現在の代表値
--   (入=min(drop系)/退=max(pick系)/外=max(out)/戻=max(return))と同一なら delete+insert をスキップし、
--   元イベント(保護者QRの実 drop_off 等)の出所と id を保全する(監査ログの無駄も防ぐ)。
-- 変更があった時のみ daily_child_status を refresh_daily_child_status(93)で再計算。
--   元の打刻の削除は child_attendance_events の trg_audit(event_logs)に残る。
-- 保護者通知は行わない(内部修正のため。通知が要る新規代理打刻は165 record_staff_manual_attendance)。
--
-- 権限: manages_childcare(主任以上)。2026-07-31確定「デイリーボードの変更=主任以上」・165と同格。
--   線引き: 出欠種別/メモ(185=office access)は現場の日常記録 / 実績打刻の事後改変(187)は主任以上。
-- 順序検証は最小限(退≥入・戻≥外 のみ)。入なしで外のみ 等の部分/異常組合せは弾かない
--   (現場の部分入力・訂正途中を許容する意図。整合はUI側で補助)。
-- 療育外出/戻りは別系統(therapy_outing_events・171/173)。本RPCの child_attendance_events への
--   delete(event_type='out'/'return')は therapy_outing_events に一切触れない。

create or replace function set_child_attendance_actuals(
  p_child_id uuid,
  p_business_date date,
  p_in     time default null,   -- 入(登園)
  p_out    time default null,   -- 外(外出)
  p_return time default null,   -- 戻(再入室)
  p_depart time default null    -- 退(降園)
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_cur_in time; v_cur_out time; v_cur_return time; v_cur_depart time;
  v_changed boolean := false;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;

  -- 順序検証は最小限(退≥入・戻≥外)。それ以外の組合せは意図的に弾かない。
  if p_in is not null and p_depart is not null and p_depart < p_in then
    raise exception 'depart before in';
  end if;
  if p_out is not null and p_return is not null and p_return < p_out then
    raise exception 'return before out';
  end if;

  -- 現在の代表値(JST時刻)を取得(同一値スキップ判定用)
  select
    (min(occurred_at) filter (where event_type in ('drop_off','proxy_drop_off')) at time zone 'Asia/Tokyo')::time,
    (max(occurred_at) filter (where event_type in ('pick_up','proxy_pick_up'))   at time zone 'Asia/Tokyo')::time,
    (max(occurred_at) filter (where event_type = 'out')    at time zone 'Asia/Tokyo')::time,
    (max(occurred_at) filter (where event_type = 'return') at time zone 'Asia/Tokyo')::time
  into v_cur_in, v_cur_depart, v_cur_out, v_cur_return
  from child_attendance_events
  where child_id = p_child_id and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date;

  -- drop/pick を触る場合のみ daily_child_status.last_event_id の FK(NO ACTION)を回避
  if (p_in is distinct from v_cur_in) or (p_depart is distinct from v_cur_depart) then
    update daily_child_status set last_event_id = null
      where child_id = p_child_id and business_date = p_business_date;
  end if;

  -- 入(登園): 変更時のみ drop_off/proxy_drop_off を置換
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

  -- 退(降園): 変更時のみ pick_up/proxy_pick_up を置換
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

  -- 外(外出): 変更時のみ out を置換
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

  -- 戻(再入室): 変更時のみ return を置換
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

-- 新規関数のため実行権限を明示付与(認証セッションのみ。関数内で主任以上を判定)。
grant execute on function set_child_attendance_actuals(uuid, date, time, time, time, time) to authenticated;
