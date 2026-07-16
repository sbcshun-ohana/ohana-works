-- 保育業務 Phase1: AIプロフィール(園・クラス・職員ごとの文体設定)
-- テーブルのみ用意し、生成時に反映するのは園(office)プロフィールのみとする最小実装。
-- class/employeeスコープの行は保存のみ可能とし、生成への反映と閲覧範囲拡張は後続フェーズで対応する。

create table ai_style_profiles (
  id uuid primary key default gen_random_uuid(),
  scope_type text not null check (scope_type in ('office', 'class', 'employee')),
  scope_id uuid not null,
  tone_settings jsonb not null default '{}',
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (scope_type, scope_id)
);
create trigger trg_ai_style_profiles_updated_at before update on ai_style_profiles
  for each row execute function set_updated_at();

alter table ai_style_profiles enable row level security;
-- Phase1ではofficeスコープのみRLSを提供する(class/employeeスコープは後続フェーズで追加)。
create policy ai_style_profiles_select_office_scoped on ai_style_profiles
  for select using (scope_type = 'office' and has_childcare_office_access(scope_id));
create policy ai_style_profiles_write_office_managers on ai_style_profiles
  for all using (scope_type = 'office' and manages_childcare(scope_id))
  with check (scope_type = 'office' and manages_childcare(scope_id));

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'ai_style_profiles'
  );
end $$;
