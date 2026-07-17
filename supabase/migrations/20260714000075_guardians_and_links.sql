-- 保護者アプリ Phase A: 保護者アカウント本体・園児紐付け
--
-- RLSは本ファイルでは有効化しない。保護者ドメイン専用の判定関数(is_guardian()等)を
-- 20260714000080でまとめて新設したうえで、本ファイルのテーブルにも適用する
-- (Phase0のchildren/childcare_classes(000056)→access_control(000057)と同じ順序の流儀)。

create table guardians (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id),
  name text not null,
  name_kana text,
  phone text,
  email text,
  status text not null default 'active' check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_guardians_updated_at before update on guardians
  for each row execute function set_updated_at();

-- 変更5: 「代表保護者」ではなく guardian_child_links.role で primary/additional を表現する。
-- 主たる保護者(primary)は最大2名(ひとり親等は1名可)。上限チェックはRPC側で行う
-- (DB制約では表現しづらいため。他の「上限N件」系ルールと同じ運用)。
create table guardian_child_links (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references guardians(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  role text not null check (role in ('primary', 'additional')),
  created_at timestamptz not null default now(),
  unique (guardian_id, child_id)
);
create index idx_guardian_child_links_child on guardian_child_links(child_id);
create index idx_guardian_child_links_guardian on guardian_child_links(guardian_id);

do $$
declare
  t text;
  audited_tables text[] := array['guardians', 'guardian_child_links'];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;
