-- 施設別基本給・手当CSV取込のプレビュー検証(employee_number→氏名表示)用。
-- employeesはRLSが本人のみのselectポリシーしか無く、labor_manager+でも
-- 直接一覧取得できないため、専用の読み取りRPCを追加する。

create or replace function fetch_employee_directory()
returns table (employee_number text, name text)
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
  select e.employee_number, e.name from employees e
  where e.resignation_date is null
  order by e.employee_number;
end;
$$;
