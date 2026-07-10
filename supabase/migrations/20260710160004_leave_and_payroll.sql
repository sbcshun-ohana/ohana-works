-- 申請・有給系(設計書28.4) / 給与系(28.5)

-- 15章/28.4 各種申請(有給/欠勤/遅刻早退/情報変更)を単一テーブルで管理
create table requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  request_type request_type not null,
  target_date date not null,
  target_end_date date,
  details jsonb not null default '{}', -- 種別ごとの詳細(理由・時間数・変更項目等)
  status request_status not null default 'pending',
  approver_id uuid references employees(id),
  approved_at timestamptz,
  decision_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_requests_updated_at before update on requests
  for each row execute function set_updated_at();
create index idx_requests_employee on requests(employee_id);
create index idx_requests_status on requests(status);

comment on column requests.details is
  '有給: usage_unit/hours等。欠勤: 理由/詳細/園への連絡事項/代替対応有無。遅刻早退: 事前/事後区分・時刻。情報変更: 変更項目・新旧値。';

-- 15.1 時間単位年休の1日換算時間(マスタ設定値)
create table leave_day_hour_settings (
  id uuid primary key default gen_random_uuid(),
  hours_per_day numeric(4,2) not null,
  effective_start_date date not null,
  note text,
  created_at timestamptz not null default now()
);
insert into leave_day_hour_settings (hours_per_day, effective_start_date, note)
  values (8.00, '2026-07-01', '初期値(労使協定内容に合わせ変更可能)');

-- 15.1 有給付与(労基法準拠: 8割出勤要件・比例付与)
create table leave_grants (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  granted_days numeric(5,1) not null,
  grant_date date not null,
  expiry_date date not null,
  basis text, -- 法定付与 / 比例付与 等
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_leave_grants_employee on leave_grants(employee_id);

-- 有給使用実績(日+時間の複合管理。承認済みrequestに紐づく)
create table leave_usages (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  request_id uuid not null references requests(id),
  target_date date not null,
  usage_unit leave_usage_unit not null,
  days_used numeric(4,2) not null default 0,
  hours_used numeric(4,2) not null default 0,
  created_at timestamptz not null default now()
);
create index idx_leave_usages_employee on leave_usages(employee_id);

-- 16.2/16.4 給与単価(月給・時給の履歴)
create table wage_masters (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  salary_type salary_type not null,
  monthly_base_salary integer,
  hourly_wage integer,
  effective_start_date date not null,
  effective_end_date date,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_wage_masters_employee on wage_masters(employee_id);

-- 16.4 割増賃金基礎単価の分母(年度別・固定値)
create table average_monthly_working_hours (
  id uuid primary key default gen_random_uuid(),
  fiscal_year int not null unique,
  hours numeric(6,2) not null,
  note text,
  created_at timestamptz not null default now()
);

-- 16.11 手当マスタ共通属性
create table allowance_masters (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  taxable boolean not null default true,
  social_insurance_target boolean not null default true,
  employment_insurance_target boolean not null default true,
  labor_insurance_wage_target boolean not null default true,
  fixed_wage boolean not null default true,
  bonus_treatment boolean not null default false,
  office_allocation_target boolean not null default false,
  overtime_base_target boolean not null default true, -- 割増賃金基礎対象。除外は通勤手当のみ(16.4)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_allowance_masters_updated_at before update on allowance_masters
  for each row execute function set_updated_at();

insert into allowance_masters (name, fixed_wage, overtime_base_target) values
  ('役職手当', true, true),
  ('職務手当', true, true),
  ('資格手当', true, true),
  ('その他手当', true, true),
  ('早番手当', false, true),
  ('調整手当', true, true),
  ('通勤手当', true, false); -- 16.4: 割増賃金基礎から除外するのは通勤手当のみ

create table employee_allowances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  allowance_master_id uuid not null references allowance_masters(id),
  amount integer not null,
  effective_start_date date not null,
  effective_end_date date,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_employee_allowances_employee on employee_allowances(employee_id);

-- 16.10 特殊業務手当の属性設定(マスタで変更可能・固定額実装は禁止)
create table special_duty_allowance_settings (
  id uuid primary key default gen_random_uuid(),
  taxable boolean not null default true,
  social_insurance_target boolean not null default true,
  employment_insurance_target boolean not null default true,
  labor_insurance_wage_target boolean not null default true,
  bonus_treatment boolean not null default false,
  overtime_base_target boolean not null default true,
  fixed_wage boolean not null default false,
  effective_start_date date not null,
  created_at timestamptz not null default now()
);
insert into special_duty_allowance_settings (effective_start_date) values ('2026-07-01');

create table special_duty_allowances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  target_payroll_month date not null, -- 対象給与月(日=01)
  amount integer not null default 0,
  reason_category text check (reason_category in ('処遇改善手当分配', '業務負担加算', '特別業務対応', '役割加算', '臨時補助金分配', 'その他')),
  reason_detail text,
  internal_memo text,
  show_on_payslip boolean not null default true,
  display_text text,
  input_by uuid not null references employees(id),
  confirmed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, target_payroll_month)
);
create trigger trg_special_duty_allowances_updated_at before update on special_duty_allowances
  for each row execute function set_updated_at();

comment on column special_duty_allowances.amount is
  '毎月手入力で確定する変動支給額。前月額の自動継続・自動確定は禁止(33章)。';

-- 16.6 交通費(職員×施設ごとに登録可能。兼務者対応)
create table commute_masters (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  office_id uuid not null references offices(id),
  commute_method text,
  unit_price integer not null,
  calc_type text not null check (calc_type in ('per_day_roundtrip', 'fixed_monthly')),
  taxable_limit integer,
  effective_start_date date not null,
  effective_end_date date,
  created_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_commute_masters_employee_office on commute_masters(employee_id, office_id);

-- 16.7 負担金(単価は施設ごと)
create table burden_fee_masters (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id) unique,
  unit_price integer not null,
  effective_start_date date not null,
  created_at timestamptz not null default now()
);
insert into burden_fee_masters (office_id, unit_price, effective_start_date)
select o.id, v.unit_price, '2026-07-01'
from (values ('O', 300), ('M', 300), ('S', 300), ('H', 250)) as v(office_code, unit_price)
join offices o on o.office_code = v.office_code;

create table burden_fee_records (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  target_month date not null,
  meal_count int not null default 0,
  amount integer not null default 0,
  source text, -- 注文表由来
  created_at timestamptz not null default now(),
  unique (employee_id, target_month)
);

-- 16.8 保険料率・源泉税表・住民税(外部ファイル取込結果を保持)
create table insurance_rate_tables (
  id uuid primary key default gen_random_uuid(),
  insurance_type text not null check (insurance_type in ('健康保険', '介護保険', '厚生年金', '雇用保険')),
  grade int,
  standard_remuneration_amount integer,
  rate numeric(7,5),
  effective_start_year_month date not null,
  effective_end_year_month date,
  created_at timestamptz not null default now()
);

create table withholding_tax_tables (
  id uuid primary key default gen_random_uuid(),
  tax_column text not null check (tax_column in ('甲欄', '乙欄')),
  dependent_count int,
  wage_lower_bound integer not null,
  wage_upper_bound integer,
  tax_amount integer not null,
  effective_start_year_month date not null,
  effective_end_year_month date,
  created_at timestamptz not null default now()
);

create table resident_taxes (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  fiscal_year int not null, -- 6月〜翌5月
  municipality_name text,
  monthly_amounts jsonb not null default '{}', -- {"2026-06": 5000, ...}
  note text,
  created_at timestamptz not null default now(),
  unique (employee_id, fiscal_year)
);

-- 17章 給与確定単位。過去月完全再現のためスナップショットを保持(3章)
create table payroll_runs (
  id uuid primary key default gen_random_uuid(),
  target_month date not null unique, -- 集計期間1日〜末日(日=01で保存)
  status payroll_run_status not null default 'draft',
  snapshot jsonb, -- 入力値・マスタのバージョンスナップショット
  transferred boolean not null default false, -- 振込実行済みフラグ(実行済みは再確定禁止)
  confirmed_by uuid references employees(id),
  confirmed_at timestamptz,
  transferred_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_payroll_runs_updated_at before update on payroll_runs
  for each row execute function set_updated_at();

create table payroll_details (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references payroll_runs(id) on delete cascade,
  employee_id uuid not null references employees(id),
  office_breakdown jsonb not null default '{}', -- 施設別按分内訳
  earnings jsonb not null default '{}', -- 基本給・手当・割増内訳
  deductions jsonb not null default '{}', -- 控除内訳
  net_pay integer not null, -- 差引支給額(円、整数)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (payroll_run_id, employee_id)
);
create trigger trg_payroll_details_updated_at before update on payroll_details
  for each row execute function set_updated_at();

create table payslips (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references payroll_runs(id),
  employee_id uuid not null references employees(id),
  file_path text not null,
  generated_at timestamptz not null default now(),
  delivered_at timestamptz,
  viewed_at timestamptz
);
create index idx_payslips_employee on payslips(employee_id);

create table bank_transfer_files (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references payroll_runs(id),
  file_type text not null check (file_type in ('csv', 'pdf')),
  file_path text not null,
  generated_by uuid references employees(id),
  generated_at timestamptz not null default now()
);
