-- 263: 連絡帳の「担当」と「作成者」を1本化。俊確定2026-08-20。
-- 作成ボタン(ensure)で行を作る際、担当が未指定なら作成者(=ログインユーザー)を担当に入れる。
-- これにより「担当=作成した人」に一本化。担当は従来の変更/自分を担当にするボタンで途中変更可能。
-- created_by 列(262)は監査用に引き続き記録するが、UIでは担当のみ表示する。

create or replace function ensure_child_daily_contact(p_child_id uuid, p_business_date date)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_office_id uuid; v_assignee uuid; v_contact_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then raise exception 'child not found'; end if;
  if not has_childcare_office_access(v_office_id) then raise exception 'not authorized'; end if;

  -- 既定の担当(園児の担当割当)。無ければ作成者本人を担当にする。
  select assigned_employee_id into v_assignee
  from child_contact_assignments
  where child_id = p_child_id and effective_end_date is null limit 1;

  insert into child_daily_contacts (child_id, business_date, assignee_employee_id, created_by)
  values (p_child_id, p_business_date, coalesce(v_assignee, my_employee_id()), my_employee_id())
  on conflict (child_id, business_date) do nothing;

  select id into v_contact_id from child_daily_contacts
  where child_id = p_child_id and business_date = p_business_date;
  return v_contact_id;
end;
$$;
