-- 19章 振込データ: 全銀協フォーマットのヘッダーレコード必須項目「委託者コード」。
--
-- 銀行(横浜銀行)が総合振込サービス登録時に付与するコードで、施設ごとの
-- 支払元口座(bank_accounts)に紐づく。値が確定するまではNULLのままとし、
-- 振込CSV生成時は従来通りゼロ埋めで出力する(admin_web側で対応)。

alter table bank_accounts add column edi_client_code text;

comment on column bank_accounts.edi_client_code is
  '全銀協フォーマットのヘッダーレコード「委託者コード」(10桁、銀行から付与)。未確定の間はNULL。';

-- 戻り値にedi_client_codeを追加する。
drop function if exists fetch_office_payroll_payer(uuid);

create or replace function fetch_office_payroll_payer(p_office_id uuid)
returns table (
  office_name text,
  bank_name text,
  branch_name text,
  bank_code text,
  branch_code text,
  account_type text,
  account_number text,
  account_holder_name text,
  edi_client_code text
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
  select o.name, ba.bank_name, ba.branch_name, ba.bank_code, ba.branch_code,
         ba.account_type, ba.account_number, ba.account_holder_name, ba.edi_client_code
  from offices o
  join bank_accounts ba on ba.id = o.payroll_bank_account_id
  where o.id = p_office_id;
end;
$$;
