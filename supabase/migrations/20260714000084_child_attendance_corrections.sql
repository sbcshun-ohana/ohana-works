-- 保護者アプリ Phase A: 登降園記録の修正履歴(理由必須)
-- 延長料の再計算はPhase Dまでは行わず記録のみとする(指示書§5.3)。

create table child_attendance_corrections (
  id uuid primary key default gen_random_uuid(),
  attendance_event_id uuid not null references child_attendance_events(id) on delete cascade,
  corrected_by uuid not null references employees(id),
  before_values jsonb not null,
  after_values jsonb not null,
  reason text not null,
  created_at timestamptz not null default now()
);
create index idx_child_attendance_corrections_event on child_attendance_corrections(attendance_event_id);

alter table child_attendance_corrections enable row level security;
create policy child_attendance_corrections_select on child_attendance_corrections
  for select using (
    exists (
      select 1 from child_attendance_events cae
      where cae.id = child_attendance_corrections.attendance_event_id
        and staff_has_guardian_data_access(cae.child_id)
    )
  );
create policy child_attendance_corrections_write on child_attendance_corrections
  for all using (
    exists (
      select 1 from child_attendance_events cae
      where cae.id = child_attendance_corrections.attendance_event_id
        and staff_manages_guardian_data(cae.child_id)
    )
  ) with check (
    exists (
      select 1 from child_attendance_events cae
      where cae.id = child_attendance_corrections.attendance_event_id
        and staff_manages_guardian_data(cae.child_id)
    )
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'child_attendance_corrections'
  );
end $$;
