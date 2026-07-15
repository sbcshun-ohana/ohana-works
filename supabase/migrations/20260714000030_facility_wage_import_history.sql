-- 施設別基本給・手当CSV取込の反映履歴取得RPC。

create or replace function fetch_employee_facility_wages_import_history()
returns table (id uuid, file_name text, imported_by_name text, imported_at timestamptz, imported_count int)
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
  select fil.id, fil.file_name, e.name, fil.imported_at, fil.imported_count
  from file_import_logs fil
  left join employees e on e.id = fil.imported_by
  where fil.import_target = 'employee_facility_wages'
  order by fil.imported_at desc;
end;
$$;

create or replace function fetch_employee_facility_allowances_import_history()
returns table (id uuid, file_name text, imported_by_name text, imported_at timestamptz, imported_count int)
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
  select fil.id, fil.file_name, e.name, fil.imported_at, fil.imported_count
  from file_import_logs fil
  left join employees e on e.id = fil.imported_by
  where fil.import_target = 'employee_facility_allowances'
  order by fil.imported_at desc;
end;
$$;
