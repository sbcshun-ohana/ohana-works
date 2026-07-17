-- 保護者アプリ Phase A: プッシュ通知(FCM統一構成)
-- APNsキーはFirebaseコンソール側に登録済みのため、Edge FunctionはFCM HTTP v1のみを呼ぶ。
--
-- 既存notificationsテーブル(20260710160005で定義済み)は職員(target_employee_id)のみを
-- 想定していたため、保護者宛て(target_guardian_id)を送れるよう列を追加する
-- (既存テーブルの拡張。既存の職員向け通知の挙動・列には影響しない)。

create table push_device_tokens (
  id uuid primary key default gen_random_uuid(),
  guardian_id uuid references guardians(id) on delete cascade,
  employee_id uuid references employees(id) on delete cascade,
  fcm_token text not null unique,
  platform text not null check (platform in ('ios', 'android')),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (
    (guardian_id is not null and employee_id is null)
    or (guardian_id is null and employee_id is not null)
  )
);
create index idx_push_device_tokens_guardian on push_device_tokens(guardian_id);
create index idx_push_device_tokens_employee on push_device_tokens(employee_id);

alter table push_device_tokens enable row level security;
create policy push_device_tokens_self on push_device_tokens
  for all using (
    guardian_id = my_guardian_id() or employee_id = my_employee_id()
  ) with check (
    guardian_id = my_guardian_id() or employee_id = my_employee_id()
  );

do $$
begin
  execute format(
    'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
    'push_device_tokens'
  );
end $$;

alter table notifications add column target_guardian_id uuid references guardians(id);

create policy notifications_select_self_guardian on notifications
  for select using (target_guardian_id = my_guardian_id());
