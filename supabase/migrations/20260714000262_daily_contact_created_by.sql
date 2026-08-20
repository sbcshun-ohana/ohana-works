-- 262: 連絡帳の下書きを「作成」ボタン方式へ。俊確定2026-08-20。
-- 現状は園児を選択した時点で ensure_child_daily_contact が走り、即「下書き」化していた。
-- 変更後: 選択だけでは行を作らず(=一覧は未着手のまま)、「作成」ボタンで初めて行を作成し、
-- そのボタンを押したログインユーザーを created_by(作成者)として記録する。
-- クライアント側で「選択時に ensure を呼ぶ」のをやめ、「作成ボタン押下時のみ ensure を呼ぶ」よう変更する。
-- DBとしては (1) created_by 列の追加 と (2) ensure が作成時に created_by を埋める だけ。

-- (1) 作成者カラム(誰が下書きを起こしたか)。既存行は NULL のまま。
alter table child_daily_contacts
  add column if not exists created_by uuid references employees(id);

-- (2) ensure_child_daily_contact: 新規作成時に created_by = my_employee_id() をセット。
--     on conflict do nothing のため、既に行がある場合は created_by を書き換えない(最初の作成者を保持)。
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
  where child_id = p_child_id and effective_end_date is null
  limit 1;

  insert into child_daily_contacts (child_id, business_date, assignee_employee_id, created_by)
  values (p_child_id, p_business_date, v_assignee, my_employee_id())
  on conflict (child_id, business_date) do nothing;

  select id into v_contact_id from child_daily_contacts
  where child_id = p_child_id and business_date = p_business_date;

  return v_contact_id;
end;
$$;
