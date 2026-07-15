-- 15章/28.4 各種申請(第2弾: 欠勤連絡・遅刻早退・情報変更) 承認導線の追加
--
-- 欠勤連絡(absence)・遅刻早退(tardiness_early_leave)は requests のステータス更新のみで
-- 副作用が無いため、20260714000004で追加済みの requests_update_managers ポリシーを
-- そのまま使う(追加ポリシーは不要)。
--
-- 情報変更(info_change)のうち銀行口座(振込先)は5.3「重要情報閲覧権限(労務管理者以上のみ)」
-- の対象のため、requests_select_managers/requests_update_managers を張り替えて
-- change_field='bank_account' の行は is_labor_manager_plus() のみ閲覧・更新できるようにする。
-- 住所・電話番号は5.3の対象外のため、既存どおり管理施設範囲の管理者が閲覧・更新できる。

drop policy if exists requests_select_managers on requests;
create policy requests_select_managers on requests
  for select using (
    exists (
      select 1 from employees e
      where e.id = requests.employee_id and manages_office(e.home_office_id)
    )
    and not (
      requests.request_type = 'info_change'
      and requests.details ->> 'change_field' = 'bank_account'
      and not is_labor_manager_plus()
    )
  );

drop policy if exists requests_update_managers on requests;
create policy requests_update_managers on requests
  for update using (
    exists (
      select 1 from employees e
      where e.id = requests.employee_id and manages_office(e.home_office_id)
    )
    and not (
      requests.request_type = 'info_change'
      and requests.details ->> 'change_field' = 'bank_account'
      and not is_labor_manager_plus()
    )
  )
  with check (
    exists (
      select 1 from employees e
      where e.id = requests.employee_id and manages_office(e.home_office_id)
    )
    and not (
      requests.request_type = 'info_change'
      and requests.details ->> 'change_field' = 'bank_account'
      and not is_labor_manager_plus()
    )
  );

-- 情報変更申請の承認: 住所・電話番号は employees + employee_contacts(履歴)へ、
-- 振込先口座は bank_transfer_accounts(履歴, is_current切替)へ反映する。
-- SECURITY DEFINERのため呼び出し元のRLSに依存せず、関数内で権限を明示チェックする
-- (approve_paid_leave_requestと同じ方針)。
create or replace function approve_info_change_request(
  p_request_id uuid,
  p_decision_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request requests%rowtype;
  v_field text;
  v_address text;
  v_phone text;
  v_email text;
begin
  select * into v_request from requests where id = p_request_id for update;

  if v_request.id is null then
    raise exception 'request not found';
  end if;
  if v_request.request_type <> 'info_change' then
    raise exception 'not an info change request';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'request is not pending';
  end if;

  v_field := v_request.details ->> 'change_field';

  if v_field = 'bank_account' then
    if not is_labor_manager_plus() then
      raise exception 'bank account changes require labor manager or above';
    end if;

    update bank_transfer_accounts
      set is_current = false, effective_end_date = v_request.target_date - 1
      where employee_id = v_request.employee_id and is_current = true;

    insert into bank_transfer_accounts (
      employee_id, bank_name, branch_name, account_type, account_number,
      account_holder_name_kana, effective_start_date, is_current, created_by
    ) values (
      v_request.employee_id,
      v_request.details ->> 'bank_name',
      v_request.details ->> 'branch_name',
      v_request.details ->> 'account_type',
      v_request.details ->> 'account_number',
      v_request.details ->> 'account_holder_name_kana',
      v_request.target_date, true, my_employee_id()
    );
  elsif v_field in ('address', 'phone') then
    if not exists (
      select 1 from employees e
      where e.id = v_request.employee_id and manages_office(e.home_office_id)
    ) then
      raise exception 'not authorized to approve this request';
    end if;

    select address, phone, email into v_address, v_phone, v_email
    from employees where id = v_request.employee_id;

    if v_field = 'address' then
      v_address := v_request.details ->> 'new_value';
      update employees set address = v_address where id = v_request.employee_id;
    else
      v_phone := v_request.details ->> 'new_value';
      update employees set phone = v_phone where id = v_request.employee_id;
    end if;

    insert into employee_contacts (
      employee_id, address, phone, email, effective_start_date, changed_by
    ) values (
      v_request.employee_id, v_address, v_phone, v_email,
      v_request.target_date, my_employee_id()
    );
  else
    raise exception 'unknown change_field: %', v_field;
  end if;

  update requests set
    status = 'approved',
    approver_id = my_employee_id(),
    approved_at = now(),
    decision_reason = p_decision_reason
  where id = p_request_id;
end;
$$;
