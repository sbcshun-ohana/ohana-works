-- 278: ヒヤリハット・事故報告の「記入者(作成者)」を申請押下時に確定する(連絡帳と同様)。
-- 俊指示(2026-08-21): 作成画面を開いたタイミングではなく、「申請する」を押したアカウントを
-- 記入者(created_by)にする。従来は下書き作成時(open/最初の保存)に created_by が入っていた。
-- created_by は fetch_incident_reports の created_by_name(記入者表示)に反映される。
-- ※他のロジックは 248 と同一(必須チェック・通知)。UPDATE に created_by = my_employee_id() を追加するのみ。

create or replace function submit_incident_report(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype; v_missing text := '';
begin
  select * into r from incident_reports where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not (r.created_by = my_employee_id() or manages_childcare(r.office_id)) then
    raise exception 'not authorized';
  end if;
  if r.status <> 'draft' then raise exception 'only draft can be submitted'; end if;

  if r.occurred_at is null then v_missing := v_missing || '発生時間 '; end if;
  if r.place_option_id is null and coalesce(r.place_other, '') = '' then v_missing := v_missing || '発生場所 '; end if;
  if coalesce(r.situation_when, '') = '' or coalesce(r.situation_where, '') = ''
     or coalesce(r.situation_what, '') = '' or coalesce(r.situation_result, '') = '' then
    v_missing := v_missing || '発生状況 ';
  end if;
  if not (coalesce(r.causes->>'child_behavior', '') <> '' or coalesce(r.causes->>'environment', '') <> ''
          or coalesce(r.causes->>'objects', '') <> '' or coalesce(r.causes->>'care_rules', '') <> '') then
    v_missing := v_missing || '原因・問題点 ';
  end if;
  if coalesce(r.prevention_text, '') = '' then v_missing := v_missing || '再発防止 '; end if;

  if r.report_type in ('minor', 'hospital') then
    if r.injury_site_option_id is null or coalesce(r.injury_detail, '') = '' or coalesce(r.first_aid, '') = '' then
      v_missing := v_missing || '発生後の対応 ';
    end if;
    if not exists (select 1 from incident_report_progress_logs where incident_report_id = p_id) then
      v_missing := v_missing || '経過と観察記録 ';
    end if;
    if not exists (select 1 from incident_report_guardian_contacts where incident_report_id = p_id) then
      v_missing := v_missing || '保護者連絡 ';
    end if;
  end if;
  if r.report_type = 'hospital' then
    if not exists (select 1 from incident_report_medical_visits where incident_report_id = p_id) then
      v_missing := v_missing || '受診記録 ';
    end if;
  end if;

  if v_missing <> '' then raise exception '必須項目が未入力です: %', v_missing; end if;

  -- 申請押下者を記入者(作成者)として確定(連絡帳と同様)。
  update incident_reports
    set status = 'submitted', submitted_at = now(), rejected_reason = null, created_by = my_employee_id()
    where id = p_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  select 'incident_report_submitted', 'ヒヤリハット・事故報告の申請',
         '報告書の承認申請が届きました。', array['in_app'], emp_id,
         jsonb_build_object('incident_report_id', p_id)
  from childcare_office_manager_employee_ids(r.office_id) as emp_id
  where emp_id <> my_employee_id();
end;
$$;
grant execute on function submit_incident_report(uuid) to authenticated, service_role;
