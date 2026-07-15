-- 通勤費UIで「所属施設のみ登録可能」であることを表示するため、
-- 職員の所属施設(home_office_id)を取得する小さなRPCを追加する。

create or replace function fetch_employee_home_office(p_employee_id uuid)
returns table (office_id uuid, office_name text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  return query
  select e.home_office_id, o.name
  from employees e
  join offices o on o.id = e.home_office_id
  where e.id = p_employee_id;
end;
$$;
