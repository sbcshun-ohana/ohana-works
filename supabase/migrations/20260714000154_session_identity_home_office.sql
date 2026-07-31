-- 要件2 #2: ヘッダーの施設名表示のうち「所属施設(施設選択が無い画面のフォールバック)」用に、
-- fetch_my_session_identity へ home_office_name を追加する。返り値の列追加のため drop→create。
-- (既存の admin_web/Flutter 呼び出しは role_code までを読むため、列追加は非破壊。)
drop function if exists fetch_my_session_identity();
create or replace function fetch_my_session_identity()
returns table (employee_id uuid, name text, role_code text, home_office_name text)
language sql stable security definer set search_path = public
as $$
  select
    e.id,
    e.name,
    (select r.code from employee_roles er join roles r on r.id = er.role_id
       where er.employee_id = e.id order by r.sort_order limit 1) as role_code,
    (select o.name from offices o where o.id = e.home_office_id) as home_office_name
  from employees e
  where e.id = my_employee_id();
$$;
