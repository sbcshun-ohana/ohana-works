-- 17章/19章/33章 給与確定フロー(確定ロック・確定解除・振込実行・振込CSV)
--
-- run_payroll()(20260714000008)は既にpayroll_runs.statusが'draft'以外なら
-- 再計算を拒否する仕組みを持つが、statusを'draft'から先へ進める手段が無かった。
-- 本マイグレーションで 確定(confirm)/確定解除(unlock)/振込実行(transfer) の
-- 状態遷移と、振込CSV(全銀協フォーマット)生成に必要なデータ取得RPCを追加する。
--
-- 33章準拠:
-- - 給与確定後の変更を再確定なしで反映してはならない → confirm後はrun_payroll()の
--   既存ガードにより再計算不可(本マイグレーションでは変更しない)
-- - 振込実行済みの給与を再確定してはならない → unlock_payroll_run()は
--   status='transferred'の場合は労務管理者・システム最高管理者問わず拒否する
-- - 確定ロック解除権限はシステム最高管理者のみ(17.4) → unlock_payroll_run()は
--   is_labor_manager_plus()ではなくsystem_adminロール限定でチェックする
-- - 変更履歴を残さず上書きしてはならない → payroll_runsは27章の監査対象テーブル
--   (DBトリガーで自動ログ)に含まれるが、unlock(確定解除)は特に例外的な操作のため
--   理由必須のアプリ層ログも追加する(3.3の実打刻修正と同じ二重ログ方針)

-- 振込先金融機関コード(全銀協フォーマットの必須項目)。既存のbank_name/branch_nameは
-- 自由入力のためコードを別途保持する。未入力の職員は振込CSV生成時にスキップされる。
alter table bank_accounts add column bank_code text;
alter table bank_accounts add column branch_code text;
alter table bank_transfer_accounts add column bank_code text;
alter table bank_transfer_accounts add column branch_code text;

-- システム最高管理者ロールを保有するか(17.4: 確定ロック解除はシステム最高管理者のみ)。
create or replace function is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id() and r.code = 'system_admin'
  );
$$;

-- 17.2 給与確定。draft以外からは実行不可。
create or replace function confirm_payroll_run(p_payroll_run_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status payroll_run_status;
begin
  -- 17.2給与確定は人的な意思決定ポイントであり無人実行を想定しないため、常時認可を要求する
  -- (run_payroll等の集計エンジンと異なりauth.uid() is nullによるバイパスは設けない)。
  if not is_labor_manager_plus() then
    raise exception 'not authorized to confirm payroll run';
  end if;

  select status into v_status from payroll_runs where id = p_payroll_run_id;
  if v_status is null then
    raise exception 'payroll run not found';
  end if;
  if v_status <> 'draft' then
    raise exception 'payroll run is % and cannot be confirmed', v_status;
  end if;

  update payroll_runs
  set status = 'confirmed', confirmed_by = my_employee_id(), confirmed_at = now()
  where id = p_payroll_run_id;
end;
$$;

-- 17.4 確定解除。システム最高管理者のみ。振込実行済み(transferred)は例外なく拒否する。
create or replace function unlock_payroll_run(p_payroll_run_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status payroll_run_status;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'reason is required';
  end if;
  -- 確定解除は例外的な取り消し操作であり無人実行を想定しないため、常時システム最高管理者を要求する。
  if not is_system_admin() then
    raise exception 'not authorized: unlocking a confirmed payroll run requires system_admin (17.4)';
  end if;

  select status into v_status from payroll_runs where id = p_payroll_run_id;
  if v_status is null then
    raise exception 'payroll run not found';
  end if;
  if v_status = 'transferred' then
    raise exception '振込実行済みの給与は再確定(確定解除)できません(33章)';
  end if;
  if v_status <> 'confirmed' then
    raise exception 'payroll run is % and is not locked', v_status;
  end if;

  update payroll_runs set status = 'draft' where id = p_payroll_run_id;

  insert into event_logs (
    operator_id, target_type, target_id, action, before_data, after_data, reason, operation_source
  ) values (
    my_employee_id(), 'payroll_runs', p_payroll_run_id, 'unlock',
    jsonb_build_object('status', 'confirmed'), jsonb_build_object('status', 'draft'),
    p_reason, 'app'
  );
end;
$$;

-- 振込実行済みとして記録する(実際の銀行への振込操作自体は本システム外で行う)。
create or replace function mark_payroll_transferred(p_payroll_run_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status payroll_run_status;
begin
  -- 振込実行の記録も人的な意思決定ポイントであり無人実行を想定しないため、常時認可を要求する。
  if not is_labor_manager_plus() then
    raise exception 'not authorized to mark payroll run as transferred';
  end if;

  select status into v_status from payroll_runs where id = p_payroll_run_id;
  if v_status is null then
    raise exception 'payroll run not found';
  end if;
  if v_status <> 'confirmed' then
    raise exception 'payroll run must be confirmed before marking as transferred (current: %)', v_status;
  end if;

  update payroll_runs
  set status = 'transferred', transferred = true, transferred_at = now()
  where id = p_payroll_run_id;
end;
$$;

-- 19章 振込データ: 振込CSV生成対象の施設一覧(その給与計算単位に対象職員がいる施設のみ)。
create or replace function fetch_payroll_run_offices(p_payroll_run_id uuid)
returns table (office_id uuid, office_name text)
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
  select distinct e.home_office_id, o.name
  from payroll_details pd
  join employees e on e.id = pd.employee_id
  join offices o on o.id = e.home_office_id
  where pd.payroll_run_id = p_payroll_run_id
  order by o.name;
end;
$$;

-- 19章 施設ごとの支払元口座(全銀協フォーマットのヘッダーレコード=委託者情報)。
create or replace function fetch_office_payroll_payer(p_office_id uuid)
returns table (
  office_name text,
  bank_name text,
  branch_name text,
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
  select o.name, ba.bank_name, ba.branch_name, ba.bank_code, ba.branch_code,
         ba.account_type, ba.account_number, ba.account_holder_name
  from offices o
  join bank_accounts ba on ba.id = o.payroll_bank_account_id
  where o.id = p_office_id;
end;
$$;

-- 19章 振込CSVのデータレコード対象者一覧(施設の基本所属職員×確定済み給与)。
-- 給与確定前(draft)のrunに対しては実行不可(確定前の金額を振込CSVへ出力しない)。
create or replace function fetch_payroll_transfer_recipients(p_payroll_run_id uuid, p_office_id uuid)
returns table (
  employee_id uuid,
  employee_name text,
  net_pay int,
  bank_name text,
  branch_name text,
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
    bta.bank_name, bta.branch_name, bta.bank_code, bta.branch_code,
    bta.account_type, bta.account_number, bta.account_holder_name_kana
  from payroll_details pd
  join employees e on e.id = pd.employee_id
  left join bank_transfer_accounts bta on bta.employee_id = pd.employee_id and bta.is_current = true
  where pd.payroll_run_id = p_payroll_run_id
    and e.home_office_id = p_office_id
  order by e.name;
end;
$$;
