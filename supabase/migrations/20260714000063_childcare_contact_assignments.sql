-- 保育業務 Phase1: 園児別担当者割当
-- 各園児の連絡帳は担当職員1名が作成する(1人の職員が複数園児を担当できる)。
-- 途中変更可能(入力内容は保持)。現在の担当 = effective_end_date is null の行。

create table child_contact_assignments (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  assigned_employee_id uuid not null references employees(id),
  effective_start_date date not null,
  effective_end_date date,
  assigned_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_child_contact_assignments_child on child_contact_assignments(child_id);
create index idx_child_contact_assignments_employee on child_contact_assignments(assigned_employee_id);

alter table child_contact_assignments enable row level security;
create policy child_contact_assignments_select_scoped on child_contact_assignments
  for select using (
    exists (
      select 1 from children c
      where c.id = child_contact_assignments.child_id and has_childcare_office_access(c.office_id)
    )
  );
create policy child_contact_assignments_write_managers on child_contact_assignments
  for all using (
    exists (
      select 1 from children c
      where c.id = child_contact_assignments.child_id and manages_childcare(c.office_id)
    )
  ) with check (
    exists (
      select 1 from children c
      where c.id = child_contact_assignments.child_id and manages_childcare(c.office_id)
    )
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'child_contact_assignments'
  );
end $$;

-- 園児別担当者の設定(複数園児への一括割当はこの関数を園児ごとに呼び出す)。
-- 既存の現在担当行を締め、新しい担当行を追加する(wage_masters等と同じeffective-dated運用)。
create or replace function assign_child_contact(
  p_child_id uuid,
  p_employee_id uuid,
  p_effective_start_date date default current_date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_office_id uuid;
begin
  select office_id into v_office_id from children where id = p_child_id;
  if v_office_id is null then
    raise exception 'child not found';
  end if;
  if not manages_childcare(v_office_id) then
    raise exception 'not authorized';
  end if;

  update child_contact_assignments
  set effective_end_date = p_effective_start_date - 1
  where child_id = p_child_id and effective_end_date is null;

  insert into child_contact_assignments (child_id, assigned_employee_id, effective_start_date, assigned_by)
  values (p_child_id, p_employee_id, p_effective_start_date, my_employee_id());
end;
$$;
