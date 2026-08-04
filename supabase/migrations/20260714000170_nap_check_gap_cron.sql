-- Phase 3 §3.4: 15:00 JST の午睡チェック漏れ検出→当該施設の管理者(主任以上+統括園長+system_admin
-- +area_manager grant)へ notifications(target_employee_id) 生成。既存 dispatch-pending-notifications
-- がFCM送信。pg_cron は UTC 稼働のため 15:00 JST = '0 6 * * *'。office×date で二重生成ガード(冪等)。
-- 漏れ判定は fetch_nap_missing_slots と同一ロジックをインライン化(cronはJWT無=authz関数を使えないため)。

create or replace function cron_detect_nap_check_gaps()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select distinct
    'nap_check_gap',
    '午睡チェックの記入漏れ',
    o.name || ' で本日の午睡チェックに未記入があります。ご確認ください。',
    array['push'],
    mgr.employee_id,
    jsonb_build_object('office_id', g.office_id::text, 'date', v_today::text),
    'pending'
  from (
    select distinct e.office_id
    from (
      select s.id as session_id, s.office_id, gs as slot_at
      from nap_sessions s
      cross join lateral generate_series(
        date_bin('5 minutes', s.sleep_start_at, timestamptz 'epoch')
          + case when s.sleep_start_at > date_bin('5 minutes', s.sleep_start_at, timestamptz 'epoch')
                 then interval '5 minutes' else interval '0' end,
        least(coalesce(s.wake_up_at, now()), now()),
        interval '5 minutes'
      ) gs
      where s.session_date = v_today and s.sleep_start_at is not null
    ) e
    left join nap_checks nc on nc.session_id = e.session_id and nc.slot_at = e.slot_at
    where nc.id is null
  ) g
  join offices o on o.id = g.office_id
  cross join lateral (
    select er.employee_id
    from employee_roles er join roles r on r.id = er.role_id
    where r.code in ('system_admin', 'executive_director')
       or (r.code in ('director', 'chief', 'office_manager') and (er.office_id is null or er.office_id = g.office_id))
    union
    select gr.grantee_employee_id
    from multi_office_authority_grants gr
    where gr.office_id = g.office_id and gr.revoked_at is null
  ) mgr(employee_id)
  where not exists (
    select 1 from notifications n
    where n.notification_type = 'nap_check_gap'
      and n.target_employee_id = mgr.employee_id
      and n.payload->>'office_id' = g.office_id::text
      and n.payload->>'date' = v_today::text
  );
end;
$$;

select cron.schedule(
  'detect_nap_check_gaps',
  '0 6 * * *',   -- 15:00 JST
  $$select cron_detect_nap_check_gaps();$$
);
