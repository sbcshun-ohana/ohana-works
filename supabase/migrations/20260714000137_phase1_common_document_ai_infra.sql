-- 追加機能(個別目標シート・架け橋カリキュラム・支援保育事業) Phase 1: 共通基盤(薄く)。
-- 参照: docs/Ohana_Works_追加機能_実装指示書_v1_2026-07-28.md §5 Phase 1, D3。
-- 共有するのはテンプレート版管理・AI実行履歴・機能フラグの3点のみ。承認フロー・
-- 各機能固有のテーブルは機能別マイグレーション(Phase 2以降)で個別に作る。

-- ============================================================
-- document_templates: テンプレート版管理(原案§3.5の項目をそのまま反映)
-- ============================================================
create table document_templates (
  id uuid primary key default gen_random_uuid(),
  template_key text not null,
  document_type text not null,
  jurisdiction text not null default 'internal',
  fiscal_year int,
  term text,
  version int not null default 1,
  effective_from date not null,
  effective_to date,
  source_file_name text,
  source_file_hash text,
  mapping_definition jsonb not null default '{}',
  required_field_definition jsonb not null default '{}',
  status text not null default 'draft'
    check (status in ('draft', 'active', 'superseded', 'archived')),
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (template_key, version)
);
create trigger trg_document_templates_updated_at before update on document_templates
  for each row execute function set_updated_at();

alter table document_templates enable row level security;
-- テンプレート自体は機微情報ではないため、職員なら誰でも参照可。書き込みはsystem_adminのみ。
create policy document_templates_select_staff on document_templates
  for select using (my_employee_id() is not null);
create policy document_templates_write_system_admin on document_templates
  for all using (is_system_admin()) with check (is_system_admin());

-- ============================================================
-- ai_runs: AI実行履歴(D5)。document_type/document_idは機能ごとのテーブルへの
-- ポリモーフィックな参照のためFK制約は張らない。
-- ============================================================
create table ai_runs (
  id uuid primary key default gen_random_uuid(),
  document_type text not null,
  document_id uuid not null,
  target_field text not null,
  input_data jsonb not null,
  provider text not null default 'anthropic',
  model text not null,
  prompt_version text not null,
  output_text text,
  executed_by uuid references employees(id),
  executed_at timestamptz not null default now(),
  decision text check (decision in ('adopted', 'edited', 'regenerated', 'discarded')),
  created_at timestamptz not null default now()
);
create index idx_ai_runs_document on ai_runs(document_type, document_id);

-- ============================================================
-- ai_run_evidence_links: AI実行の根拠記録リンク
-- ============================================================
create table ai_run_evidence_links (
  id uuid primary key default gen_random_uuid(),
  ai_run_id uuid not null references ai_runs(id) on delete cascade,
  evidence_table text not null,
  evidence_id uuid not null,
  created_at timestamptz not null default now()
);
create index idx_ai_run_evidence_links_run on ai_run_evidence_links(ai_run_id);

-- ai_runs / ai_run_evidence_links は document_type によってアクセス可否が機能ごとに
-- 異なるため、テーブル単体の汎用RLSは書かない(deny-all)。各機能のセキュリティ定義RPC
-- 経由のみでアクセスさせる(fetch_my_children_office_names等と同じ「必要最小限だけ
-- 返す専用RPC」方針)。RPCはPhase 2以降、機能ごとに追加する。
alter table ai_runs enable row level security;
alter table ai_run_evidence_links enable row level security;

-- 監査ログ(既存のlog_event_changeトリガーを適用)
do $$
declare
  t text;
  audited_tables text[] := array['document_templates', 'ai_runs', 'ai_run_evidence_links'];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;

-- ============================================================
-- 機能フラグ3キー追加(施設単位のfeature_flag_office_overridesをそのまま使う。
-- guardian_appのようなマスタースイッチ配下には置かない)
-- ============================================================
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('employee_goal_sheet_enabled', '個別目標シート', '職員向け個別目標シート機能の有効化', false),
  ('bridge_curriculum_enabled', '架け橋カリキュラム', '5歳児→小学校接続カリキュラム機能の有効化', false),
  ('support_childcare_program_enabled', '支援保育事業', '支援保育事業(様式1・2等)機能の有効化', false);
