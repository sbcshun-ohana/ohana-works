-- 保護者アプリ Phase A: 保護者申請(欠席/遅刻/早退/感染症/送迎者変更)
-- 既存の職員向けrequestsテーブルと同型だが、保護者ドメインの別テーブルとして持つ
-- (RLS3ドメイン分離のため、既存requestsテーブルには一切手を加えない)。

create table parent_requests (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  guardian_id uuid not null references guardians(id),
  request_type text not null check (request_type in (
    'absence', 'tardiness', 'early_leave', 'infectious_disease', 'pickup_person_change'
  )),
  target_date date not null,
  details jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  approved_by uuid references employees(id),
  approved_at timestamptz,
  decision_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_parent_requests_updated_at before update on parent_requests
  for each row execute function set_updated_at();
create index idx_parent_requests_child on parent_requests(child_id);

create table parent_request_revisions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references parent_requests(id) on delete cascade,
  revised_by uuid not null references guardians(id),
  before_values jsonb not null,
  after_values jsonb not null,
  created_at timestamptz not null default now()
);
create index idx_parent_request_revisions_request on parent_request_revisions(request_id);

create table parent_request_messages (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references parent_requests(id) on delete cascade,
  sender_type text not null check (sender_type in ('guardian', 'staff')),
  sender_guardian_id uuid references guardians(id),
  sender_employee_id uuid references employees(id),
  message text not null,
  created_at timestamptz not null default now(),
  check (
    (sender_type = 'guardian' and sender_guardian_id is not null and sender_employee_id is null)
    or (sender_type = 'staff' and sender_employee_id is not null and sender_guardian_id is null)
  )
);
create index idx_parent_request_messages_request on parent_request_messages(request_id);

alter table parent_requests enable row level security;
create policy parent_requests_select on parent_requests
  for select using (guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id));
create policy parent_requests_insert on parent_requests
  for insert with check (guardian_has_child_access(child_id) and guardian_id = my_guardian_id());
create policy parent_requests_update_guardian on parent_requests
  for update using (guardian_id = my_guardian_id() and status = 'pending')
  with check (guardian_id = my_guardian_id() and status = 'pending');
create policy parent_requests_update_managers on parent_requests
  for update using (staff_manages_guardian_data(child_id))
  with check (staff_manages_guardian_data(child_id));

alter table parent_request_revisions enable row level security;
create policy parent_request_revisions_select on parent_request_revisions
  for select using (
    exists (
      select 1 from parent_requests pr
      where pr.id = parent_request_revisions.request_id
        and (guardian_has_child_access(pr.child_id) or staff_has_guardian_data_access(pr.child_id))
    )
  );
create policy parent_request_revisions_insert on parent_request_revisions
  for insert with check (
    exists (
      select 1 from parent_requests pr
      where pr.id = parent_request_revisions.request_id and guardian_has_child_access(pr.child_id)
    )
  );

alter table parent_request_messages enable row level security;
create policy parent_request_messages_select on parent_request_messages
  for select using (
    exists (
      select 1 from parent_requests pr
      where pr.id = parent_request_messages.request_id
        and (guardian_has_child_access(pr.child_id) or staff_has_guardian_data_access(pr.child_id))
    )
  );
create policy parent_request_messages_insert_guardian on parent_request_messages
  for insert with check (
    sender_type = 'guardian' and sender_guardian_id = my_guardian_id()
    and exists (
      select 1 from parent_requests pr
      where pr.id = parent_request_messages.request_id and guardian_has_child_access(pr.child_id)
    )
  );
create policy parent_request_messages_insert_staff on parent_request_messages
  for insert with check (
    sender_type = 'staff' and sender_employee_id = my_employee_id()
    and exists (
      select 1 from parent_requests pr
      where pr.id = parent_request_messages.request_id and staff_has_guardian_data_access(pr.child_id)
    )
  );

do $$
declare
  t text;
  audited_tables text[] := array['parent_requests', 'parent_request_revisions', 'parent_request_messages'];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;
