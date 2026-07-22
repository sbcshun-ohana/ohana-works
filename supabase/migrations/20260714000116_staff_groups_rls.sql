-- グループ連絡: staff_groups / staff_group_members のRLS。
-- notices⇄notice_recipientsで一度踏んだ相互参照recursionバグ(20260714000003)と同じ形を
-- staff_groups⇄staff_group_membersで再現しないよう、直接の相互サブクエリではなく
-- SECURITY DEFINER関数(is_staff_group_member/manages_staff_group)を介して判定する。

create or replace function is_staff_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from staff_group_members
    where group_id = p_group_id
      and employee_id = my_employee_id()
      and removed_at is null
  );
$$;

create or replace function manages_staff_group(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from staff_groups sg
    where sg.id = p_group_id and manages_office(sg.office_id)
  );
$$;

alter table staff_groups enable row level security;

-- 施設管理者(園長・主任・園管理者・system_admin・labor_manager)は自施設のグループを閲覧・作成・編集可能。
-- メンバー本人は自分が所属するグループ(名称・種別)を閲覧できる。
create policy staff_groups_select on staff_groups
  for select using (manages_office(office_id) or is_staff_group_member(id));

create policy staff_groups_write_managers on staff_groups
  for all using (manages_office(office_id)) with check (manages_office(office_id));

alter table staff_group_members enable row level security;

create policy staff_group_members_select on staff_group_members
  for select using (employee_id = my_employee_id() or manages_staff_group(group_id));

create policy staff_group_members_write_managers on staff_group_members
  for all using (manages_staff_group(group_id)) with check (manages_staff_group(group_id));
