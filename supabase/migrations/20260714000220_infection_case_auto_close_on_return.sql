-- 220: 感染症案件の登園時自動終了を拡張(俊指示 2026-08-17)。
-- 209では「受診結果待ち」のみ登園で自動消滅していた。本migrationで
-- 「感染症確定+必要書類が充足済み(提出済み or 書類不要)」の案件も、登園(present/picked_up)が
-- 済んだ時点で closed/returned に自動終了する。保護者アプリのカード・ボードのバッジが自動で消える。
-- 書類未提出(required_not_submitted)の案件は対象外(手続き中のため残す)。
-- ※適用前照合: pg_get_functiondef('refresh_daily_child_status(uuid,date)'::regprocedure) が209版と一致すること。
-- 冪等: create or replace のみ。

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

    -- 220: 書類充足済み(提出済み or 書類不要)の確定案件は、登園完了で自動終了(復帰)。
    update infection_cases
    set status = 'closed', closed_reason = 'returned',
        close_note = '必要書類の提出後に登園したため自動終了(復帰)', closed_at = now()
    where child_id = p_child_id
      and status = 'infection_confirmed'
      and document_state in ('not_required', 'submitted_electronically', 'received_on_paper');
  end if;
end;
$$;
