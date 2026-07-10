-- 勤怠系・シフト系(設計書28.2 / 28.3)

-- 9.1 端末マスタ
create table devices (
  id uuid primary key default gen_random_uuid(),
  device_code text not null unique,
  office_id uuid not null references offices(id),
  status device_status not null default 'enabled',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_devices_updated_at before update on devices
  for each row execute function set_updated_at();

-- 9.2 ワンタイムQR(サーバー発行・署名付き・single-use消費)
create table qr_tokens (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  token_hash text not null unique, -- 生トークンは保存せずハッシュのみ保持
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null, -- 発行から8時間
  status qr_token_status not null default 'issued',
  used_at timestamptz,
  used_by_device_id uuid references devices(id),
  created_at timestamptz not null default now()
);
create index idx_qr_tokens_employee on qr_tokens(employee_id);
create index idx_qr_tokens_status on qr_tokens(status);

-- 9.4/11.1 実打刻(1分単位)。丸め処理は適用しない不変ログ。
-- 「実打刻データ(time_punches)を丸めて保存・上書きしてはならない」(33章)
create table time_punches (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  device_id uuid references devices(id),
  punch_type punch_type not null,
  punched_at timestamptz not null,
  source punch_source not null,
  office_id uuid not null references offices(id),
  qr_token_id uuid references qr_tokens(id),
  created_at timestamptz not null default now()
);
create index idx_time_punches_employee_date on time_punches(employee_id, punched_at);

comment on table time_punches is
  '実打刻の不変ログ。UPDATEは行わず、修正が必要な場合は daily_attendances 側の承認済み値を管理者が別途登録する。';

-- 14章 施設別勤務時間セグメント(QR由来 or 管理者登録)
create table attendance_segments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  work_date date not null,
  office_id uuid not null references offices(id),
  start_at timestamptz not null,
  end_at timestamptz,
  source text not null check (source in ('punch', 'manual')),
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_attendance_segments_updated_at before update on attendance_segments
  for each row execute function set_updated_at();
create index idx_attendance_segments_employee_date on attendance_segments(employee_id, work_date);

-- 11.1 実測値と給与算定用(承認済み)値を分離管理
create table daily_attendances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  work_date date not null,
  actual_clock_in_at timestamptz,
  actual_clock_out_at timestamptz,
  actual_break_start_at timestamptz,
  actual_break_end_at timestamptz,
  approved_work_start_at timestamptz, -- 給与算定用(丸め後)
  approved_work_end_at timestamptz,   -- 給与算定用(丸め後)。実退勤打刻を超えて設定不可(アプリ層で検証)
  approved_break_minutes int,
  shift_type shift_type_code,
  alert_codes text[] not null default '{}', -- 22章アラートの簡易サマリ(正本は alerts テーブル)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, work_date)
);
create trigger trg_daily_attendances_updated_at before update on daily_attendances
  for each row execute function set_updated_at();
create index idx_daily_attendances_employee_date on daily_attendances(employee_id, work_date);

create table attendance_approvals (
  id uuid primary key default gen_random_uuid(),
  daily_attendance_id uuid not null references daily_attendances(id) on delete cascade,
  approved_by uuid not null references employees(id),
  approved_at timestamptz not null default now(),
  before_data jsonb,
  after_data jsonb,
  reason text
);
create index idx_attendance_approvals_daily on attendance_approvals(daily_attendance_id);

-- 9.3 代理打刻(iPad管理者コード、立会い前提。イベントログ・アラート対象)
create table proxy_punches (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  device_id uuid not null references devices(id),
  punch_type punch_type not null,
  punched_at timestamptz not null,
  proxy_operator_id uuid not null references employees(id), -- 管理者コード保持者
  note text,
  created_at timestamptz not null default now()
);
create index idx_proxy_punches_employee on proxy_punches(employee_id);

-- 20.2/13.2 シフトExcel取込履歴
create table shift_imports (
  id uuid primary key default gen_random_uuid(),
  file_name text not null,
  imported_by uuid not null references employees(id),
  imported_at timestamptz not null default now(),
  target_year_month date not null,
  imported_count int not null default 0,
  unmatched_count int not null default 0,
  error_count int not null default 0,
  warning_count int not null default 0,
  status file_import_status not null default 'awaiting_review',
  detail jsonb,
  created_at timestamptz not null default now()
);

-- 13.2/13.3 週単位固定シフトパターン(Excel取込結果)
create table fixed_shift_patterns (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid references employees(id), -- 職員番号未照合の場合はnull(要確認対象)
  employee_number_raw text not null, -- Excel記載の職員番号(照合キー、氏名のみ照合は禁止)
  weekday int not null check (weekday between 0 and 6), -- 0=日曜
  start_time time not null,
  end_time time not null,
  break_minutes int not null default 0,
  office_id uuid references offices(id),
  employment_type_raw text, -- Excel記載の雇用区分(参考値)
  source_import_id uuid not null references shift_imports(id),
  created_at timestamptz not null default now()
);
create index idx_fixed_shift_patterns_employee on fixed_shift_patterns(employee_id);
create index idx_fixed_shift_patterns_import on fixed_shift_patterns(source_import_id);

-- 13.4/13.5 月間個別シフト
create table shifts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  work_date date not null,
  office_id uuid references offices(id),
  start_time time,
  end_time time,
  break_minutes int not null default 0,
  shift_type shift_type_code not null default 'normal_work',
  status shift_status not null default 'draft',
  confirmed_by uuid references employees(id),
  confirmed_at timestamptz,
  source_pattern_id uuid references fixed_shift_patterns(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_shifts_updated_at before update on shifts
  for each row execute function set_updated_at();
create index idx_shifts_employee_date on shifts(employee_id, work_date);
create index idx_shifts_status on shifts(status);

-- 13.4 確定後の変更履歴(変更前後・変更者・承認者・日時・理由・自動/手動区分は必須記録)
create table shift_change_logs (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references shifts(id) on delete cascade,
  before_data jsonb,
  after_data jsonb,
  changed_by uuid references employees(id),
  approved_by uuid references employees(id),
  changed_at timestamptz not null default now(),
  reason text not null,
  change_kind text not null check (change_kind in ('auto', 'manual'))
);
create index idx_shift_change_logs_shift on shift_change_logs(shift_id);

-- 13.7 勤務交代(依頼→応募/承諾→管理者承認)
create table shift_change_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references employees(id),
  target_shift_id uuid not null references shifts(id),
  proposed_employee_id uuid references employees(id),
  status request_status not null default 'pending',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_shift_change_requests_updated_at before update on shift_change_requests
  for each row execute function set_updated_at();

create table shift_change_approvals (
  id uuid primary key default gen_random_uuid(),
  shift_change_request_id uuid not null references shift_change_requests(id) on delete cascade,
  approved_by uuid not null references employees(id),
  approved_at timestamptz not null default now(),
  decision text not null check (decision in ('approved', 'rejected')),
  note text
);
