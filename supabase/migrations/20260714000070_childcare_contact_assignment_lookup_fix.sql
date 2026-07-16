-- 保育業務 Phase1 修正: ensure_child_daily_contact()の担当者解決ロジック
--
-- 不具合: 「現在の担当」をchild_contact_assignments.effective_end_date is nullのみで
-- 判定していたため、未来日付から始まる再割当て(assign_child_contact)を行った直後は、
-- まだ有効期間中の旧担当ではなく、開始前の新担当が「現在の担当」として誤って
-- 解決されてしまう(ダミーデータ検証で発見)。
--
-- 修正: 対象business_dateをeffective_start_date/effective_end_dateの範囲に含む行を
-- 選択するようにする。

create or replace function ensure_child_daily_contact(p_child_id uuid, p_business_date date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
  v_assignee uuid;
  v_contact_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not has_childcare_office_access(v_office_id) then
    raise exception 'not authorized';
  end if;

  select assigned_employee_id into v_assignee
  from child_contact_assignments
  where child_id = p_child_id
    and effective_start_date <= p_business_date
    and (effective_end_date is null or effective_end_date >= p_business_date)
  order by effective_start_date desc
  limit 1;

  insert into child_daily_contacts (child_id, business_date, assignee_employee_id)
  values (p_child_id, p_business_date, v_assignee)
  on conflict (child_id, business_date) do nothing;

  select id into v_contact_id from child_daily_contacts
  where child_id = p_child_id and business_date = p_business_date;

  return v_contact_id;
end;
$$;
