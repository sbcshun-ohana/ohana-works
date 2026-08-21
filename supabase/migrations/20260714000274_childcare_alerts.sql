-- 274: 保育業務の重要事項アラート集計。管理者ウェブのアラートバーで未対応件数を表示する。
-- どのページを開いていても気づけるよう、施設単位で未対応の重要事項をまとめて返す。
-- 対象は拡張可能: 現状=アレルギー発症報告(未対応) / ヒヤリハット・事故報告(承認待ち+未クローズ)。
-- 全職員閲覧可(has_childcare_office_access)。件数0の種別は返さない。

create or replace function fetch_childcare_alerts_for_office(p_office_id uuid)
returns table (alert_type text, label text, cnt bigint, href text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;

  -- アレルギー発症報告(271): status='reported' の未対応。
  return query
    select 'allergy_incident'::text, 'アレルギー発症報告(未対応)'::text, count(*), '/childcare/allergy-incidents'::text
    from allergy_incident_reports
    where office_id = p_office_id and status = 'reported'
    having count(*) > 0;

  -- ヒヤリハット・事故報告(246-252): フラグON施設で、下書き以外かつ未クローズ(承認待ち含む)。
  if is_incident_reports_enabled_for_office(p_office_id) then
    return query
      select 'incident_report'::text, 'ヒヤリハット・事故報告(未対応)'::text, count(*), '/childcare/incidents'::text
      from incident_reports
      where office_id = p_office_id and status <> 'draft' and coalesce(closure_status, 'open') <> 'closed'
      having count(*) > 0;
  end if;
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;
