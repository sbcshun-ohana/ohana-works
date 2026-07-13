-- iPadキオスク打刻機能(9.1/9.3/10章)向けの追加スキーマ

-- 9.3 代理打刻: 管理者コード(職員ごとの個別PIN)保持者を特定するためのテーブル
create table proxy_punch_credentials (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null unique references employees(id),
  code_salt text not null,
  code_hash text not null, -- sha256(code_salt || pin)
  is_active boolean not null default true,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_proxy_punch_credentials_updated_at before update on proxy_punch_credentials
  for each row execute function set_updated_at();

alter table proxy_punch_credentials enable row level security;
create policy proxy_punch_credentials_labor_manager_only on proxy_punch_credentials
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());

-- 代理打刻・「退勤後の再読取→管理者に確認」選択時に発報するアラート種別(22章)
insert into alert_rules (alert_key, name, description, severity, target_role_codes)
values
  ('proxy_punch_used', '代理打刻', 'iPadキオスクで代理打刻(管理者コード入力)が行われた', 'high',
    array['labor_manager', 'director', 'chief', 'office_manager']),
  ('qr_punch_requires_admin_review', '打刻要確認', '退勤後の再読取で「管理者に確認」が選択された', 'normal',
    array['labor_manager', 'director', 'chief', 'office_manager'])
on conflict (alert_key) do nothing;
