-- P0: イベント駆動プッシュ通知の自動化(1/4: 明細公開)。
-- 給与確定(confirm_payroll_run)を「明細公開」の発火点とし、対象職員ぶんの
-- notifications(outbox)行を1回のINSERTでまとめて積む。実配信は
-- dispatch-pending-notifications Edge Function(別途追加)が定期的にpendingを処理する。
--
-- 併せて、fetch_my_payslips(20260714000111)がpayroll_runs.statusを見ておらず
-- draft(未確定)の給与明細も職員から閲覧できてしまっていた問題を修正する
-- (「明細公開」の名の通り、確定前は非公開であるべき)。

create or replace function confirm_payroll_run(p_payroll_run_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status payroll_run_status;
  v_target_month date;
begin
  -- 17.2給与確定は人的な意思決定ポイントであり無人実行を想定しないため、常時認可を要求する
  -- (run_payroll等の集計エンジンと異なりauth.uid() is nullによるバイパスは設けない)。
  if not is_labor_manager_plus() then
    raise exception 'not authorized to confirm payroll run';
  end if;

  select status, target_month into v_status, v_target_month from payroll_runs where id = p_payroll_run_id;
  if v_status is null then
    raise exception 'payroll run not found';
  end if;
  if v_status <> 'draft' then
    raise exception 'payroll run is % and cannot be confirmed', v_status;
  end if;

  update payroll_runs
  set status = 'confirmed', confirmed_by = my_employee_id(), confirmed_at = now()
  where id = p_payroll_run_id;

  insert into notifications (
    notification_type, title, body, channels, target_employee_id, payload, status
  )
  select
    'payslip_published',
    '給与明細が公開されました',
    to_char(v_target_month, 'yyyy年mm月') || '分の給与明細を確認できます',
    array['fcm', 'in_app'],
    pd.employee_id,
    jsonb_build_object('payroll_run_id', p_payroll_run_id),
    'pending'
  from payroll_details pd
  where pd.payroll_run_id = p_payroll_run_id;
end;
$$;

-- 給与確定前(draft)の明細は職員本人にも非公開とする。
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
    and pr.status <> 'draft'
  order by pr.target_month desc
  limit 12;
end;
$$;
