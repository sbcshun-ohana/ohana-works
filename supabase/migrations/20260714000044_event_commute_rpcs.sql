-- イベント直行日の通勤費 登録・確認・一覧取得RPC。

create or replace function set_event_commute_record(
  p_employee_id uuid,
  p_work_date date,
  p_destination text,
  p_amount int,
  p_taxable boolean,
  p_confirmed boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'amountは0以上で指定してください';
  end if;

  insert into event_commute_records (
    employee_id, work_date, destination, amount, taxable, confirmed, created_by
  ) values (
    p_employee_id, p_work_date, p_destination, p_amount, p_taxable, p_confirmed, my_employee_id()
  )
  on conflict (employee_id, work_date) do update set
    destination = excluded.destination,
    amount = excluded.amount,
    taxable = excluded.taxable,
    confirmed = excluded.confirmed,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function delete_event_commute_record(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  delete from event_commute_records where id = p_id;
end;
$$;

create or replace function fetch_event_commute_records(p_month date)
returns table (
  id uuid,
  employee_id uuid,
  employee_name text,
  work_date date,
  destination text,
  amount int,
  taxable boolean,
  confirmed boolean
)
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
  select ecr.id, ecr.employee_id, e.name, ecr.work_date, ecr.destination, ecr.amount, ecr.taxable, ecr.confirmed
  from event_commute_records ecr
  join employees e on e.id = ecr.employee_id
  where date_trunc('month', ecr.work_date)::date = date_trunc('month', p_month)::date
  order by ecr.work_date, e.name;
end;
$$;
