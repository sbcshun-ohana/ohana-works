-- 248: ヒヤリハット・事故報告 Phase A ③(ワークフローRPC + 承認通知)。§4準拠。
-- 作成/下書き保存(全コレクション置換)・申請(必須検証)・2段階承認・差し戻し・承認取消・
-- 承認後の経過/保護者連絡の追記。認可はRPC内で実施(RLSはselectのみ)。
-- 通知は notifications outbox(申請→主任以上/主任承認→統括/承認・差し戻し→記入者)。

-- 下書きの作成/保存(status='draft'のみ・記入者 or 主任以上)。子コレクションは全置換。
create or replace function save_incident_report(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office uuid := (p_payload->>'office_id')::uuid;
  v_type text := p_payload->>'report_type';
  v_id uuid := p_id;
  v_status text;
  v_created_by uuid;
  v_on date := coalesce((p_payload->>'occurred_on')::date, current_date);
begin
  if v_id is null then
    if v_office is null or not has_childcare_office_access(v_office) then
      raise exception 'not authorized';
    end if;
    if not is_incident_reports_enabled_for_office(v_office) then
      raise exception 'feature disabled';
    end if;
    if v_type not in ('hiyari', 'minor', 'hospital') then
      raise exception 'invalid report_type';
    end if;
    insert into incident_reports (office_id, report_type, status, created_by, closure_status, occurred_on)
    values (v_office, v_type, 'draft', my_employee_id(),
            case when v_type in ('minor', 'hospital') then 'open' else null end, v_on)
    returning id, office_id into v_id, v_office;
  else
    select status, office_id, created_by into v_status, v_office, v_created_by
    from incident_reports where id = v_id;
    if not found then raise exception 'not found'; end if;
    if v_status <> 'draft' then raise exception 'only draft is editable'; end if;
    if not (v_created_by = my_employee_id() or manages_childcare(v_office)) then
      raise exception 'not authorized';
    end if;
  end if;

  update incident_reports set
    occurred_on = v_on,
    occurred_at = (p_payload->>'occurred_at')::time,
    place_option_id = (p_payload->>'place_option_id')::uuid,
    place_other = p_payload->>'place_other',
    situation_when = p_payload->>'situation_when',
    situation_where = p_payload->>'situation_where',
    situation_what = p_payload->>'situation_what',
    situation_result = p_payload->>'situation_result',
    staff_counts = coalesce(p_payload->'staff_counts', '{}'::jsonb),
    causes = coalesce(p_payload->'causes', '{}'::jsonb),
    injury_site_option_id = (p_payload->>'injury_site_option_id')::uuid,
    injury_detail = p_payload->>'injury_detail',
    first_aid = p_payload->>'first_aid',
    prevention_text = p_payload->>'prevention_text',
    note_text = p_payload->>'note_text'
  where id = v_id;

  -- 対象園児(氏名・当日のクラスをスナップショット)
  delete from incident_report_children where incident_report_id = v_id;
  insert into incident_report_children (incident_report_id, child_id, child_name_snapshot, class_name_snapshot)
  select v_id, ch.id, ch.display_name, cls.class_name
  from jsonb_array_elements(coalesce(p_payload->'children', '[]'::jsonb)) e
  join children ch on ch.id = (e->>'child_id')::uuid
  left join lateral (
    select cc.class_name
    from child_class_enrollments cce
    join childcare_classes cc on cc.id = cce.class_id
    where cce.child_id = ch.id
      and cce.effective_start_date <= v_on
      and (cce.effective_end_date is null or cce.effective_end_date >= v_on)
    order by cce.effective_start_date desc limit 1
  ) cls on true;

  -- 経過と観察記録
  delete from incident_report_progress_logs where incident_report_id = v_id;
  insert into incident_report_progress_logs
    (incident_report_id, logged_at, staff_employee_id, report_kind, report_text, created_by)
  select v_id, (e->>'logged_at')::timestamptz, (e->>'staff_employee_id')::uuid,
         e->>'report_kind', e->>'report_text', my_employee_id()
  from jsonb_array_elements(coalesce(p_payload->'progress_logs', '[]'::jsonb)) e;

  -- 保護者連絡
  delete from incident_report_guardian_contacts where incident_report_id = v_id;
  insert into incident_report_guardian_contacts
    (incident_report_id, contacted_at, staff_employee_id, contact_book_written, reaction_kind, reaction_text, created_by)
  select v_id, (e->>'contacted_at')::timestamptz, (e->>'staff_employee_id')::uuid,
         (e->>'contact_book_written')::boolean, e->>'reaction_kind', e->>'reaction_text', my_employee_id()
  from jsonb_array_elements(coalesce(p_payload->'guardian_contacts', '[]'::jsonb)) e;

  -- 受診記録(病院搬送・選択式)
  delete from incident_report_medical_visits where incident_report_id = v_id;
  insert into incident_report_medical_visits
    (incident_report_id, medical_institution, doctor_name, department_option_id, exam_option_ids,
     treatment_option_ids, exam_detail, doctor_instruction, prescription_present,
     prescription_option_ids, prescription_detail, treatment_period, created_by)
  select v_id, e->>'medical_institution', e->>'doctor_name', (e->>'department_option_id')::uuid,
    coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(e->'exam_option_ids') x), '{}'),
    coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(e->'treatment_option_ids') x), '{}'),
    e->>'exam_detail', e->>'doctor_instruction', (e->>'prescription_present')::boolean,
    coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(e->'prescription_option_ids') x), '{}'),
    e->>'prescription_detail', e->>'treatment_period', my_employee_id()
  from jsonb_array_elements(coalesce(p_payload->'medical_visits', '[]'::jsonb)) e;

  -- 保育課連絡
  delete from incident_report_childcare_dept_contacts where incident_report_id = v_id;
  insert into incident_report_childcare_dept_contacts
    (incident_report_id, contacted_at, contacted_to, content, created_by)
  select v_id, (e->>'contacted_at')::timestamptz, e->>'contacted_to', e->>'content', my_employee_id()
  from jsonb_array_elements(coalesce(p_payload->'childcare_dept_contacts', '[]'::jsonb)) e;

  -- 現場写真
  delete from incident_report_photos where incident_report_id = v_id;
  insert into incident_report_photos (incident_report_id, storage_key, sort_order, uploaded_by)
  select v_id, e->>'storage_key', coalesce((e->>'sort_order')::int, 0), my_employee_id()
  from jsonb_array_elements(coalesce(p_payload->'photos', '[]'::jsonb)) e;

  return v_id;
end;
$$;
grant execute on function save_incident_report(uuid, jsonb) to authenticated, service_role;

-- 申請(draft→submitted)。種別別の必須検証。通知=施設の主任以上。
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

  update incident_reports set status = 'submitted', submitted_at = now(), rejected_reason = null where id = p_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  select 'incident_report_submitted', 'ヒヤリハット・事故報告の申請',
         '報告書の承認申請が届きました。', array['in_app'], emp_id,
         jsonb_build_object('incident_report_id', p_id)
  from childcare_office_manager_employee_ids(r.office_id) as emp_id
  where emp_id <> my_employee_id();
end;
$$;
grant execute on function submit_incident_report(uuid) to authenticated, service_role;

-- 1段階目承認(submitted→chief_approved・主任以上 自施設)。通知=統括。
create or replace function chief_approve_incident_report(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype;
begin
  select * into r from incident_reports where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not manages_childcare(r.office_id) then raise exception 'not authorized'; end if;
  if r.status <> 'submitted' then raise exception 'invalid state'; end if;

  update incident_reports set status = 'chief_approved',
    chief_approved_by = my_employee_id(), chief_approved_at = now() where id = p_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  select distinct 'incident_report_chief_approved', 'ヒヤリハット・事故報告(主任承認済)',
         '統括園長の承認をお待ちしています。', array['in_app'], er.employee_id,
         jsonb_build_object('incident_report_id', p_id)
  from employee_roles er join roles ro on ro.id = er.role_id
  where ro.code in ('executive_director', 'system_admin') and er.employee_id <> my_employee_id();
end;
$$;
grant execute on function chief_approve_incident_report(uuid) to authenticated, service_role;

-- 2段階目承認(chief_approved→approved・統括以上)。approved_atが週次基準。通知=記入者。
create or replace function approve_incident_report(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype;
begin
  select * into r from incident_reports where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not is_executive_or_system_admin() then raise exception 'not authorized'; end if;
  if r.status <> 'chief_approved' then raise exception 'invalid state'; end if;

  update incident_reports set status = 'approved',
    approved_by = my_employee_id(), approved_at = now() where id = p_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  values ('incident_report_approved', 'ヒヤリハット・事故報告が承認されました',
          '報告書が承認されました。', array['in_app'], r.created_by,
          jsonb_build_object('incident_report_id', p_id));
end;
$$;
grant execute on function approve_incident_report(uuid) to authenticated, service_role;

-- 差し戻し(submitted→draft=主任以上 / chief_approved→draft=統括)。理由付き。通知=記入者。
create or replace function reject_incident_report(p_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype;
begin
  select * into r from incident_reports where id = p_id;
  if not found then raise exception 'not found'; end if;
  if r.status = 'submitted' then
    if not manages_childcare(r.office_id) then raise exception 'not authorized'; end if;
  elsif r.status = 'chief_approved' then
    if not is_executive_or_system_admin() then raise exception 'not authorized'; end if;
  else
    raise exception 'invalid state';
  end if;

  update incident_reports set status = 'draft', rejected_reason = p_reason,
    submitted_at = null, chief_approved_by = null, chief_approved_at = null where id = p_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  values ('incident_report_returned', 'ヒヤリハット・事故報告が差し戻されました',
          coalesce('理由: ' || p_reason, '差し戻されました。'), array['in_app'], r.created_by,
          jsonb_build_object('incident_report_id', p_id));
end;
$$;
grant execute on function reject_incident_report(uuid, text) to authenticated, service_role;

-- 承認取消(approved→draft・統括以上のみ)。理由付き。通知=記入者。
create or replace function cancel_incident_approval(p_id uuid, p_reason text)
returns void
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype;
begin
  select * into r from incident_reports where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not is_executive_or_system_admin() then raise exception 'not authorized'; end if;
  if r.status <> 'approved' then raise exception 'invalid state'; end if;

  update incident_reports set status = 'draft',
    approved_by = null, approved_at = null, chief_approved_by = null, chief_approved_at = null,
    submitted_at = null, rejected_reason = coalesce(p_reason, '承認取消') where id = p_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  values ('incident_report_approval_cancelled', 'ヒヤリハット・事故報告の承認が取り消されました',
          coalesce('理由: ' || p_reason, '承認が取り消されました。'), array['in_app'], r.created_by,
          jsonb_build_object('incident_report_id', p_id));
end;
$$;
grant execute on function cancel_incident_approval(uuid, text) to authenticated, service_role;

-- 承認後の追記(経過)。draft=記入者/主任以上、それ以降=主任以上(§4.1・監査は created_by で区別)。
create or replace function add_incident_progress_log(
  p_report_id uuid, p_logged_at timestamptz, p_staff_employee_id uuid, p_report_kind text, p_report_text text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype; v_id uuid;
begin
  select * into r from incident_reports where id = p_report_id;
  if not found then raise exception 'not found'; end if;
  if r.status = 'draft' then
    if not (r.created_by = my_employee_id() or manages_childcare(r.office_id)) then raise exception 'not authorized'; end if;
  else
    if not manages_childcare(r.office_id) then raise exception 'not authorized'; end if;
  end if;
  insert into incident_report_progress_logs
    (incident_report_id, logged_at, staff_employee_id, report_kind, report_text, created_by)
  values (p_report_id, p_logged_at, p_staff_employee_id, p_report_kind, p_report_text, my_employee_id())
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function add_incident_progress_log(uuid, timestamptz, uuid, text, text) to authenticated, service_role;

-- 承認後の追記(保護者連絡)。同上の認可。
create or replace function add_incident_guardian_contact(
  p_report_id uuid, p_contacted_at timestamptz, p_staff_employee_id uuid,
  p_contact_book_written boolean, p_reaction_kind text, p_reaction_text text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare r incident_reports%rowtype; v_id uuid;
begin
  select * into r from incident_reports where id = p_report_id;
  if not found then raise exception 'not found'; end if;
  if r.status = 'draft' then
    if not (r.created_by = my_employee_id() or manages_childcare(r.office_id)) then raise exception 'not authorized'; end if;
  else
    if not manages_childcare(r.office_id) then raise exception 'not authorized'; end if;
  end if;
  insert into incident_report_guardian_contacts
    (incident_report_id, contacted_at, staff_employee_id, contact_book_written, reaction_kind, reaction_text, created_by)
  values (p_report_id, p_contacted_at, p_staff_employee_id, p_contact_book_written, p_reaction_kind, p_reaction_text, my_employee_id())
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function add_incident_guardian_contact(uuid, timestamptz, uuid, boolean, text, text) to authenticated, service_role;
