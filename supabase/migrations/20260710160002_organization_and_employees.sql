-- 組織・職員系(設計書28.1)

-- 4.2 口座(給与支払元の会社口座)
-- 口座の詳細(銀行名・口座番号等)は本設計書に記載がないため、
-- 名称のみ初期投入し、詳細は管理者Webのマスタ画面で別途入力する想定。
create table bank_accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null, -- 例: オハナ口座 / マハロ口座 / ステーション口座 / ハレレア口座 / 本部口座
  bank_name text,
  branch_name text,
  account_type text check (account_type in ('普通', '当座')),
  account_number text,
  account_holder_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_bank_accounts_updated_at before update on bank_accounts
  for each row execute function set_updated_at();

insert into bank_accounts (name) values
  ('オハナ口座'), ('マハロ口座'), ('ステーション口座'), ('ハレレア口座'), ('本部口座');

-- 4.3 施設マスタ(削除せず履歴管理)
create table offices (
  id uuid primary key default gen_random_uuid(),
  office_code text not null unique,
  name text not null,
  address text,
  start_date date not null,
  end_date date,
  status office_status not null default '稼働中',
  payroll_bank_account_id uuid references bank_accounts(id),
  pims_identifier text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_offices_updated_at before update on offices
  for each row execute function set_updated_at();

-- 4.1/4.2 施設マスタ初期投入(稼働開始日は暫定値。管理者Webで正式値に更新すること)
insert into offices (office_code, name, start_date, payroll_bank_account_id)
select v.office_code, v.name, date '2020-01-01', ba.id
from (values
  ('O', '大和オハナ保育園', 'オハナ口座'),
  ('M', 'BABY MAHALO', 'マハロ口座'),
  ('S', 'Mahalo Station', 'ステーション口座'),
  ('H', 'Halelea', 'ハレレア口座')
) as v(office_code, name, bank_account_name)
join bank_accounts ba on ba.name = v.bank_account_name;

-- 5.1/5.2 権限ロール
create table roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

insert into roles (code, name, sort_order) values
  ('system_admin', 'システム最高管理者', 1),
  ('labor_manager', '労務管理者', 2),
  ('director', '園長', 3),
  ('chief', '主任', 4),
  ('office_manager', '園管理者', 5),
  ('viewer', '閲覧者', 6),
  ('staff', '一般職員', 7);

-- 機能ごとに 閲覧/作成/編集/削除/承認/確定/出力 を設定
create table role_permissions (
  id uuid primary key default gen_random_uuid(),
  role_id uuid not null references roles(id) on delete cascade,
  feature_key text not null,
  can_view boolean not null default false,
  can_create boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  can_approve boolean not null default false,
  can_confirm boolean not null default false,
  can_export boolean not null default false,
  unique (role_id, feature_key)
);

-- 20.1 マスタ設定(職種・役職・雇用形態はハードコードせずマスタ化)
create table job_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null default 0,
  is_active boolean not null default true
);

create table positions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null default 0,
  is_active boolean not null default true
);

create table employment_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique, -- 例: 正社員 / 契約社員 / パート / アルバイト
  sort_order int not null default 0,
  is_active boolean not null default true
);

-- 6.1 職員マスタ基本項目
create table employees (
  id uuid primary key default gen_random_uuid(),
  employee_number text not null unique, -- 永久番号・再利用禁止(アプリ層で欠番管理)
  auth_user_id uuid unique references auth.users(id),
  name text not null,
  name_kana text,
  birth_date date,
  address text,
  phone text,
  email text,
  hire_date date not null,
  resignation_date date,
  home_office_id uuid not null references offices(id), -- 基本所属
  job_type_id uuid references job_types(id),
  position_id uuid references positions(id),
  employment_type_id uuid not null references employment_types(id),
  full_time_flag boolean not null default true, -- 常勤=true / 非常勤=false
  salary_type salary_type not null,
  work_time_system work_time_system_type not null default '通常',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_employees_updated_at before update on employees
  for each row execute function set_updated_at();
create index idx_employees_home_office on employees(home_office_id);

comment on column employees.work_time_system is
  '6.2: 変形労働時間制対象の判定は employment_type=正社員 かつ salary_type=月給 かつ work_time_system=1ヶ月単位変形労働時間制 の3条件で行う。名称だけで判定しない。';

-- 兼務園を含む所属履歴(6.3, primary/concurrent)
create table employee_office_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  office_id uuid not null references offices(id),
  assignment_type text not null check (assignment_type in ('primary', 'concurrent')),
  start_date date not null,
  end_date date,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_employee_office_assignments_employee on employee_office_assignments(employee_id);

-- 住所・電話・メールの変更履歴(6.3/6.4: 本人申請→管理者承認で反映)
create table employee_contacts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  address text,
  phone text,
  email text,
  effective_start_date date not null,
  effective_end_date date,
  changed_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_employee_contacts_employee on employee_contacts(employee_id);

create table emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  name text not null,
  relationship text,
  phone text not null,
  priority int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_emergency_contacts_updated_at before update on emergency_contacts
  for each row execute function set_updated_at();

-- 役職・職種・雇用形態・常勤区分・給与区分の変更履歴(6.3の残り項目を汎用管理)
create table employee_attribute_histories (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  attribute_name text not null, -- 例: position / job_type / employment_type / full_time_flag / salary_type / work_time_system
  old_value text,
  new_value text,
  effective_date date not null,
  changed_by uuid references employees(id),
  reason text,
  created_at timestamptz not null default now()
);
create index idx_employee_attribute_histories_employee on employee_attribute_histories(employee_id);

-- ロール付与履歴(施設スコープ対応: 園長・主任・園管理者等は管理施設範囲を持つ)
create table employee_roles (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  role_id uuid not null references roles(id),
  office_id uuid references offices(id), -- null=全施設対象(システム最高管理者・労務管理者等)
  created_at timestamptz not null default now(),
  unique (employee_id, role_id, office_id)
);

create table employee_role_histories (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  role_id uuid not null references roles(id),
  office_id uuid references offices(id),
  action text not null check (action in ('assigned', 'revoked')),
  changed_by uuid references employees(id),
  reason text,
  created_at timestamptz not null default now()
);

-- 6.6 税区分・扶養情報
create table dependents (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  name text not null,
  name_kana text,
  relationship text not null,
  birth_date date,
  cohabitation_status text check (cohabitation_status in ('同居', '別居')),
  disability_category text, -- 障害者/特別障害者等の該当区分
  effective_start_date date not null,
  effective_end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_dependents_updated_at before update on dependents
  for each row execute function set_updated_at();
create index idx_dependents_employee on dependents(employee_id);

create table tax_withholding_statuses (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  submitted_flag boolean not null, -- 扶養控除等申告書提出有無
  tax_column text not null check (tax_column in ('甲欄', '乙欄')),
  dependent_count int not null default 0, -- 源泉控除対象扶養親族の数
  special_category text, -- 障害者・寡婦・ひとり親等
  effective_start_year_month date not null, -- 適用開始年月(日=01で保存)
  effective_end_year_month date,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_tax_withholding_statuses_employee on tax_withholding_statuses(employee_id);

-- 6.7 標準報酬月額
create table standard_monthly_remunerations (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  health_insurance_amount integer not null,
  health_insurance_grade int not null,
  pension_amount integer not null,
  pension_grade int not null,
  effective_year_month date not null,
  revision_reason text not null check (revision_reason in ('資格取得時決定', '定時決定', '随時改定')),
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_standard_monthly_remunerations_employee on standard_monthly_remunerations(employee_id);

-- 6.5 社会保険・雇用保険加入状況(介護保険は生年月日から自動判定するため対象外)
create table insurance_enrollments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  insurance_type text not null check (insurance_type in ('健康保険', '厚生年金', '雇用保険')),
  enrolled boolean not null default true,
  acquisition_date date,
  loss_date date,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_insurance_enrollments_employee on insurance_enrollments(employee_id);

-- マイナンバー(専用テーブル分離)
-- 暗号化は Supabase Vault / pgsodium を用いてアプリ/Edge Function層で実施し、
-- 本テーブルには暗号文のみを格納する。閲覧は労務管理者以上・閲覧ログ必須(21章)。
create table my_numbers (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null unique references employees(id) on delete cascade,
  encrypted_number bytea not null,
  masked_number text not null, -- 下4桁表示用(既定マスク表示)
  updated_by uuid references employees(id),
  updated_at timestamptz not null default now()
);

-- 職員の振込先口座(6.3: 履歴管理対象)
create table bank_transfer_accounts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  bank_name text not null,
  branch_name text not null,
  account_type text not null check (account_type in ('普通', '当座')),
  account_number text not null,
  account_holder_name_kana text not null,
  effective_start_date date not null,
  effective_end_date date,
  is_current boolean not null default true,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_bank_transfer_accounts_employee on bank_transfer_accounts(employee_id);

-- 6.8 借上宿舎制度
-- 制度マスタ(補助上限額など)。ハードコード禁止のため必ずこのテーブルから参照する。
create table company_housing_program_settings (
  id uuid primary key default gen_random_uuid(),
  subsidy_cap_amount integer not null,
  effective_start_date date not null,
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
insert into company_housing_program_settings (subsidy_cap_amount, effective_start_date, note)
  values (69000, '2026-07-01', '初期値(制度マスタで変更可能)');

create table company_housing_settings (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  usage_flag boolean not null default true,
  start_date date not null,
  end_date date,
  monthly_rent integer not null,
  target_office_id uuid references offices(id),
  property_name text,
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_company_housing_settings_updated_at before update on company_housing_settings
  for each row execute function set_updated_at();
create index idx_company_housing_settings_employee on company_housing_settings(employee_id);

-- 16.9: 家賃からの完全自動計算・自動確定は禁止。reference_amount は参考表示専用、
-- deduction_amount が労務管理者手入力による正式な給与控除額。
create table company_housing_deductions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  target_month date not null, -- 対象給与月(日=01で保存)
  reference_amount integer, -- 参考本人負担額(家賃-上限、自動表示専用)
  deduction_amount integer not null, -- 正式控除額(手入力)
  input_by uuid not null references employees(id),
  input_at timestamptz not null default now(),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, target_month)
);
create trigger trg_company_housing_deductions_updated_at before update on company_housing_deductions
  for each row execute function set_updated_at();
