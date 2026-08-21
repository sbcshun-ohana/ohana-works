-- 277: アラート集計に level を追加(action=赤バー=対応が必要 / info=青バー=お知らせ)。
-- 俊指示(2026-08-21): 対応が必要なものは赤、完了のお知らせ(保護者同意など)は青。
-- 保護者同意(272)は「除去食の同意がありました」を青のお知らせとして直近7日分表示。
-- ※同意後に園側の必須作業は現状なし(275の自動ゲートで除去食提供へ切替)。将来そうした作業を
--   追加する場合は、その未対応タスクを action(赤)としてこの関数に足す。

drop function if exists fetch_childcare_alerts_for_office(uuid);
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

  -- 青(info): 除去食の保護者同意がありました(直近7日)。対応不要のお知らせ。
  return query
    select 'meal_consent_recent'::text, '除去食の保護者同意がありました'::text, count(*),
           '/childcare/meal-conferences'::text, 'info'::text
    from meal_conference_consents
    where office_id = p_office_id and agreed_at >= now() - interval '7 days'
    having count(*) > 0;
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;
