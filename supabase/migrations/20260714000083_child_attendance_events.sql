-- 保護者アプリ Phase A: 登園・降園イベント(変更1)
--
-- 登園制御で家庭連絡帳未提出により受付を拒否した場合も'rejected'として必ず記録する
-- (拒否後にそのまま預かってしまう運用事故を検知できるようにするため)。
-- 例外処理(災害・通信障害等)は管理者権限で処理し、admin_override_by/reasonに記録する。
-- 記録自体はEdge Function(service role)経由のRPCに限定し、クライアントからの直接
-- INSERTは許可しない。

create table child_attendance_events (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  event_type text not null check (event_type in (
    'drop_off', 'pick_up', 'rejected', 'proxy_drop_off', 'proxy_pick_up'
  )),
  occurred_at timestamptz not null default now(),
  device_id uuid references devices(id),
  recorded_by_guardian_id uuid references guardians(id),
  recorded_by_employee_id uuid references employees(id),
  rejection_reason text,
  admin_override_by uuid references employees(id),
  admin_override_reason text,
  created_at timestamptz not null default now()
);
create index idx_child_attendance_events_child on child_attendance_events(child_id, occurred_at);

alter table child_attendance_events enable row level security;
create policy child_attendance_events_select on child_attendance_events
  for select using (
    guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id)
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'child_attendance_events'
  );
end $$;
