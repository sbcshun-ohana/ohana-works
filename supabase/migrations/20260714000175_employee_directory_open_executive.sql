-- 職員マスタ部分開放(第1段): 職員名簿の閲覧を統括園長にも開放する。
-- 氏名・所属のみの基本ロスター。労務系RPC(源泉/給与/手当/通勤費等)は is_labor_manager_plus 据置で
-- 統括園長を拒否(defense-in-depth)。PIN管理・施設職員一覧は既に manages_office で統括園長が呼べる。
-- area_manager には開放しない(is_executive_or_system_admin = executive_director/system_admin のみ)。

create or replace function fetch_employee_directory()
returns table (employee_number text, name text, home_office_id uuid)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (is_labor_manager_plus() or is_executive_or_system_admin()) then
    raise exception 'not authorized';
  end if;

  return query
  select e.employee_number, e.name, e.home_office_id from employees e
  where e.resignation_date is null
  order by e.employee_number;
end;
$$;
