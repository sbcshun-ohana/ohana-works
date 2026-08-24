-- 316: 登降園 Phase C ガード④。閉園後も「外出中のまま」(前日以前で return なし・降園変換なし)の一時外出を
--   (1) アラートバーに「一時外出 未クローズ(要確認)」として主任以上へ表示、
--   (2) 翌朝(8:00 JST)cronで主任以上へ push+in_app 通知(office×run-date で1日1回・冪等)。
-- child_outings(315)に依存。文言/対象(manages_childcare)は既存アラートと整合。

-- (1) アラートバー再定義(既存アラートは維持し、一時外出 未クローズ を末尾に追加)。
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

  -- 一時外出 未クローズ(主任以上・前日以前で外出中のまま=閉園後も戻り/降園が記録されていない)。
  if manages_childcare(p_office_id) then
    return query
      select 'outing_not_closed'::text, '一時外出 未クローズ(要確認)'::text, count(*),
             '/childcare/daily-board'::text, 'action'::text
      from child_outings co
      where co.office_id = p_office_id and co.return_at is null and not co.converted_to_departure
        and co.business_date < (now() at time zone 'Asia/Tokyo')::date
      having count(*) > 0;
  end if;
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;

-- (2) 翌朝の主任以上への通知(前日以前で外出中のまま)。office×run-date で1日1回・冪等。
--   通知対象(主任以上)の抽出は cron_detect_nap_check_gaps(181)と同一ロジック。
create or replace function cron_detect_stale_outings()
returns void language plpgsql security definer set search_path = public as $$
declare v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select distinct 'outing_not_closed', '一時外出の未クローズ',
    o.name || ' で前日までの一時外出が未クローズです(' || g.cnt || '件)。戻り/降園の記録をご確認ください。',
    array['push', 'in_app'], mgr.employee_id,
    jsonb_build_object('office_id', g.office_id::text, 'date', v_today::text), 'pending'
  from (
    select co.office_id, count(*) as cnt
    from child_outings co
    where co.return_at is null and not co.converted_to_departure and co.business_date < v_today
    group by co.office_id
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

-- 08:00 JST(= 23:00 UTC)に実行。閉園後も残る前日の外出を翌朝まとめて主任へ。冪等(存在時のみ付替)。
do $$
begin
  if exists (select 1 from cron.job where jobname = 'detect_stale_outings') then
    perform cron.unschedule('detect_stale_outings');
  end if;
  perform cron.schedule('detect_stale_outings', '0 23 * * *', 'select cron_detect_stale_outings();');
end $$;
