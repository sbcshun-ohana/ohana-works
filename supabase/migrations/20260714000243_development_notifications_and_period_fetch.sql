-- 243: 発達記録 Phase 5 = 通知配線 + 児童票用の期間取得RPC。
-- 通知は既存 notifications outbox(cron_dispatch_pending_notifications が配信)へ直接insert。
-- - 達成申請 → 主任以上(childcare_office_manager_employee_ids・申請者自身は除く)
-- - 承認/差し戻し → 申請者(直接登録=申請者なしのため通知なし)
-- fetch_development_achievements_for_period: 四半期児童票の後続実装が使う読み取り専用RPC。

-- 表示用テンプレート(カタログ。実挿入はRPCが直接行う既存流儀に合わせる)
insert into notification_templates (template_key, title_template, body_template, channels) values
  ('childcare_development_request_submitted', '発達記録・達成申請', '達成申請が届きました。承認待ちです。', array['in_app']),
  ('childcare_development_request_approved', '達成申請が承認されました', '発達項目の達成が確定しました。', array['in_app']),
  ('childcare_development_request_returned', '達成申請が差し戻されました', '理由: {{reason}}', array['in_app'])
on conflict (template_key) do nothing;

-- ─────────────────────────────────────────────────────────────
-- 1) 達成申請(239)に「主任以上へ通知」を追加(署名・戻り型不変)
create or replace function submit_development_achievement_request(
  p_child_id uuid, p_item_id uuid,
  p_source text default 'manual', p_ai_candidate_id uuid default null, p_note text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare v_office uuid; v_req uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not (is_child_homeroom_staff(p_child_id) or manages_childcare(v_office)) then
    raise exception 'not authorized';
  end if;
  if p_source not in ('manual','ai_candidate') then raise exception 'invalid source'; end if;
  if not exists (select 1 from development_item_masters where id = p_item_id and is_active) then
    raise exception 'item not found or inactive';
  end if;
  if exists (select 1 from child_development_achievements
             where child_id = p_child_id and item_id = p_item_id and is_active) then
    raise exception '既に達成済みです';
  end if;

  insert into development_achievement_requests
    (child_id, office_id, item_id, source, ai_candidate_id, note, status, requested_by)
  values (p_child_id, v_office, p_item_id, p_source, p_ai_candidate_id, p_note, 'pending_review', my_employee_id())
  returning id into v_req;

  -- 主任以上へ承認待ち通知(申請者自身は除く)
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
  select 'childcare_development_request_submitted', '発達記録・達成申請',
         '達成申請が届きました。承認待ちです。', array['in_app'], emp_id,
         jsonb_build_object('request_id', v_req, 'child_id', p_child_id, 'item_id', p_item_id)
  from childcare_office_manager_employee_ids(v_office) as emp_id
  where emp_id <> my_employee_id();

  return v_req;
exception when unique_violation then
  raise exception '既に承認待ちの申請があります';
end $$;

-- 2) 承認/差し戻し(239)に「申請者へ通知」を追加(署名・戻り型不変)
create or replace function decide_development_achievement_request(
  p_request_id uuid, p_approve boolean, p_note text default null,
  p_first_achieved_on date default null, p_target_year_month text default null
) returns uuid
language plpgsql security definer set search_path = public
as $$
declare r development_achievement_requests%rowtype; v_ach uuid; v_method text;
begin
  select * into r from development_achievement_requests where id = p_request_id;
  if r.id is null then raise exception 'request not found'; end if;
  if not manages_childcare(r.office_id) then raise exception 'not authorized'; end if;
  if r.status <> 'pending_review' then raise exception '処理済みの申請です'; end if;

  if p_approve then
    v_method := case when r.source = 'ai_candidate' then 'ai_request' else 'manual_request' end;
    v_ach := create_dev_achievement_internal(
      r.child_id, r.item_id, v_method, r.requested_by, r.ai_candidate_id,
      p_first_achieved_on, p_target_year_month);
    update development_achievement_requests
      set status = 'approved', decided_by = my_employee_id(), decided_at = now(), decide_note = p_note
      where id = p_request_id;

    if r.requested_by is not null and r.requested_by <> my_employee_id() then
      insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
      values ('childcare_development_request_approved', '達成申請が承認されました',
              '発達項目の達成が確定しました。', array['in_app'], r.requested_by,
              jsonb_build_object('request_id', p_request_id, 'child_id', r.child_id, 'item_id', r.item_id, 'achievement_id', v_ach));
    end if;
    return v_ach;
  else
    update development_achievement_requests
      set status = 'returned', decided_by = my_employee_id(), decided_at = now(), decide_note = p_note
      where id = p_request_id;

    if r.requested_by is not null and r.requested_by <> my_employee_id() then
      insert into notifications (notification_type, title, body, channels, target_employee_id, payload)
      values ('childcare_development_request_returned', '達成申請が差し戻されました',
              coalesce('理由: ' || p_note, '差し戻されました。'), array['in_app'], r.requested_by,
              jsonb_build_object('request_id', p_request_id, 'child_id', r.child_id, 'item_id', r.item_id));
    end if;
    return null;
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────
-- 3) 児童票用: 期間内(first_achieved_on)の有効達成をスナップショット付きで返す(読み取り専用)。
--    年齢区分は達成時点の版スナップショット(development_item_master_versions)を優先。
create or replace function fetch_development_achievements_for_period(
  p_child_id uuid, p_from date, p_to date
) returns table (
  achievement_id uuid, item_id uuid, age_band_code text, domain_code text,
  item_name text, observation_point text, first_achieved_on date,
  target_year_month text, method text, approved_by_name text
)
language plpgsql stable security definer set search_path = public
as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;

  return query
  select a.id, a.item_id, coalesce(v.age_band_code, m.age_band_code), a.domain_code,
         a.item_name, a.observation_point, a.first_achieved_on, a.target_year_month,
         a.method, e.name
  from child_development_achievements a
  left join development_item_master_versions v on v.id = a.item_version_id
  left join development_item_masters m on m.id = a.item_id
  left join employees e on e.id = a.approved_by
  where a.child_id = p_child_id and a.is_active
    and a.first_achieved_on between p_from and p_to
  order by a.first_achieved_on, a.domain_code;
end $$;
grant execute on function fetch_development_achievements_for_period(uuid, date, date) to authenticated, service_role;
