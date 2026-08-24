-- 294: 個人案の必須検証(AC-04)。月案の申請時、対象児(0-2歳全員/3-5歳は加配児)の個人案が
-- 記入済み(子どもの姿・ねらい・配慮環境構成)でないと申請不可。未記入の園児名を列挙。

-- 未記入の個人案対象児の氏名(「、」区切り。空=充足)。対象=fetch_guidance_individual_targetsと同一判定。
create or replace function guidance_plan_individual_missing(p_id uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v_class uuid; v_type text; v_age int; v_year int; v_month int; v_ms date; v_me date; v_result text;
begin
  select office_id, class_id, plan_type, fiscal_year, month into v_office, v_class, v_type, v_year, v_month
    from guidance_plans where id = p_id;
  if v_office is null then return ''; end if;
  if v_type <> 'monthly' or v_class is null then return ''; end if;
  select substring(cc.age_group from '(\d)歳')::int into v_age from childcare_classes cc where cc.id = v_class;
  v_ms := make_date(case when coalesce(v_month,4) >= 4 then v_year else v_year + 1 end, coalesce(v_month,4), 1);
  v_me := (v_ms + interval '1 month - 1 day')::date;
  select string_agg(c.display_name, '、' order by c.display_name) into v_result
  from children c
  join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null and cce.class_id = v_class
  where c.office_id = v_office and c.enrollment_status = '在籍中'
    and ( coalesce(v_age, 9) <= 2
          or exists (select 1 from child_kahai_periods k where k.child_id = c.id
                     and k.start_date <= v_me and (k.end_date is null or k.end_date >= v_ms)) )
    and not exists (
      select 1 from guidance_plan_individual_entries e
      where e.plan_id = p_id and e.child_id = c.id
        and coalesce(btrim(e.content->>'kidsstate'), '') <> ''
        and coalesce(btrim(e.content->>'aim'), '') <> ''
        and coalesce(btrim(e.content->>'consideration'), '') <> ''
    );
  return coalesce(v_result, '');
end $$;
grant execute on function guidance_plan_individual_missing(uuid) to authenticated, service_role;

-- submit_guidance_plan に個人案の必須検証を追加(288の内容 + 個人案チェック)。
create or replace function submit_guidance_plan(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid; v_status text; v_missing text; v_imiss text;
begin
  select office_id, status into v_office, v_status from guidance_plans where id = p_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if v_status <> 'draft' then raise exception 'only draft can be submitted'; end if;
  v_missing := guidance_plan_missing_required(p_id);
  if coalesce(v_missing,'') <> '' then raise exception '必須項目が未入力です: %', v_missing; end if;
  v_imiss := guidance_plan_individual_missing(p_id);
  if coalesce(v_imiss,'') <> '' then raise exception '個人案が未記入の園児がいます: %', v_imiss; end if;

  update guidance_plans set status = 'submitted', submitted_at = now(), submitted_by = my_employee_id(),
    rejected_reason = null where id = p_id;

  insert into notifications (notification_type, title, body, channels, target_employee_id, payload, status)
  select 'guidance_plan_submitted', '指導計画の申請', '指導計画の承認依頼が届きました。',
    array['in_app'], emp, jsonb_build_object('guidance_plan_id', p_id::text), 'pending'
  from childcare_office_manager_employee_ids(v_office) emp where emp <> my_employee_id();
end $$;
grant execute on function submit_guidance_plan(uuid) to authenticated, service_role;
