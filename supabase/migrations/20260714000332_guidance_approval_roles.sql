-- 332: 指導計画の承認権限の見直し(俊指示 2026-08-25・訂正版)。
--  ・申請(submit)= 全職員(認可・企業主導型とも変わらず)。
--  ・主任確認(chief_check)= 認可(大和)のみ・主任以上。企業主導型は主任確認なし(元々1段)。
--  ・承認(approve)= 統括園長(executive_director)・園長(director)およびそれ以上(system_admin)。
--    統括管理者(area_manager)・現場管理者(office_manager)・主任(chief)は承認不可。両区分共通。
--  ・承認取消(cancel)= 承認者と同権限。
--  ・画面のボタン出し分け用に fetch_guidance_plan の plan に office_category / can_approve を付与。

-- 承認可能判定: 統括園長(全施設)・system_admin、園長(自施設)。※統括管理者(area_manager)は承認不可。
create or replace function can_approve_guidance_plan(target_office_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select
    -- 統括園長(全施設)・system_admin(=園長より上位)
    exists (select 1 from employee_roles er join roles r on r.id = er.role_id
            where er.employee_id = my_employee_id() and r.code in ('system_admin','executive_director'))
    -- 園長(自施設 / 全社園長=office_id null)
    or exists (select 1 from employee_roles er join roles r on r.id = er.role_id
               where er.employee_id = my_employee_id() and r.code = 'director'
                 and (er.office_id is null or er.office_id = target_office_id));
$$;
grant execute on function can_approve_guidance_plan(uuid) to authenticated, service_role;

-- 申請: 認可・企業主導型とも全職員(その施設の保育アクセス保持者)。
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

-- 承認: 統括園長・園長(およびそれ以上)のみ。authorized=chief_checked→approved / corporate_led=submitted→approved。
create or replace function approve_guidance_plan(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text; v_cat text; v_created uuid;
begin
  select gp.office_id, gp.status, o.office_category, gp.created_by into v_office, v_status, v_cat, v_created
  from guidance_plans gp join offices o on o.id = gp.office_id where gp.id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not can_approve_guidance_plan(v_office) then raise exception '承認は統括園長・園長が行えます'; end if;
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

-- 承認取消: 承認と同じ権限(統括園長・園長)。approved→draft。
create or replace function cancel_guidance_plan_approval(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text;
begin
  select office_id, status into v_office, v_status from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not can_approve_guidance_plan(v_office) then raise exception '承認取消は統括園長・園長が行えます'; end if;
  if v_status <> 'approved' then raise exception 'only approved can be cancelled'; end if;
  if coalesce(btrim(p_reason),'') = '' then raise exception '取消理由を入力してください'; end if;
  update guidance_plans set status = 'draft', approved_at = null, approved_by = null,
    chief_checked_at = null, chief_checked_by = null,
    rejected_reason = '[承認取消] ' || p_reason where id = p_id;
end $$;
grant execute on function cancel_guidance_plan_approval(uuid, text) to authenticated, service_role;

-- 詳細取得: plan に office_category と can_approve を付与(画面のボタン出し分け用)。
create or replace function fetch_guidance_plan(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v jsonb;
begin
  select office_id into v_office from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  select jsonb_build_object(
    'plan', to_jsonb(gp.*) || jsonb_build_object(
       'office_category', o.office_category,
       'can_approve', can_approve_guidance_plan(gp.office_id)),
    'template', to_jsonb(t.*),
    'individual', coalesce((select jsonb_agg(jsonb_build_object(
        'child_id', e.child_id, 'child_name', c.display_name, 'content', e.content) order by c.display_name)
      from guidance_plan_individual_entries e join children c on c.id = e.child_id where e.plan_id = gp.id), '[]'::jsonb)
  ) into v
  from guidance_plans gp
  join guidance_plan_templates t on t.id = gp.template_id
  join offices o on o.id = gp.office_id
  where gp.id = p_id;
  return v;
end $$;
grant execute on function fetch_guidance_plan(uuid) to authenticated, service_role;
