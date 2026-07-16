-- 保育業務 Phase1: 施設ごとの運用設定
-- 「機能のON/OFF」(feature_flags)とは別レイヤーとして、機能内の運用設定を持つ。
-- クラス活動/連絡帳の入力・申請締切時刻、個人日誌の承認要否・閲覧範囲を扱う。

create table childcare_office_settings (
  office_id uuid primary key references offices(id),
  class_activity_deadline_time time not null default '15:00',
  contact_approval_deadline_time time not null default '17:00',
  personal_journal_requires_approval boolean not null default false,
  personal_journal_visibility_scope text not null default 'same_office_staff_and_admin'
    check (personal_journal_visibility_scope in ('same_office_staff_and_admin', 'admin_only')),
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now()
);
create trigger trg_childcare_office_settings_updated_at before update on childcare_office_settings
  for each row execute function set_updated_at();

alter table childcare_office_settings enable row level security;
create policy childcare_office_settings_select_scoped on childcare_office_settings
  for select using (has_childcare_office_access(office_id));
create policy childcare_office_settings_write_managers on childcare_office_settings
  for all using (manages_childcare(office_id)) with check (manages_childcare(office_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'childcare_office_settings'
  );
end $$;
