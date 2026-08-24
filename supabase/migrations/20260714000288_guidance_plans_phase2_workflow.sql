-- 288: 指導計画 Phase 2-b = 状態遷移(申請→主任確認→承認/差し戻し/承認取消)+必須欄検証+通知。
-- 認可(大和)=担当申請→主任確認→園長承認(2段)/企業主導型3施設=担当申請→管理者承認(1段)。
-- 必須欄検証=テンプレの required 欄が本文に入っているか(個人案の全員検証はPhase後続で追加予定)。

-- 未記入の必須欄ラベルを「、」区切りで返す(空=充足)。
create or replace function guidance_plan_missing_required(p_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select string_agg(f->>'label', '、')
  from guidance_plans gp
  join guidance_plan_templates t on t.id = gp.template_id,
       jsonb_array_elements(t.sections) s,
       jsonb_array_elements(s->'fields') f
  where gp.id = p_id
    and coalesce((f->>'required')::boolean, false)
    and coalesce(nullif(btrim(coalesce(gp.content->>(f->>'key'), '')), ''), '') = '';
$$;

-- 申請(draft→submitted)。必須欄検証→主任以上へ通知。
create or replace function submit_guidance_plan(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text; v_missing text; v_type text;
begin
  select office_id, status, plan_type into v_office, v_status, v_type from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if v_status <> 'draft' then raise exception 'only draft can be submitted'; end if;
  v_missing := guidance_plan_missing_required(p_id);
  if coalesce(v_missing,'') <> '' then raise exception '必須項目が未入力です: %', v_missing; end if;

  update guidance_plans set status = 'submitted', submitted_at = now(), submitted_by = my_employee_id(),
    rejected_reason = null where id = p_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select 'guidance_plan_submitted', '指導計画の申請', '指導計画の承認依頼が届きました。',
    array['in_app'], emp, jsonb_build_object('guidance_plan_id', p_id::text), 'pending'
  from childcare_office_manager_employee_ids(v_office) emp where emp <> my_employee_id();
end $$;
grant execute on function submit_guidance_plan(uuid) to authenticated, service_role;

-- 主任確認(authorizedのみ・submitted→chief_checked)。→ 承認者(園長/管理者)へ通知。
create or replace function chief_check_guidance_plan(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text; v_cat text;
begin
  select gp.office_id, gp.status, o.office_category into v_office, v_status, v_cat
  from guidance_plans gp join offices o on o.id = gp.office_id where gp.id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if v_cat <> 'authorized' then raise exception 'chief check only for authorized office'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if v_status <> 'submitted' then raise exception 'only submitted can be checked'; end if;
  update guidance_plans set status = 'chief_checked', chief_checked_at = now(), chief_checked_by = my_employee_id()
    where id = p_id;
  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select 'guidance_plan_checked', '指導計画の承認待ち', '主任確認が済み、園長承認をお待ちしています。',
    array['in_app'], emp, jsonb_build_object('guidance_plan_id', p_id::text), 'pending'
  from childcare_office_manager_employee_ids(v_office) emp where emp <> my_employee_id();
end $$;
grant execute on function chief_check_guidance_plan(uuid) to authenticated, service_role;

-- 承認(管理者以上)。authorized=chief_checked→approved / corporate_led=submitted→approved。→作成者へ通知。
create or replace function approve_guidance_plan(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text; v_cat text; v_created uuid;
begin
  select gp.office_id, gp.status, o.office_category, gp.created_by into v_office, v_status, v_cat, v_created
  from guidance_plans gp join offices o on o.id = gp.office_id where gp.id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not is_childcare_admin(v_office) then raise exception 'not authorized'; end if;
  if v_cat = 'authorized' and v_status <> 'chief_checked' then raise exception '主任確認後に承認できます'; end if;
  if v_cat = 'corporate_led' and v_status <> 'submitted' then raise exception '申請後に承認できます'; end if;
  update guidance_plans set status = 'approved', approved_at = now(), approved_by = my_employee_id() where id = p_id;
  if v_created is not null and v_created <> my_employee_id() then
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
    values ('guidance_plan_approved', '指導計画が承認されました', '申請した指導計画が承認されました。',
      array['in_app'], v_created, jsonb_build_object('guidance_plan_id', p_id::text), 'pending');
  end if;
end $$;
grant execute on function approve_guidance_plan(uuid) to authenticated, service_role;

-- 差し戻し(主任以上・submitted/chief_checked→draft・理由付き)。→作成者へ通知。
create or replace function reject_guidance_plan(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text; v_created uuid;
begin
  select office_id, status, created_by into v_office, v_status, v_created from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  if v_status not in ('submitted','chief_checked') then raise exception 'only submitted/checked can be rejected'; end if;
  if coalesce(btrim(p_reason),'') = '' then raise exception '差し戻し理由を入力してください'; end if;
  update guidance_plans set status = 'draft', rejected_reason = p_reason,
    submitted_at = null, submitted_by = null, chief_checked_at = null, chief_checked_by = null where id = p_id;
  if v_created is not null and v_created <> my_employee_id() then
    insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
    values ('guidance_plan_rejected', '指導計画が差し戻されました', '指導計画が差し戻されました: ' || p_reason,
      array['in_app'], v_created, jsonb_build_object('guidance_plan_id', p_id::text), 'pending');
  end if;
end $$;
grant execute on function reject_guidance_plan(uuid, text) to authenticated, service_role;

-- 承認取消(管理者以上・approved→draft・理由記録)。評価反省の後追い修正等はこの経路。
create or replace function cancel_guidance_plan_approval(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text;
begin
  select office_id, status into v_office, v_status from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not is_childcare_admin(v_office) then raise exception 'not authorized'; end if;
  if v_status <> 'approved' then raise exception 'only approved can be cancelled'; end if;
  if coalesce(btrim(p_reason),'') = '' then raise exception '取消理由を入力してください'; end if;
  update guidance_plans set status = 'draft', approved_at = null, approved_by = null,
    chief_checked_at = null, chief_checked_by = null,
    rejected_reason = '[承認取消] ' || p_reason where id = p_id;
end $$;
grant execute on function cancel_guidance_plan_approval(uuid, text) to authenticated, service_role;
