-- 281: 除去食の保護者同意のお知らせ(青バー)を「確認済みにする」で消せるようにする。
-- 俊指示(2026-08-24): 直近7日で自動的に消えるのではなく、園が確認した時点で消えるようにしたい。
-- meal_conference_consents に acknowledged_at を追加し、青バーは「未確認(acknowledged_at is null)」のみ表示。
-- 確認操作(acknowledge_meal_consents・主任以上)で当該施設の未確認同意をまとめて確認済みにする。

alter table meal_conference_consents add column if not exists acknowledged_at timestamptz;
alter table meal_conference_consents add column if not exists acknowledged_by uuid references employees(id);

-- 未確認の保護者同意の件数(給食会議ページのお知らせバナー用)。全職員閲覧可。
create or replace function fetch_unacknowledged_meal_consent_count(p_office_id uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return (select count(*)::int from meal_conference_consents
          where office_id = p_office_id and acknowledged_at is null);
end $$;
grant execute on function fetch_unacknowledged_meal_consent_count(uuid) to authenticated, service_role;

-- 未確認の保護者同意をまとめて確認済みにする(主任以上)。→ 青バーが消える。
create or replace function acknowledge_meal_consents(p_office_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then raise exception 'not authorized'; end if;
  update meal_conference_consents set acknowledged_at = now(), acknowledged_by = my_employee_id()
  where office_id = p_office_id and acknowledged_at is null;
end $$;
grant execute on function acknowledge_meal_consents(uuid) to authenticated, service_role;

-- アラート集計: 青(info)の除去食同意を「未確認のみ」に変更(7日窓は廃止)。他は 280 と同一。
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

  -- 赤(action): 感染症の書類待ち。
  if is_infection_control_enabled_for_office(p_office_id) then
    return query
      select 'infection_document'::text, '感染症の書類待ち'::text, count(*),
             '/childcare/daily-board'::text, 'action'::text
      from infection_cases
      where office_id = p_office_id and status <> 'closed' and document_state = 'required_not_submitted'
      having count(*) > 0;
  end if;

  -- 青(info): 除去食の保護者同意がありました(未確認のみ・確認で消える)。
  return query
    select 'meal_consent_recent'::text, '除去食の保護者同意がありました'::text, count(*),
           '/childcare/meal-conferences'::text, 'info'::text
    from meal_conference_consents
    where office_id = p_office_id and acknowledged_at is null
    having count(*) > 0;

  -- 青(info): 給食会議の保護者同意待ち。
  return query
    select 'meal_consent_pending'::text, '給食会議の保護者同意待ち'::text, count(*),
           '/childcare/meal-conferences'::text, 'info'::text
    from meal_conferences
    where office_id = p_office_id and status = 'held'
    having count(*) > 0;
end $$;
grant execute on function fetch_childcare_alerts_for_office(uuid) to authenticated, service_role;
