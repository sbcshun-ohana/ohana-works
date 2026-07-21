-- 開発計画(改訂版 2026-07-17) Phase 1 / A-5: 自分の給与明細一覧RPC。
-- payslipsは自己SELECT可能だが、対象月(target_month)を持つpayroll_runsは
-- is_labor_manager_plus()のみのRLSのため、通常の埋め込みクエリでは一般職員から
-- 結合できない。RPCラッパー(security definer)で安全に結合して返す。
-- is_within_payslip_access_window()(20260714000110)を再利用し、退職後6ヶ月の
-- アクセス制限も適用する。12ヶ月表示の要件はlimitで実現する。

create or replace function fetch_my_payslips()
returns table (
  id uuid,
  payroll_run_id uuid,
  target_month date,
  file_path text,
  generated_at timestamptz,
  viewed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if my_employee_id() is null then
    raise exception 'not authorized';
  end if;
  if not is_within_payslip_access_window(my_employee_id()) then
    return;
  end if;

  return query
  select p.id, p.payroll_run_id, pr.target_month, p.file_path, p.generated_at, p.viewed_at
  from payslips p
  join payroll_runs pr on pr.id = p.payroll_run_id
  where p.employee_id = my_employee_id()
  order by pr.target_month desc
  limit 12;
end;
$$;
