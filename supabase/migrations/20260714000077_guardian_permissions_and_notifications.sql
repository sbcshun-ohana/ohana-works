-- 保護者アプリ Phase A: 追加保護者への権限制限・通知設定
--
-- guardian_permissions: 行が無い場合は許可(allowed=true)とみなす「太いデフォルト・
-- 細い例外」方式。主たる保護者は原則すべて許可、追加保護者を制限したい場合のみ
-- allowed=falseの行を明示的に登録する。
-- 保護者招待の可否(guardian_child_links.role='primary'か)はこの権限テーブルではなく
-- ロールで判定するため、permission_keyには含めない(create_guardian_invitation_by_guardian参照)。

create table guardian_permissions (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references guardians(id) on delete cascade,
  child_id uuid not null references children(id) on delete cascade,
  permission_key text not null check (permission_key in (
    'view_daily_report', 'submit_requests', 'manage_emergency_contacts'
  )),
  allowed boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (guardian_id, child_id, permission_key)
);
create trigger trg_guardian_permissions_updated_at before update on guardian_permissions
  for each row execute function set_updated_at();

-- categoryは通知カテゴリのキー(自由文字列。既存notifications.notification_typeと同じ方針)。
-- OFF不可(強制配信)カテゴリの判定・強制送信はEdge Function/RPC側で行う
-- (本テーブルのenabled=falseを無視して送る)。
create table guardian_notification_settings (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid not null references guardians(id) on delete cascade,
  category text not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (guardian_id, category)
);
create trigger trg_guardian_notification_settings_updated_at before update on guardian_notification_settings
  for each row execute function set_updated_at();

do $$
declare
  t text;
  audited_tables text[] := array['guardian_permissions', 'guardian_notification_settings'];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;
