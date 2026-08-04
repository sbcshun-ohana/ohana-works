-- 職員マスタ部分開放 第2段: 基本情報の編集RPC。
-- A 氏名・所属編集(labor OR exec)。B 役職編集=昇格防止(操作者の最小sort_orderより厳密に下位のみ)
-- +自己role変更禁止+最後のsystem_admin/labor_manager剥奪禁止。C 担任は既存set_class_homeroom流用。
-- email は職員ログイン(PIN→auth_user_id)に未使用のため編集可。

-- A) 氏名・カナ・メール・所属
create or replace function update_employee_basic(
  p_employee_id uuid, p_name text, p_name_kana text, p_email text, p_home_office_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (is_labor_manager_plus() or is_executive_or_system_admin()) then
    raise exception 'not authorized';
  end if;
  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'name is required';
  end if;
  if p_home_office_id is null then
    raise exception 'home_office_id is required';
  end if;
  update employees
  set name = p_name, name_kana = p_name_kana, email = p_email, home_office_id = p_home_office_id
  where id = p_employee_id;
end; $$;

-- 操作者の最小 sort_order(最も上位の役職)。
create or replace function my_min_role_sort_order()
returns int language sql stable security definer set search_path = public as $$
  select min(r.sort_order) from employee_roles er join roles r on r.id = er.role_id
  where er.employee_id = my_employee_id();
$$;

-- B) 役職付与
create or replace function assign_employee_role(p_employee_id uuid, p_role_code text, p_office_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_actor uuid := my_employee_id(); v_actor_min int; v_target_sort int; v_role_id uuid;
begin
  -- 役職(=権限)の付与は組織の権限設計に属するため統括園長/system_adminのみ(labor_manager対象外)。
  if not is_executive_or_system_admin() then
    raise exception 'not authorized';
  end if;
  if p_employee_id = v_actor then
    raise exception 'cannot change your own role';
  end if;
  select id, sort_order into v_role_id, v_target_sort from roles where code = p_role_code;
  if v_role_id is null then raise exception 'unknown role'; end if;
  v_actor_min := my_min_role_sort_order();
  if v_actor_min is null or v_target_sort <= v_actor_min then
    raise exception 'cannot assign a role at or above your level';
  end if;
  insert into employee_roles (employee_id, role_id, office_id)
  values (p_employee_id, v_role_id, p_office_id)
  on conflict (employee_id, role_id, office_id) do nothing;
end; $$;

-- B) 役職剥奪
create or replace function remove_employee_role(p_employee_id uuid, p_role_code text, p_office_id uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_actor uuid := my_employee_id(); v_actor_min int; v_target_sort int; v_role_id uuid; v_others int;
begin
  -- 役職(=権限)の剥奪は統括園長/system_adminのみ(labor_manager対象外)。
  if not is_executive_or_system_admin() then
    raise exception 'not authorized';
  end if;
  if p_employee_id = v_actor then
    raise exception 'cannot change your own role';
  end if;
  select id, sort_order into v_role_id, v_target_sort from roles where code = p_role_code;
  if v_role_id is null then raise exception 'unknown role'; end if;
  v_actor_min := my_min_role_sort_order();
  if v_actor_min is null or v_target_sort <= v_actor_min then
    raise exception 'cannot remove a role at or above your level';
  end if;
  -- 最後の system_admin / labor_manager を剥奪させない(在籍者ベース)
  if p_role_code in ('system_admin', 'labor_manager') then
    select count(distinct er.employee_id) into v_others
    from employee_roles er
    join roles r on r.id = er.role_id
    join employees e on e.id = er.employee_id
    where r.code = p_role_code and e.resignation_date is null and er.employee_id <> p_employee_id;
    if v_others = 0 then
      raise exception 'cannot remove the last %', p_role_code;
    end if;
  end if;
  delete from employee_roles
  where employee_id = p_employee_id and role_id = v_role_id
    and (office_id is not distinct from p_office_id);
end; $$;
