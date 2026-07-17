-- 保護者アプリ Phase A: 園連絡帳の閲覧履歴・重要事項確認
-- 1名閲覧で家庭確認済みとする判定・12時間未閲覧の再通知はRPC/Edge Function側のロジックとする。

create table communication_book_reads (
  id uuid primary key default gen_random_uuid(),
  child_daily_contact_id uuid not null references child_daily_contacts(id) on delete cascade,
  guardian_id uuid not null references guardians(id),
  read_at timestamptz not null default now(),
  unique (child_daily_contact_id, guardian_id)
);

create table communication_book_confirmations (
  id uuid primary key default gen_random_uuid(),
  child_daily_contact_id uuid not null references child_daily_contacts(id) on delete cascade,
  guardian_id uuid not null references guardians(id),
  confirmation_type text not null check (confirmation_type in ('read_ack', 'important_matter_ack')),
  confirmed_at timestamptz not null default now(),
  unique (child_daily_contact_id, guardian_id, confirmation_type)
);

alter table communication_book_reads enable row level security;
create policy communication_book_reads_select on communication_book_reads
  for select using (
    guardian_id = my_guardian_id()
    or exists (
      select 1 from child_daily_contacts cdc
      where cdc.id = communication_book_reads.child_daily_contact_id
        and staff_has_guardian_data_access(cdc.child_id)
    )
  );
create policy communication_book_reads_insert on communication_book_reads
  for insert with check (
    guardian_id = my_guardian_id()
    and exists (
      select 1 from child_daily_contacts cdc
      where cdc.id = communication_book_reads.child_daily_contact_id
        and guardian_has_child_access(cdc.child_id)
    )
  );

alter table communication_book_confirmations enable row level security;
create policy communication_book_confirmations_select on communication_book_confirmations
  for select using (
    guardian_id = my_guardian_id()
    or exists (
      select 1 from child_daily_contacts cdc
      where cdc.id = communication_book_confirmations.child_daily_contact_id
        and staff_has_guardian_data_access(cdc.child_id)
    )
  );
create policy communication_book_confirmations_insert on communication_book_confirmations
  for insert with check (
    guardian_id = my_guardian_id()
    and exists (
      select 1 from child_daily_contacts cdc
      where cdc.id = communication_book_confirmations.child_daily_contact_id
        and guardian_has_child_access(cdc.child_id)
    )
  );

do $$
declare
  t text;
  audited_tables text[] := array['communication_book_reads', 'communication_book_confirmations'];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;
