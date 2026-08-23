-- 280: 保育業務アラートに2種追加。
--   赤(action): 感染症の書類待ち(登園許可書/登園届が必要だが未提出・案件が未クローズ・フラグON時)。
--   青(info): 給食会議の同意待ち(会議記録済みだが保護者同意がまだ=保護者アクション待ちのお知らせ)。
-- 戻り値の型は 277/279 と同一なので create or replace のみ。

create or replace function fetch_childcare_alerts_for_office(p_office_id uuid)
returns table (alert_type text, label text, cnt bigint, href text, level text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;

  -- 赤(action): アレルギー発症報告(未対応)。
  return query
    select 'allergy_incident'::text, 'アレルギー発症報告(未対応)'::text, count(*),
           '/childcare/allergy-incidents'::text, 'action'::text
    from allergy_incident_reports
    where office_id = p_office_id and status = 'reported'
    having count(*) > 0;

  -- 赤(action): ヒヤリハット・事故報告(未対応)。
  if is_incident_reports_enabled_for_office(p_office_id) then
    return query
      select 'incident_report'::text, 'ヒヤリハット・事故報告(未対応)'::text, count(*),
             '/childcare/incidents'::text, 'action'::text
      from incident_reports
      where office_id = p_office_id and status <> 'draft' and coalesce(closure_status, 'open') <> 'closed'
      having count(*) > 0;
  end if;

  -- 赤(action): 保護者からの連絡(未承認)。
  return query
    select 'parent_request'::text, '保護者からの連絡(未承認)'::text, count(*),
           '/childcare/parent-requests'::text, 'action'::text
    from parent_requests pr join children c on c.id = pr.child_id
    where c.office_id = p_office_id and pr.status = 'pending'
    having count(*) > 0;

  -- 赤(action): 感染症の書類待ち(登園許可書/登園届が必要だが未提出・未クローズ)。
  if is_infection_control_enabled_for_office(p_office_id) then
    return query
      select 'infection_document'::text, '感染症の書類待ち'::text, count(*),
             '/childcare/daily-board'::text, 'action'::text
      from infection_cases
      where office_id = p_office_id and status <> 'closed' and document_state = 'required_not_submitted'
      having count(*) > 0;
  end if;

  -- 青(info): 除去食の保護者同意がありました(直近7日)。
  return query
    select 'meal_consent_recent'::text, '除去食の保護者同意がありました'::text, count(*),
           '/childcare/meal-conferences'::text, 'info'::text
    from meal_conference_consents
    where office_id = p_office_id and agreed_at >= now() - interval '7 days'
    having count(*) > 0;

  -- 青(info): 給食会議の同意待ち(会議記録済み・保護者同意なし=保護者アクション待ち)。
  return query
    select 'meal_consent_pending'::text, '給食会議の保護者同意待ち'::text, count(*),
           '/childcare/meal-conferences'::text, 'info'::text
    from meal_conferences
    where office_id = p_office_id and status = 'held'
    having count(*) > 0;
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;
