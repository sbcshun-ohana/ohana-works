-- 19章 振込一覧Excel出力用データ取得RPC。
--
-- 全銀協CSV(fetch_payroll_transfer_recipients)と同じデータソース
-- (payroll_details.net_pay + bank_transfer_accounts)を使うが、以下の点で
-- 目視確認用に別のRPCとして用意する。
-- - 全施設分をまとめて1回で取得する(全銀協CSVは施設ごとに個別出力するため
--   施設指定が必須だが、確認資料は全施設を横断して見たいことが多い)
-- - 給与確定前(draft)でも出力可能とする(施設別給与内訳Excelと同じ考え方。
--   全銀協CSV側は実際の振込に使うデータのため確定後のみという制限を維持し、
--   本RPCはレビュー専用のため変更しない)
-- - 口座情報が未登録の職員も除外せず返す(account_info_readyフラグで
--   Excel側が区別できるようにする)

create or replace function fetch_payroll_transfer_list_export(p_payroll_run_id uuid)
returns table (
  employee_id uuid,
  employee_number text,
  employee_name text,
  employee_name_kana text,
  office_id uuid,
  office_name text,
  bank_name text,
  branch_name text,
  account_type text,
  account_number text,
  account_holder_name_kana text,
  net_pay int,
  account_info_ready boolean
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

  if not exists (select 1 from payroll_runs where id = p_payroll_run_id) then
    raise exception 'payroll run not found';
  end if;

  return query
  select
    pd.employee_id,
    e.employee_number,
    e.name,
    e.name_kana,
    e.home_office_id,
    o.name,
    bta.bank_name,
    bta.branch_name,
    bta.account_type,
    bta.account_number,
    bta.account_holder_name_kana,
    pd.net_pay,
    (bta.bank_code is not null and bta.branch_code is not null
      and bta.account_number is not null and bta.account_holder_name_kana is not null)
  from payroll_details pd
  join employees e on e.id = pd.employee_id
  join offices o on o.id = e.home_office_id
  left join bank_transfer_accounts bta on bta.employee_id = pd.employee_id and bta.is_current = true
  where pd.payroll_run_id = p_payroll_run_id
  order by o.name, e.employee_number;
end;
$$;
