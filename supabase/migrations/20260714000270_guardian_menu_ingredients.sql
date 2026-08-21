-- 270: 保護者の献立RPCに材料(ingredients)を追加。戻り値変更のため drop→create→grant。
-- 保護者の閲覧画面にも材料を掲載する(俊指示2026-08-21)。ingredients jsonb(例 {"text":"..."})。
drop function if exists fetch_published_menu_days_for_guardian(uuid, date, text);
create or replace function fetch_published_menu_days_for_guardian(p_office_id uuid, p_target_month date, p_food_type text)
returns table (menu_date date, meal_slot text, menu_text text, ingredients jsonb)
language plpgsql security definer set search_path = public as $$
declare v_month date := date_trunc('month', p_target_month)::date;
begin
  if not exists (
    select 1 from guardian_child_links gcl join children c on c.id = gcl.child_id
    where gcl.guardian_id = my_guardian_id() and c.office_id = p_office_id
  ) then raise exception 'not authorized'; end if;
  if not is_meal_parent_section_enabled_for_office(p_office_id) then return; end if;
  if p_food_type = 'allergy_removed' then return; end if;
  return query
    select d.menu_date, d.meal_slot, d.menu_text, d.ingredients
    from menu_days d join menu_imports mi on mi.id = d.import_id
    where d.office_id = p_office_id and d.food_type = p_food_type and mi.status = 'published'
      and d.menu_date >= v_month and d.menu_date < (v_month + interval '1 month')::date
    order by d.menu_date, d.meal_slot;
end $$;
grant execute on function fetch_published_menu_days_for_guardian(uuid, date, text) to authenticated, service_role;
