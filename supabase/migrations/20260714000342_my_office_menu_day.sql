-- 342: 職員の自己発注画面に当日・翌日の昼食メニューを表示するための取得RPC(献立管理 §4.3/AC-06)。
--   呼び出し職員の基本所属(employees.home_office_id)の公開済み献立(通常食種・除去食は除く)を返す。
create or replace function fetch_my_office_menu_day(p_date date)
returns table (food_type text, meal_slot text, menu_text text)
language plpgsql stable security definer set search_path = public as $$
declare v_office uuid;
begin
  select home_office_id into v_office from employees where id = my_employee_id();
  if v_office is null then return; end if;
  return query
    select d.food_type, d.meal_slot, d.menu_text
    from menu_days d
    join menu_imports mi on mi.id = d.import_id
    where d.office_id = v_office and d.menu_date = p_date and mi.status = 'published'
      and d.removal_kind is null
    order by d.food_type, d.meal_slot;
end $$;
grant execute on function fetch_my_office_menu_day(date) to authenticated, service_role;
