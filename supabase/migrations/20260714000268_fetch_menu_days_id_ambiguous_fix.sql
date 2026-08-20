-- 268: fetch_menu_days_for_import の "column reference id is ambiguous" 修正。
-- RETURNS TABLE の id 列(=OUT変数 id)と menu_imports.id が曖昧だったため、menu_imports.id に修飾する。
create or replace function fetch_menu_days_for_import(p_import_id uuid)
returns table (id uuid, menu_date date, food_type text, removal_kind text, meal_slot text,
               menu_text text, ingredients jsonb, nutrition jsonb, removal_note text)
language plpgsql security definer set search_path = public as $$
declare v_office uuid;
begin
  select office_id into v_office from menu_imports where menu_imports.id = p_import_id;
  if v_office is null then raise exception 'not found'; end if;
  if not has_childcare_office_access(v_office) then raise exception 'not authorized'; end if;
  return query
    select d.id, d.menu_date, d.food_type, d.removal_kind, d.meal_slot,
           d.menu_text, d.ingredients, d.nutrition, d.removal_note
    from menu_days d where d.import_id = p_import_id
    order by d.menu_date, d.food_type, d.meal_slot;
end $$;
grant execute on function fetch_menu_days_for_import(uuid) to authenticated, service_role;
