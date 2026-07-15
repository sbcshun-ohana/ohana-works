-- 19章 施設ごとの給与内訳Excel出力用データ取得RPC。
--
-- 全銀協CSVは振込データとして完結しているが、運用上「施設ごとの給与内訳
-- (職員番号・氏名・所属施設・基本給・手当・通勤費・控除額・差引支給額)」を
-- 確認したいというニーズがあるため、payroll_details.office_breakdown
-- (jsonb、施設ごとの内訳)を展開して返す。
--
-- 月間勤怠Excel(fetch_attendance_export_by_office)と同じ認可パターン
-- (施設指定時はmanages_office、全体はis_labor_manager_plus限定)を踏襲する。
-- 給与確定前(draft)でも内容確認・レビュー目的で出力できるよう、
-- ステータスによる制限は設けない(振込CSVとは異なり実際の送金には
-- 使わないため)。

create or replace function fetch_payroll_export_by_office(p_payroll_run_id uuid, p_office_id uuid)
returns table (
  employee_id uuid,
  employee_number text,
  employee_name text,
  office_id uuid,
  office_name text,
  is_home_office boolean,
  base_salary int,
  allowances int,
  commute int,
  subtotal int,
  deductions_total int,
  net_pay int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_office_id is not null and not manages_office(p_office_id) then
    raise exception 'not authorized to view payroll for this office';
  end if;
  if p_office_id is null and not is_labor_manager_plus() then
    raise exception 'not authorized to view all offices payroll ("全体" is labor manager and above only)';
  end if;

  if not exists (select 1 from payroll_runs where id = p_payroll_run_id) then
    raise exception 'payroll run not found';
  end if;

  return query
  select
    pd.employee_id,
    e.employee_number,
    e.name,
    (office_kv.key)::uuid,
    o.name,
    (office_kv.key)::uuid = e.home_office_id,
    (office_kv.value->>'base_salary')::int,
    (office_kv.value->>'allowances')::int,
    (office_kv.value->>'commute')::int,
    (office_kv.value->>'subtotal')::int,
    (office_kv.value->>'deductions_total')::int,
    (office_kv.value->>'net_pay')::int
  from payroll_details pd
  join employees e on e.id = pd.employee_id
  cross join lateral jsonb_each(pd.office_breakdown) as office_kv(key, value)
  join offices o on o.id = (office_kv.key)::uuid
  where pd.payroll_run_id = p_payroll_run_id
    and (p_office_id is null or (office_kv.key)::uuid = p_office_id)
  order by o.name, e.employee_number;
end;
$$;
