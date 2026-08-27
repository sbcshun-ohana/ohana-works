-- 381: 一時外出を「出欠状況の外/戻」(child_attendance_events)へ統合(俊指示 2026-08-27)。
--   専用の child_outings(315)アイコン運用を廃止し、出欠編集の「外(out)」に理由を付ける方式へ。
--   療育QR(171)は不変。戻り予定時刻は廃止(理由+外時刻のみ)。閉園時の未クローズ安全通知は
--   child_attendance_events ベース(外あり・その後 戻/退 なし)に付け替えて維持する。

-- (1) 外出イベントに理由を保持する列(therapy/checkup/other)。'out' イベントにのみ付与。
alter table child_attendance_events
  add column if not exists outing_reason text
    check (outing_reason is null or outing_reason in ('therapy', 'checkup', 'other'));

-- (2) set_child_attendance_actuals に p_outing_reason を追加。'out' の代表イベントに理由を保存。
--   ※現行の本番定義は212(感染症ゲート版)。212ベースに拡張し、感染症登園ゲート(AC-11)を保持する。
--   ※p_outing_reason=null は「理由据置」(理由を渡さない既存admin呼び出しで理由を消さない)。
--     coalesce(p_outing_reason, 現在理由) を採用。理由のクリアは外時刻クリア(out削除)で行われる。
--   旧6引数版を落として7引数版へ差し替え(名前付き呼び出しは既定でnull補完)。
drop function if exists set_child_attendance_actuals(uuid, date, time, time, time, time);
create or replace function set_child_attendance_actuals(
  p_child_id uuid,
  p_business_date date,
  p_in     time default null,   -- 入(登園)
  p_out    time default null,   -- 外(外出)
  p_return time default null,   -- 戻(再入室)
  p_depart time default null,   -- 退(降園)
  p_outing_reason text default null  -- 外出理由(therapy/checkup/other)。null=据置。
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_office uuid;
  v_cur_in time; v_cur_out time; v_cur_return time; v_cur_depart time;
  v_cur_reason text;
  v_eff_reason text;
  v_changed boolean := false;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if p_outing_reason is not null and p_outing_reason not in ('therapy', 'checkup', 'other') then
    raise exception 'invalid outing_reason';
  end if;

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

  -- 現在の外出理由(最新の out イベント)。p_outing_reason=null は据置(coalesce)。
  select outing_reason into v_cur_reason
  from child_attendance_events
  where child_id = p_child_id and event_type = 'out'
    and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date
  order by occurred_at desc limit 1;
  v_eff_reason := coalesce(p_outing_reason, v_cur_reason);

  -- 212: 感染症ゲート(「入」を新規に立てる場合のみ=AC-11。削除・降園・外出/戻りは対象外)
  if p_in is distinct from v_cur_in and p_in is not null then
    perform assert_infection_gate_for_checkin(p_child_id);
  end if;

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

  -- 外(外出): 時刻 or 実効理由 が変わったら out を置換(理由も保存)。
  if (p_out is distinct from v_cur_out) or (v_eff_reason is distinct from v_cur_reason) then
    delete from child_attendance_events
      where child_id = p_child_id and event_type = 'out'
        and (occurred_at at time zone 'Asia/Tokyo')::date = p_business_date;
    if p_out is not null then
      insert into child_attendance_events (child_id, event_type, occurred_at, recorded_by_employee_id, outing_reason)
      values (p_child_id, 'out', (p_business_date::timestamp + p_out) at time zone 'Asia/Tokyo', my_employee_id(), v_eff_reason);
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
grant execute on function set_child_attendance_actuals(uuid, date, time, time, time, time, text) to authenticated;

-- (3) アラートバーの「一時外出 未クローズ」を child_attendance_events ベースへ付け替え。
--   前日以前(直近7日)で「外」あり・その後 戻/退 なし=閉園後も外出のまま。他アラートは316のまま維持。
create or replace function fetch_childcare_alerts_for_office(p_office_id uuid)
returns table (alert_type text, label text, cnt bigint, href text, level text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;

  return query
    select 'allergy_incident'::text, 'アレルギー発症報告(未対応)'::text, count(*),
           '/childcare/allergy-incidents'::text, 'action'::text
    from allergy_incident_reports
    where office_id = p_office_id and status = 'reported'
    having count(*) > 0;

  if is_incident_reports_enabled_for_office(p_office_id) then
    return query
      select 'incident_report'::text, 'ヒヤリハット・事故報告(未対応)'::text, count(*),
             '/childcare/incidents'::text, 'action'::text
      from incident_reports
      where office_id = p_office_id and status <> 'draft' and coalesce(closure_status, 'open') <> 'closed'
      having count(*) > 0;
  end if;

  return query
    select 'parent_request'::text, '保護者からの連絡(未承認)'::text, count(*),
           '/childcare/parent-requests'::text, 'action'::text
    from parent_requests pr join children c on c.id = pr.child_id
    where c.office_id = p_office_id and pr.status = 'pending'
    having count(*) > 0;

  if is_infection_control_enabled_for_office(p_office_id) then
    return query
      select 'infection_document'::text, '感染症の書類待ち'::text, count(*),
             '/childcare/daily-board'::text, 'action'::text
      from infection_cases
      where office_id = p_office_id and status <> 'closed' and document_state = 'required_not_submitted'
      having count(*) > 0;
  end if;

  return query
    select 'meal_consent_recent'::text, '除去食の保護者同意がありました'::text, count(*),
           '/childcare/meal-conferences'::text, 'info'::text
    from meal_conference_consents mcc
    join meal_conferences mc on mc.id = mcc.conference_id
    where mc.office_id = p_office_id and mcc.acknowledged_at is null
    having count(*) > 0;

  -- 指導計画 未完了(主任以上のみ)。
  if manages_childcare(p_office_id) and is_guidance_plans_enabled_for_office(p_office_id) then
    return query
      select 'guidance_unsubmitted'::text, '指導計画 未提出'::text, count(*),
             '/childcare/guidance-plans'::text, 'action'::text
      from fetch_guidance_plan_tasks_for_office(p_office_id) t where t.level = 'action'
      having count(*) > 0;
    return query
      select 'guidance_pending'::text, '指導計画 承認待ち'::text, count(*),
             '/childcare/guidance-plans'::text, 'info'::text
      from fetch_guidance_plan_tasks_for_office(p_office_id) t where t.level = 'info'
      having count(*) > 0;
  end if;

  -- 重要事項説明書 未同意(主任以上・公開中文書がある場合)。世帯数でカウント。
  if manages_childcare(p_office_id) then
    return query
      with active as (
        select id from important_matters_documents
        where office_id = p_office_id and is_published order by fiscal_year desc, version desc limit 1
      )
      select 'important_matters_unconsented'::text, '重要事項説明書 未同意'::text, count(*),
             '/childcare/important-matters'::text, 'info'::text
      from (
        select distinct ch.household_id
        from children ch, active a
        where ch.office_id = p_office_id and ch.enrollment_status = '在籍中' and ch.household_id is not null
          and not exists (select 1 from important_matters_consents c where c.document_id = a.id and c.household_id = ch.household_id)
      ) x
      having count(*) > 0;
  end if;

  -- 一時外出 未クローズ(主任以上・前日以前で「外」あり・その後 戻/退 なし)。315→出欠状況ベースへ変更(381)。
  if manages_childcare(p_office_id) then
    return query
      select 'outing_not_closed'::text, '一時外出 未クローズ(要確認)'::text, count(*),
             '/childcare/daily-board'::text, 'action'::text
      from (
        select e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date as bd,
               max(e.occurred_at) filter (where e.event_type = 'out')    as out_at,
               max(e.occurred_at) filter (where e.event_type = 'return') as ret_at,
               max(e.occurred_at) filter (where e.event_type in ('pick_up','proxy_pick_up')) as pick_at
        from child_attendance_events e
        join children c on c.id = e.child_id
        where c.office_id = p_office_id
          and e.occurred_at >= now() - interval '8 days'   -- sargable粗フィルタ(索引利用)
          and (e.occurred_at at time zone 'Asia/Tokyo')::date < (now() at time zone 'Asia/Tokyo')::date
          and (e.occurred_at at time zone 'Asia/Tokyo')::date >= (now() at time zone 'Asia/Tokyo')::date - 7
        group by e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date
      ) x
      where x.out_at is not null
        and (x.ret_at is null or x.ret_at < x.out_at)
        and (x.pick_at is null or x.pick_at < x.out_at)
      having count(*) > 0;
  end if;
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;

-- (4) 翌朝の主任通知も child_attendance_events ベースへ付け替え(cron名・notification_type は据置=再スケジュール不要)。
create or replace function cron_detect_stale_outings()
returns void language plpgsql security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select distinct 'outing_not_closed', '一時外出の未クローズ',
    o.name || ' で前日までの外出が未クローズです(' || g.cnt || '件)。戻り/降園の記録をご確認ください。',
    array['push', 'in_app'], mgr.employee_id,
    jsonb_build_object('office_id', g.office_id::text, 'date', v_today::text), 'pending'
  from (
    select c.office_id, count(*) as cnt
    from (
      select e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date as bd,
             max(e.occurred_at) filter (where e.event_type = 'out')    as out_at,
             max(e.occurred_at) filter (where e.event_type = 'return') as ret_at,
             max(e.occurred_at) filter (where e.event_type in ('pick_up','proxy_pick_up')) as pick_at
      from child_attendance_events e
      where e.occurred_at >= now() - interval '8 days'   -- sargable粗フィルタ(索引利用)
        and (e.occurred_at at time zone 'Asia/Tokyo')::date < v_today
        and (e.occurred_at at time zone 'Asia/Tokyo')::date >= v_today - 7
      group by e.child_id, (e.occurred_at at time zone 'Asia/Tokyo')::date
    ) x
    join children c on c.id = x.child_id
    where x.out_at is not null
      and (x.ret_at is null or x.ret_at < x.out_at)
      and (x.pick_at is null or x.pick_at < x.out_at)
    group by c.office_id
  ) g
  join offices o on o.id = g.office_id
  cross join lateral (
    select er.employee_id from employee_roles er join roles r on r.id = er.role_id
    where r.code in ('system_admin', 'executive_director')
       or (r.code in ('director', 'chief', 'office_manager') and (er.office_id is null or er.office_id = g.office_id))
    union
    select gr.grantee_employee_id from multi_office_authority_grants gr
    where gr.office_id = g.office_id and gr.revoked_at is null
  ) mgr(employee_id)
  where not exists (
    select 1 from notifications n
    where n.notification_type = 'outing_not_closed'
      and n.target_employee_id = mgr.employee_id
      and n.payload->>'office_id' = g.office_id::text
      and n.payload->>'date' = v_today::text
  );
end $$;
