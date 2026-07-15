-- 6.3/6.6 職員ごとの源泉徴収区分(甲欄/乙欄)・扶養人数の管理UI用RPC。
--
-- tax_withholding_statuses(20260710160002)は既に甲欄/乙欄・扶養人数を履歴管理
-- (effective_start_year_month/effective_end_year_month)する設計で存在し、
-- 給与計算エンジン(20260714000015)も既にこのテーブルを参照している。
-- これまで欠けていたのは、この値を労務管理者が入力するUIのみだったため、
-- employeesへのカラム追加(履歴管理の後退になる)は行わず、既存テーブルへの
-- 書き込みRPCと一覧取得RPCのみを追加する。

-- 新しい適用開始年月の行を挿入する。既存の「現在有効(終了日未設定)」な行が
-- それより前から始まっている場合は、前月を終了年月として履歴を自動的に閉じる
-- (6.3章の履歴管理: 変更履歴を残さず上書きしてはならない、33章準拠)。
create or replace function set_employee_tax_withholding_status(
  p_employee_id uuid,
  p_tax_column text,
  p_dependent_count int,
  p_submitted_flag boolean,
  p_effective_start_year_month date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new_id uuid;
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;
  if p_tax_column not in ('甲欄', '乙欄') then
    raise exception 'invalid tax_column: % (must be 甲欄 or 乙欄)', p_tax_column;
  end if;
  if p_dependent_count is null or p_dependent_count < 0 then
    raise exception 'dependent_count must be 0 or greater';
  end if;

  update tax_withholding_statuses
  set effective_end_year_month = (p_effective_start_year_month - interval '1 month')::date
  where employee_id = p_employee_id
    and effective_end_year_month is null
    and effective_start_year_month < p_effective_start_year_month;

  insert into tax_withholding_statuses (
    employee_id, submitted_flag, tax_column, dependent_count, effective_start_year_month, created_by
  ) values (
    p_employee_id, p_submitted_flag, p_tax_column, p_dependent_count, p_effective_start_year_month,
    my_employee_id()
  )
  returning id into v_new_id;

  return v_new_id;
end;
$$;

-- 職員一覧+現在(直近)の源泉徴収区分・扶養人数を1回で取得する。
-- 未設定の職員はtax_column等がnullで返る(給与計算エンジンは未設定時に乙欄/0人扱い)。
create or replace function fetch_employees_tax_withholding_status()
returns table (
  employee_id uuid,
  employee_name text,
  office_name text,
  tax_column text,
  dependent_count int,
  submitted_flag boolean,
  effective_start_year_month date
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
  select
    e.id, e.name, o.name,
    tws.tax_column, tws.dependent_count, tws.submitted_flag, tws.effective_start_year_month
  from employees e
  join offices o on o.id = e.home_office_id
  left join lateral (
    select tax_column, dependent_count, submitted_flag, effective_start_year_month
    from tax_withholding_statuses
    where employee_id = e.id and effective_start_year_month <= current_date
    order by effective_start_year_month desc
    limit 1
  ) tws on true
  where e.resignation_date is null
  order by e.name;
end;
$$;
