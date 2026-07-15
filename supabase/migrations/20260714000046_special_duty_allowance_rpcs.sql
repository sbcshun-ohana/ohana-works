-- 特殊業務手当(special_duty_allowances)の登録・確認・一覧取得RPC。
--
-- テーブル自体・給与計算エンジンからの参照(20260714000017以降)は既に
-- 存在していたが、労務担当者が入力するためのRPCが未整備だった
-- (event_commute_records追加時と同じ状況)。event_commute_recordsの
-- RPCパターンに合わせて追加する。

create or replace function set_special_duty_allowance(
  p_employee_id uuid,
  p_target_payroll_month date,
  p_amount int,
  p_reason_category text,
  p_reason_detail text,
  p_internal_memo text,
  p_show_on_payslip boolean,
  p_display_text text,
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

  insert into special_duty_allowances (
    employee_id, target_payroll_month, amount, reason_category, reason_detail,
    internal_memo, show_on_payslip, display_text, input_by, confirmed
  ) values (
    p_employee_id, date_trunc('month', p_target_payroll_month)::date, p_amount, p_reason_category, p_reason_detail,
    p_internal_memo, coalesce(p_show_on_payslip, true), p_display_text, my_employee_id(), coalesce(p_confirmed, false)
  )
  on conflict (employee_id, target_payroll_month) do update set
    amount = excluded.amount,
    reason_category = excluded.reason_category,
    reason_detail = excluded.reason_detail,
    internal_memo = excluded.internal_memo,
    show_on_payslip = excluded.show_on_payslip,
    display_text = excluded.display_text,
    confirmed = excluded.confirmed,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function delete_special_duty_allowance(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_labor_manager_plus() then
    raise exception 'not authorized';
  end if;

  delete from special_duty_allowances where id = p_id;
end;
$$;

create or replace function fetch_special_duty_allowances(p_month date)
returns table (
  id uuid,
  employee_id uuid,
  employee_name text,
  target_payroll_month date,
  amount int,
  reason_category text,
  reason_detail text,
  internal_memo text,
  show_on_payslip boolean,
  display_text text,
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
  select sda.id, sda.employee_id, e.name, sda.target_payroll_month, sda.amount, sda.reason_category,
         sda.reason_detail, sda.internal_memo, sda.show_on_payslip, sda.display_text, sda.confirmed
  from special_duty_allowances sda
  join employees e on e.id = sda.employee_id
  where sda.target_payroll_month = date_trunc('month', p_month)::date
  order by e.name;
end;
$$;
