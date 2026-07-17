-- 保護者アプリ Phase A: 家庭連絡帳(保護者→園)
-- 体温は35.0〜42.0℃・0.1℃刻み(変更4で園側と統一)。15分単位の時刻入力はUI側で制御する
-- (既存の打刻時刻等と同様、DB側では時刻の粒度を制約しない)。
-- 37.5℃以上は警告+欠席申請導線をUI側で表示するが、提出自体はブロックしない。

create table family_daily_reports (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  business_date date not null,
  guardian_id uuid not null references guardians(id),
  temperature numeric(3,1) check (temperature between 35.0 and 42.0),
  temperature_measured_at time,
  symptoms text,
  home_notes text,
  status text not null default 'draft' check (status in ('draft', 'submitted')),
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (child_id, business_date)
);
create trigger trg_family_daily_reports_updated_at before update on family_daily_reports
  for each row execute function set_updated_at();

-- 保護者が編集した際の変更履歴(event_logsはRLS未設定=保護者から見えないため、
-- 保護者自身が閲覧できる変更履歴として別テーブルを持つ)。
create table family_daily_report_revisions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references family_daily_reports(id) on delete cascade,
  revised_by uuid not null references guardians(id),
  before_values jsonb not null,
  after_values jsonb not null,
  created_at timestamptz not null default now()
);
create index idx_family_daily_report_revisions_report on family_daily_report_revisions(report_id);

alter table family_daily_reports enable row level security;
create policy family_daily_reports_select on family_daily_reports
  for select using (
    guardian_has_child_access(child_id) or staff_has_guardian_data_access(child_id)
  );
create policy family_daily_reports_write_guardian on family_daily_reports
  for all using (guardian_has_child_access(child_id)) with check (guardian_has_child_access(child_id));

alter table family_daily_report_revisions enable row level security;
create policy family_daily_report_revisions_select on family_daily_report_revisions
  for select using (
    exists (
      select 1 from family_daily_reports fdr
      where fdr.id = family_daily_report_revisions.report_id
        and (guardian_has_child_access(fdr.child_id) or staff_has_guardian_data_access(fdr.child_id))
    )
  );
create policy family_daily_report_revisions_insert on family_daily_report_revisions
  for insert with check (
    exists (
      select 1 from family_daily_reports fdr
      where fdr.id = family_daily_report_revisions.report_id
        and guardian_has_child_access(fdr.child_id)
    )
  );

do $$
declare
  t text;
  audited_tables text[] := array['family_daily_reports', 'family_daily_report_revisions'];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;
