-- Phase 3(支援保育事業)のadmin_web画面実装向け。
-- 既存の fetch_my_childcare_offices / is_childcare_enabled_for_office は
-- 'childcare_operations' フラグ固定で、支援保育専用フラグ
-- ('support_childcare_program_enabled')では判定できないため、同型の
-- 専用関数・RPCを新設する(is_manager相当はis_support_childcare_chiefを使う)。

create or replace function is_support_childcare_enabled_for_office(p_office_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select enabled from feature_flag_employee_overrides
     where feature_key = 'support_childcare_program_enabled' and employee_id = my_employee_id()),
    (select enabled from feature_flag_office_overrides
     where feature_key = 'support_childcare_program_enabled' and office_id = p_office_id),
    (select default_enabled from feature_flags where feature_key = 'support_childcare_program_enabled'),
    false
  );
$$;

create or replace function fetch_my_support_childcare_offices()
returns table (office_id uuid, office_name text, is_manager boolean)
language plpgsql stable security definer set search_path = public
as $$
begin
  return query
  select o.id, o.name, is_support_childcare_chief(o.id)
  from offices o
  where is_support_childcare_enabled_for_office(o.id) and has_childcare_office_access(o.id)
  order by o.name;
end;
$$;
