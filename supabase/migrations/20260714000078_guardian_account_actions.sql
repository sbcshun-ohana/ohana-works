-- 保護者アプリ Phase A: 園による保護者アカウント操作履歴
-- 停止・強制ログアウト等は職員(管理者)のみが行える操作のため、必ず理由と実施者を記録する。
-- 実際のセッション無効化(強制ログアウト)はRLSでは実現できないため、
-- 本テーブルへの記録とあわせてservice role経由のRPC/Edge Functionで
-- Supabase Admin Auth APIを呼び出す(20260714000092以降で実装)。

create table guardian_account_actions (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references guardians(id) on delete cascade,
  action text not null check (action in ('suspended', 'reactivated', 'forced_logout', 'revoked_invitation')),
  performed_by uuid not null references employees(id),
  reason text,
  created_at timestamptz not null default now()
);
create index idx_guardian_account_actions_guardian on guardian_account_actions(guardian_id);

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'guardian_account_actions'
  );
end $$;
