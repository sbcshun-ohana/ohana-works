-- 279: 保育業務アラートに「保護者からの連絡(未承認)」を赤(要対応)で追加。
-- 欠席・遅刻・服薬・お迎え変更などの未承認申請(parent_requests.status='pending')を見落とさないため。
-- 戻り値の型は 277 と同一(alert_type,label,cnt,href,level)なので create or replace のみ。

create or replace function fetch_childcare_alerts_for_office(p_office_id uuid)
returns table (alert_type text, label text, cnt bigint, href text, level text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;

  -- 赤(action): アレルギー発症報告(未対応)。園の確認・判断が必要。
  return query
    select 'allergy_incident'::text, 'アレルギー発症報告(未対応)'::text, count(*),
           '/childcare/allergy-incidents'::text, 'action'::text
    from allergy_incident_reports
    where office_id = p_office_id and status = 'reported'
    having count(*) > 0;

  -- 赤(action): ヒヤリハット・事故報告(未対応)。承認待ち+未クローズ。
  if is_incident_reports_enabled_for_office(p_office_id) then
    return query
      select 'incident_report'::text, 'ヒヤリハット・事故報告(未対応)'::text, count(*),
             '/childcare/incidents'::text, 'action'::text
      from incident_reports
      where office_id = p_office_id and status <> 'draft' and coalesce(closure_status, 'open') <> 'closed'
      having count(*) > 0;
  end if;

  -- 赤(action): 保護者からの連絡(未承認)。欠席/遅刻/服薬/お迎え変更等の承認待ち。
  return query
    select 'parent_request'::text, '保護者からの連絡(未承認)'::text, count(*),
           '/childcare/parent-requests'::text, 'action'::text
    from parent_requests pr join children c on c.id = pr.child_id
    where c.office_id = p_office_id and pr.status = 'pending'
    having count(*) > 0;

  -- 青(info): 除去食の保護者同意がありました(直近7日)。対応不要のお知らせ。
  return query
    select 'meal_consent_recent'::text, '除去食の保護者同意がありました'::text, count(*),
           '/childcare/meal-conferences'::text, 'info'::text
    from meal_conference_consents
    where office_id = p_office_id and agreed_at >= now() - interval '7 days'
    having count(*) > 0;
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;
