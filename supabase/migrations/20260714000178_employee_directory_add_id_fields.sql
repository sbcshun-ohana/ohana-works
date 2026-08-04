-- 第2段フロント有効化: fetch_employee_directory に employee_id / name_kana / email を追加。
-- 編集UI(update_employee_basic 等)が employee_id と初期値を必要とするため。ゲートは 175 と同じ
-- (is_labor_manager_plus OR is_executive_or_system_admin)。列追加のため drop→再作成。

drop function if exists fetch_employee_directory();

create function fetch_employee_directory()
returns table (
  employee_id uuid,
  employee_number text,
  name text,
  name_kana text,
  email text,
  home_office_id uuid
)
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
  select e.id, e.employee_number, e.name, e.name_kana, e.email, e.home_office_id
  from employees e
  where e.resignation_date is null
  order by e.employee_number;
end;
$$;
