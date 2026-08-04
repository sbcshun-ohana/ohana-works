-- 第2段フロント有効化: 役職・担任の読み取りRPC(employee_roles/class_homeroom_assignments は RLSで
-- 直接SELECT不可のため)。roles/offices は authenticated 直読み可。付与可能役職の絞り込みは
-- 既存 my_min_role_sort_order() を front が呼び、roles(直読み) を sort_order で絞る。

-- 職員の現在の役職(閲覧=労務 or 統括園長)
create or replace function fetch_employee_roles(p_employee_id uuid)
returns table (role_code text, office_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (is_labor_manager_plus() or is_executive_or_system_admin()) then
    raise exception 'not authorized';
  end if;
  return query
  select r.code, er.office_id
  from employee_roles er join roles r on r.id = er.role_id
  where er.employee_id = p_employee_id
  order by r.sort_order;
end; $$;

-- 施設のクラス担任(現任のみ・閲覧=manages_childcare=統括園長可)
create or replace function fetch_class_homerooms(p_office_id uuid)
returns table (class_id uuid, class_name text, employee_id uuid, employee_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not manages_childcare(p_office_id) then
    raise exception 'not authorized';
  end if;
  return query
  select cc.id, cc.class_name, e.id, e.name
  from childcare_classes cc
  left join class_homeroom_assignments cha on cha.class_id = cc.id and cha.unassigned_at is null
  left join employees e on e.id = cha.employee_id
  where cc.office_id = p_office_id and cc.is_active
  order by cc.age_group, cc.class_name, e.name;
end; $$;
