-- admin_web「シフト管理」画面(週次テンプレート・イレギュラー例外の編集)向けに、
-- 選択した施設に所属する在籍中の職員一覧を返すRPC。
-- 保育業務ドメインの fetch_childcare_office_staff (has_childcare_office_access基準)とは
-- 権限系統が異なるため流用せず、労務ドメインの manages_office() を基準に新設する。

create or replace function fetch_office_employees(p_office_id uuid)
returns table (employee_id uuid, name text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not manages_office(p_office_id) then
    raise exception 'not authorized to view employees for this office';
  end if;

  return query
  select e.id, e.name
  from employees e
  where e.home_office_id = p_office_id
    and (e.resignation_date is null or e.resignation_date >= current_date)
  order by e.name;
end;
$$;
