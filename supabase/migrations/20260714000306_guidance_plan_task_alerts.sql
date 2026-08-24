-- 306: 指導計画のタスク管理アラート(主任以上)。未提出/未作成=要対応(action)、申請済み・未承認=承認待ち(info)。
-- 週案は企業主導型(corporate_led)のみ必須。大和(authorized)は月案まで。年間・全体的な計画・保育安全計画は全施設。
create or replace function fetch_guidance_plan_tasks_for_office(p_office_id uuid)
returns table (message text, level text, plan_type text, class_name text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_cat text; v_fiscal int; v_month int; v_week date; v_y int; cc record; v_status text;
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  if not is_guidance_plans_enabled_for_office(p_office_id) then return; end if;
  select office_category into v_cat from offices where id = p_office_id;
  v_y := extract(year from current_date)::int;
  v_month := extract(month from current_date)::int;
  v_fiscal := case when v_month >= 4 then v_y else v_y - 1 end;
  v_week := (date_trunc('week', current_date))::date;  -- 月曜

  -- 園単位: 全体的な計画
  v_status := (select status from guidance_plans where office_id = p_office_id and plan_type = 'overall' and fiscal_year = v_fiscal and class_id is null limit 1);
  if coalesce(v_status, '') in ('', 'draft') then return query select '全体的な計画 未提出'::text, 'action'::text, 'overall'::text, null::text;
  elsif v_status in ('submitted', 'chief_checked') then return query select '全体的な計画 承認待ち'::text, 'info'::text, 'overall'::text, null::text; end if;

  -- 園単位: 保育安全計画
  v_status := (select status from guidance_plans where office_id = p_office_id and plan_type = 'safety' and fiscal_year = v_fiscal and class_id is null limit 1);
  if coalesce(v_status, '') in ('', 'draft') then return query select '保育安全計画 未提出'::text, 'action'::text, 'safety'::text, null::text;
  elsif v_status in ('submitted', 'chief_checked') then return query select '保育安全計画 承認待ち'::text, 'info'::text, 'safety'::text, null::text; end if;

  -- クラス単位
  for cc in select id, class_name from childcare_classes where office_id = p_office_id and is_active order by class_name loop
    -- 年間指導計画
    v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'annual' and fiscal_year = v_fiscal limit 1);
    if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' 年間指導計画 未提出', 'action'::text, 'annual'::text, cc.class_name;
    elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' 年間指導計画 承認待ち', 'info'::text, 'annual'::text, cc.class_name; end if;

    -- 月案(当月)
    v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'monthly' and fiscal_year = v_fiscal and month = v_month limit 1);
    if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' ' || v_month || '月の月案 未提出', 'action'::text, 'monthly'::text, cc.class_name;
    elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' ' || v_month || '月の月案 承認待ち', 'info'::text, 'monthly'::text, cc.class_name; end if;

    -- 週案(企業主導型のみ・当週)
    if v_cat = 'corporate_led' then
      v_status := (select status from guidance_plans where office_id = p_office_id and class_id = cc.id and plan_type = 'weekly' and week_start_date = v_week limit 1);
      if coalesce(v_status, '') in ('', 'draft') then return query select cc.class_name || ' 今週の週案 未提出', 'action'::text, 'weekly'::text, cc.class_name;
      elsif v_status in ('submitted', 'chief_checked') then return query select cc.class_name || ' 今週の週案 承認待ち', 'info'::text, 'weekly'::text, cc.class_name; end if;
    end if;
  end loop;
end $$;
grant execute on function fetch_guidance_plan_tasks_for_office(uuid) to authenticated, service_role;

-- 既存アラートバーに「指導計画 未完了」サマリを追加(主任以上のみ・action件数)。
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

  -- 指導計画 未完了(主任以上のみ)。要対応(未提出)件数を赤、承認待ち件数を青で。
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
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;
