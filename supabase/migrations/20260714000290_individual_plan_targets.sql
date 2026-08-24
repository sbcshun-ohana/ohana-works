-- 290: 加配(個人案対象)の個別設定 + 個人案対象児の判定。
-- 俊確定(2026-08-24): 個人案が必要=0・1・2歳児クラス全員 + 加配児童(クラス問わず)。
-- 3・4・5歳児は加配児のみ個人案が必要(加配でなければ不要)。加配は園児個別に登録・チェックできるようにする。
-- 284で children.individual_plan_target(既定false)を追加済み。ここに設定RPCと対象児取得RPCを足す。

-- 加配(個人案対象)の個別ON/OFF(主任以上)。
create or replace function set_child_individual_plan_target(p_child_id uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from children where id = p_child_id;
  if v_office is null then raise exception 'child not found'; end if;
  if not manages_childcare(v_office) then raise exception 'not authorized'; end if;
  update children set individual_plan_target = coalesce(p_on, false) where id = p_child_id;
end $$;
grant execute on function set_child_individual_plan_target(uuid, boolean) to authenticated, service_role;

-- 園児マスタ表示用: 加配フラグ一覧(在籍中)。全職員閲覧可。
create or replace function fetch_child_kahai_flags(p_office_id uuid)
returns table (child_id uuid, individual_plan_target boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not has_childcare_office_access(p_office_id) then raise exception 'not authorized'; end if;
  return query
    select c.id, c.individual_plan_target from children c
    where c.office_id = p_office_id and c.enrollment_status = '在籍中';
end $$;
grant execute on function fetch_child_kahai_flags(uuid) to authenticated, service_role;

-- 月案の個人案 対象児: そのクラスの在籍児のうち、クラス年齢0-2歳は全員 / 3-5歳は加配児のみ。
create or replace function fetch_guidance_individual_targets(p_plan_id uuid)
returns table (child_id uuid, display_name text, is_kahai boolean)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid; v_class uuid; v_type text; v_age int;
begin
  select gp.office_id, gp.class_id, gp.plan_type into v_office, v_class, v_type from guidance_plans gp where gp.id = p_plan_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  if v_type <> 'monthly' or v_class is null then return; end if;
  select substring(cc.age_group from '(\d)歳')::int into v_age from childcare_classes cc where cc.id = v_class;
  return query
    select c.id, c.display_name, c.individual_plan_target
    from children c
    join child_class_enrollments cce on cce.child_id = c.id and cce.effective_end_date is null and cce.class_id = v_class
    where c.office_id = v_office and c.enrollment_status = '在籍中'
      and (coalesce(v_age, 9) <= 2 or c.individual_plan_target)
    order by c.display_name;
end $$;
grant execute on function fetch_guidance_individual_targets(uuid) to authenticated, service_role;
