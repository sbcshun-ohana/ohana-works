-- 保護者アプリ Phase A: 保護者招待
-- 初回招待(園発行)は職員が、2人目以降の主たる保護者招待・追加保護者招待は
-- 既存の主たる保護者が行える(変更5)。招待元はどちらか一方のみ。

create table guardian_invitations (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  role text not null check (role in ('primary', 'additional')),
  invited_by_employee_id uuid references employees(id),
  invited_by_guardian_id uuid references guardians(id),
  token_hash text not null unique,
  expires_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'expired', 'revoked')),
  accepted_by_guardian_id uuid references guardians(id),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  check (
    (invited_by_employee_id is not null and invited_by_guardian_id is null)
    or (invited_by_employee_id is null and invited_by_guardian_id is not null)
  )
);
create index idx_guardian_invitations_child on guardian_invitations(child_id);

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'guardian_invitations'
  );
end $$;
