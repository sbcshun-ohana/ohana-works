-- 通勤費CSVのプレビュー画面でoffice_id=home_office_idを検証するため、
-- 職員一覧取得RPCにhome_office_idを追加する。
-- 戻り値の列構成が変わるため、create or replaceの前に旧定義を削除する。
drop function if exists fetch_employee_directory();

create or replace function fetch_employee_directory()
returns table (employee_number text, name text, home_office_id uuid)
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
  select e.employee_number, e.name, e.home_office_id from employees e
  where e.resignation_date is null
  order by e.employee_number;
end;
$$;
