-- 207: 連絡帳の担当者変更RPC(俊指示 2026-08-14)。
-- 「担当: ○○」の横の「変更」ボタンから、施設の在籍職員へ担当を渡す。
-- 認可=施設アクセスを持つ職員(has_childcare_office_access)。下書き/差し戻し中のみ変更可。
-- 変更先は当該施設に在籍中(employee_office_assignments 期間内)の職員に限定。
-- 監査は child_daily_contacts の既存 trg_audit が記録する。冪等: create or replace のみ。

create or replace function set_child_daily_contact_assignee(p_contact_id uuid, p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_contact child_daily_contacts%rowtype;
  v_office uuid;
begin
  select * into v_contact from child_daily_contacts where id = p_contact_id for update;
  if v_contact.id is null then
    raise exception 'contact not found';
  end if;
  select office_id into v_office from children where id = v_contact.child_id;
  if not has_childcare_office_access(v_office) then
    raise exception 'not authorized';
  end if;
  if v_contact.status not in ('draft', 'rejected') then
    raise exception 'contact is % and assignee cannot be changed', v_contact.status;
  end if;
  if not exists (
    select 1 from employee_office_assignments eoa
    where eoa.employee_id = p_employee_id
      and eoa.office_id = v_office
      and eoa.start_date <= current_date
      and (eoa.end_date is null or eoa.end_date >= current_date)
  ) then
    raise exception 'employee is not assigned to this office';
  end if;

  update child_daily_contacts set assignee_employee_id = p_employee_id where id = p_contact_id;
end;
$$;

grant execute on function set_child_daily_contact_assignee(uuid, uuid) to anon, authenticated, service_role;
