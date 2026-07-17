-- 保護者アプリ Phase A: 感染症マスタ(国基準・自治体・園独自)
-- 初期データ(国基準の一覧)投入は指示書§7の確認事項のため、本マイグレーションでは
-- テーブル定義のみ行い、実データ投入はユーザー確認後に別途行う。

create table infectious_disease_masters (
  id uuid primary key default gen_random_uuid(),
  office_id uuid references offices(id), -- null=国基準・自治体等の共通マスタ、値あり=園独自
  name text not null,
  category text not null check (category in ('first', 'second', 'third')),
  requires_opinion_letter boolean not null default false,
  requires_return_form boolean not null default false,
  form_template_storage_path text,
  source text not null check (source in ('national', 'municipal', 'office_specific')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_infectious_disease_masters_updated_at before update on infectious_disease_masters
  for each row execute function set_updated_at();

alter table infectious_disease_masters enable row level security;
create policy infectious_disease_masters_select on infectious_disease_masters
  for select using (
    is_guardian()
    or (office_id is not null and has_childcare_office_access(office_id))
    or (office_id is null and my_employee_id() is not null)
  );
create policy infectious_disease_masters_write_office_specific on infectious_disease_masters
  for all using (office_id is not null and manages_childcare(office_id))
  with check (office_id is not null and manages_childcare(office_id));
create policy infectious_disease_masters_write_global on infectious_disease_masters
  for all using (office_id is null and is_system_admin())
  with check (office_id is null and is_system_admin());

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'infectious_disease_masters'
  );
end $$;
