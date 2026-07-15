-- 19章 振込CSV(全銀協フォーマット)の被仕向銀行名・支店名は半角カナ固定のため、
-- 既存のbank_name/branch_name(漢字の自由入力)とは別にカナ専用カラムを追加する。
-- 20260714000011で追加したbank_code/branch_codeと合わせて振込CSV生成に必須の項目となる。
alter table bank_accounts add column bank_name_kana text;
alter table bank_accounts add column branch_name_kana text;
alter table bank_transfer_accounts add column bank_name_kana text;
alter table bank_transfer_accounts add column branch_name_kana text;

-- 戻り値の列構成(OUT引数)が変わるためCREATE OR REPLACEでは差し替えできない。
drop function if exists fetch_office_payroll_payer(uuid);
drop function if exists fetch_payroll_transfer_recipients(uuid, uuid);

create function fetch_office_payroll_payer(p_office_id uuid)
returns table (
  office_name text,
  bank_name_kana text,
  branch_name_kana text,
  bank_code text,
  branch_code text,
  account_type text,
  account_number text,
  account_holder_name text
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
  select o.name, ba.bank_name_kana, ba.branch_name_kana, ba.bank_code, ba.branch_code,
         ba.account_type, ba.account_number, ba.account_holder_name
  from offices o
  join bank_accounts ba on ba.id = o.payroll_bank_account_id
  where o.id = p_office_id;
end;
$$;

create function fetch_payroll_transfer_recipients(p_payroll_run_id uuid, p_office_id uuid)
returns table (
  employee_id uuid,
  employee_name text,
  net_pay int,
  bank_name_kana text,
  branch_name_kana text,
  bank_code text,
  branch_code text,
  account_type text,
  account_number text,
  account_holder_name_kana text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_status payroll_run_status;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  select status into v_status from payroll_runs where id = p_payroll_run_id;
  if v_status is null then
    raise exception 'payroll run not found';
  end if;
  if v_status = 'draft' then
    raise exception '給与確定前の対象月は振込CSVを出力できません(17.2: 給与確定の後工程)';
  end if;

  return query
  select
    pd.employee_id, e.name, pd.net_pay,
    bta.bank_name_kana, bta.branch_name_kana, bta.bank_code, bta.branch_code,
    bta.account_type, bta.account_number, bta.account_holder_name_kana
  from payroll_details pd
  join employees e on e.id = pd.employee_id
  left join bank_transfer_accounts bta on bta.employee_id = pd.employee_id and bta.is_current = true
  where pd.payroll_run_id = p_payroll_run_id
    and e.home_office_id = p_office_id
  order by e.name;
end;
$$;
