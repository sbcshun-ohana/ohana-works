-- 311: アラートバーに「重要事項説明書 未同意 N世帯」を追加(主任以上・同意必須の運用担保)。既存アラートは維持。
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
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;
