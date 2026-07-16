-- 保育業務 Phase0: 機能フラグ基盤
-- 施設ごと×機能ごとのON/OFF、試験運用対象の先行公開(職員単位オーバーライド)を扱う。
-- 「機能のON/OFF」と「機能内の運用設定」は別レイヤーとして扱い、後者は各機能側の
-- テーブル(例: childcare_office_settings)に持たせる。
-- 有効化するまで既存の職員業務(勤怠・給与・申請・お知らせ)には一切影響を与えない。

create table feature_flags (
  feature_key text primary key,
  name text not null,
  description text,
  default_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_feature_flags_updated_at before update on feature_flags
  for each row execute function set_updated_at();

-- 施設ごとのON/OFF。行が無い施設はfeature_flags.default_enabledに従う。
create table feature_flag_office_overrides (
  id uuid primary key default gen_random_uuid(),
  feature_key text not null references feature_flags(feature_key) on delete cascade,
  office_id uuid not null references offices(id),
  enabled boolean not null,
  note text,
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now(),
  unique (feature_key, office_id)
);

-- 試験運用対象の職員個別オーバーライド(施設単位の設定より優先)。
create table feature_flag_employee_overrides (
  id uuid primary key default gen_random_uuid(),
  feature_key text not null references feature_flags(feature_key) on delete cascade,
  employee_id uuid not null references employees(id) on delete cascade,
  enabled boolean not null,
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now(),
  unique (feature_key, employee_id)
);

-- システム最高管理者判定。既存employee_roles/rolesを流用し、機能フラグ専用の
-- 新ロール・新enumは追加しない。
create or replace function is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from employee_roles er
    join roles r on r.id = er.role_id
    where er.employee_id = my_employee_id()
      and r.code = 'system_admin'
  );
$$;

alter table feature_flags enable row level security;
create policy feature_flags_select_authenticated on feature_flags
  for select using (my_employee_id() is not null);
create policy feature_flags_write_system_admin on feature_flags
  for all using (is_system_admin()) with check (is_system_admin());

alter table feature_flag_office_overrides enable row level security;
create policy feature_flag_office_overrides_select_authenticated on feature_flag_office_overrides
  for select using (my_employee_id() is not null);
create policy feature_flag_office_overrides_write_system_admin on feature_flag_office_overrides
  for all using (is_system_admin()) with check (is_system_admin());

alter table feature_flag_employee_overrides enable row level security;
create policy feature_flag_employee_overrides_select_self_or_admin on feature_flag_employee_overrides
  for select using (employee_id = my_employee_id() or is_system_admin());
create policy feature_flag_employee_overrides_write_system_admin on feature_flag_employee_overrides
  for all using (is_system_admin()) with check (is_system_admin());

-- 保育業務メニュー全体の有効化フラグ。既定OFF。
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('childcare_operations', '保育業務', '保育業務メニュー(園児管理・連絡帳等)全体の有効化フラグ', false);
