-- 15章/28.4 各種申請(第1弾: 有給休暇申請) 管理者承認導線の追加
--
-- requests/leave_grants/leave_usages は20260710160004で定義済み。
-- RLSは本人のselect/insertのみ(20260710160006)のため、管理者(施設管理範囲を持つ
-- ロール)による閲覧・承認/却下を可能にするポリシーとRPCを追加する。

-- 管理者は自身の管理施設に所属する職員の申請を閲覧できる。
create policy requests_select_managers on requests
  for select using (
    exists (
      select 1 from employees e
      where e.id = requests.employee_id and manages_office(e.home_office_id)
    )
  );

-- 管理者は自身の管理施設に所属する職員の申請ステータスを更新できる(承認/却下)。
-- 有給の承認は leave_usages への記録を伴うため approve_paid_leave_request() 経由とし、
-- 却下はこのポリシー経由で requests を直接UPDATEする。
create policy requests_update_managers on requests
  for update using (
    exists (
      select 1 from employees e
      where e.id = requests.employee_id and manages_office(e.home_office_id)
    )
  )
  with check (
    exists (
      select 1 from employees e
      where e.id = requests.employee_id and manages_office(e.home_office_id)
    )
  );

-- 管理者は承認画面で対象職員の有給残数を参照できる。
create policy leave_grants_select_managers on leave_grants
  for select using (
    exists (
      select 1 from employees e
      where e.id = leave_grants.employee_id and manages_office(e.home_office_id)
    )
  );

create policy leave_usages_select_managers on leave_usages
  for select using (
    exists (
      select 1 from employees e
      where e.id = leave_usages.employee_id and manages_office(e.home_office_id)
    )
  );

-- 有給休暇申請の承認: leave_usages への記録とrequestsのステータス更新を1関数内で行う。
-- SECURITY DEFINERのため呼び出し元のRLSに依存せず、関数内でmanages_office()により
-- 承認権限を明示チェックする(is_notice_recipient/is_notice_creatorと同じ方針)。
create or replace function approve_paid_leave_request(
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
  v_usage_unit text;
  v_hours numeric;
  v_days_used numeric(4,2) := 0;
  v_hours_used numeric(4,2) := 0;
begin
  select * into v_request from requests where id = p_request_id for update;

  if v_request.id is null then
    raise exception 'request not found';
  end if;
  if v_request.request_type <> 'paid_leave' then
    raise exception 'not a paid leave request';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'request is not pending';
  end if;
  if not exists (
    select 1 from employees e
    where e.id = v_request.employee_id and manages_office(e.home_office_id)
  ) then
    raise exception 'not authorized to approve this request';
  end if;

  v_usage_unit := v_request.details ->> 'usage_unit';
  v_hours := coalesce((v_request.details ->> 'hours')::numeric, 0);

  if v_usage_unit = 'day' then
    v_days_used := 1;
  elsif v_usage_unit = 'half_day' then
    v_days_used := 0.5;
  elsif v_usage_unit = 'hour' then
    v_hours_used := v_hours;
  else
    raise exception 'unknown usage_unit: %', v_usage_unit;
  end if;

  insert into leave_usages (
    employee_id, request_id, target_date, usage_unit, days_used, hours_used
  ) values (
    v_request.employee_id, v_request.id, v_request.target_date,
    v_usage_unit::leave_usage_unit, v_days_used, v_hours_used
  );

  update requests set
    status = 'approved',
    approver_id = my_employee_id(),
    approved_at = now(),
    decision_reason = p_decision_reason
  where id = p_request_id;
end;
$$;
