-- 通知・ログ系(設計書28.6)

-- 22章 アラートルール(条件・重要度・通知対象ロールは画面から変更可能)
create table alert_rules (
  id uuid primary key default gen_random_uuid(),
  alert_key text not null unique,
  name text not null,
  description text,
  severity text not null default 'normal' check (severity in ('info', 'normal', 'high')),
  target_role_codes text[] not null default '{}',
  enabled boolean not null default true,
  condition_config jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_alert_rules_updated_at before update on alert_rules
  for each row execute function set_updated_at();

create table alerts (
  id uuid primary key default gen_random_uuid(),
  alert_rule_id uuid not null references alert_rules(id),
  target_employee_id uuid references employees(id),
  target_office_id uuid references offices(id),
  context jsonb not null default '{}',
  status alert_status not null default '未処理',
  resolved_by uuid references employees(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_alerts_status on alerts(status);
create index idx_alerts_employee on alerts(target_employee_id);

create table notification_templates (
  id uuid primary key default gen_random_uuid(),
  template_key text not null unique,
  title_template text not null,
  body_template text not null,
  channels text[] not null default '{}', -- fcm / in_app / alert_list
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_notification_templates_updated_at before update on notification_templates
  for each row execute function set_updated_at();

-- 通知イベントを1テーブルに集約し、チャネルへ出し分け
create table notifications (
  id uuid primary key default gen_random_uuid(),
  notification_type text not null,
  title text not null,
  body text,
  channels text[] not null default '{}',
  target_employee_id uuid references employees(id),
  target_role_code text,
  payload jsonb not null default '{}',
  scheduled_at timestamptz,
  sent_at timestamptz,
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  retry_count int not null default 0,
  created_at timestamptz not null default now()
);
create index idx_notifications_employee on notifications(target_employee_id);
create index idx_notifications_status on notifications(status);

-- 27章 イベントログ(重要テーブルはDBトリガーによる自動記録+アプリ層ログの二重化)
create table event_logs (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  operator_id uuid references employees(id),
  target_type text not null,
  target_id uuid,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  reason text,
  device_info text,
  operation_source text not null default 'db_trigger' check (operation_source in ('db_trigger', 'app'))
);
create index idx_event_logs_target on event_logs(target_type, target_id);
create index idx_event_logs_operator on event_logs(operator_id);

-- 21章 重要情報アクセスログ(マイナンバー・給与・扶養・標準報酬・借上宿舎等の閲覧記録)
create table sensitive_access_logs (
  id uuid primary key default gen_random_uuid(),
  viewer_id uuid references employees(id),
  target_employee_id uuid references employees(id),
  screen text not null,
  target_data text not null,
  device_info text,
  ip_address inet,
  accessed_at timestamptz not null default now()
);
create index idx_sensitive_access_logs_viewer on sensitive_access_logs(viewer_id);
create index idx_sensitive_access_logs_target on sensitive_access_logs(target_employee_id);

-- 23章 災害モード
create table disaster_events (
  id uuid primary key default gen_random_uuid(),
  triggered_by uuid not null references employees(id),
  triggered_at timestamptz not null default now(),
  status text not null default 'active' check (status in ('active', 'closed')),
  closed_at timestamptz,
  note text
);

create table disaster_responses (
  id uuid primary key default gen_random_uuid(),
  disaster_event_id uuid not null references disaster_events(id) on delete cascade,
  employee_id uuid not null references employees(id),
  response_type disaster_response_type not null,
  responded_at timestamptz not null default now(),
  note text,
  unique (disaster_event_id, employee_id)
);

-- 24章 監査資料管理(職種別必須資料の未提出判定に利用)
create table audit_documents (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid references employees(id),
  office_id uuid references offices(id),
  document_type text not null, -- 例: 保育士証 / 幼稚園教諭免許 / 子育て支援員研修修了証 / 栄養士免許
  file_path text,
  submitted_flag boolean not null default false,
  submitted_date date,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_audit_documents_updated_at before update on audit_documents
  for each row execute function set_updated_at();
create index idx_audit_documents_employee on audit_documents(employee_id);

-- 20.4 休日カレンダー(土曜は休日固定ではない)
create table holidays (
  id uuid primary key default gen_random_uuid(),
  holiday_date date not null unique,
  holiday_type text not null check (holiday_type in ('national_holiday', 'year_end_new_year', 'company_holiday')),
  name text,
  created_at timestamptz not null default now()
);

-- 20.2 汎用ファイル取込履歴(住民税一覧/源泉徴収税額表/社保料額表/労働者名簿等。シフトは shift_imports を使用)
create table file_import_logs (
  id uuid primary key default gen_random_uuid(),
  import_target text not null, -- 対象マスタ名
  file_name text not null,
  imported_by uuid not null references employees(id),
  imported_at timestamptz not null default now(),
  target_period text,
  imported_count int not null default 0,
  unmatched_count int not null default 0,
  error_count int not null default 0,
  warning_count int not null default 0,
  status file_import_status not null default 'awaiting_review',
  detail jsonb,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 27章: 重要テーブルの自動監査ログ(DBトリガー層)
-- ============================================================
create or replace function log_event_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operator uuid;
begin
  select id into v_operator from employees where auth_user_id = auth.uid();

  insert into event_logs (operator_id, target_type, target_id, action, before_data, after_data, operation_source)
  values (
    v_operator,
    TG_TABLE_NAME,
    coalesce(new.id, old.id),
    TG_OP,
    case when TG_OP in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('UPDATE', 'INSERT') then to_jsonb(new) else null end,
    'db_trigger'
  );
  return coalesce(new, old);
end;
$$;

do $$
declare
  t text;
  audited_tables text[] := array[
    'employees',
    'employee_office_assignments',
    'employee_roles',
    'wage_masters',
    'employee_allowances',
    'standard_monthly_remunerations',
    'tax_withholding_statuses',
    'bank_transfer_accounts',
    'shifts',
    'shift_change_approvals',
    'requests',
    'daily_attendances',
    'attendance_approvals',
    'proxy_punches',
    'payroll_runs',
    'payslips',
    'company_housing_settings',
    'company_housing_deductions',
    'special_duty_allowances',
    'shift_imports',
    'file_import_logs'
  ];
begin
  foreach t in array audited_tables loop
    execute format(
      'create trigger trg_audit_%1$s after insert or update or delete on %1$s for each row execute function log_event_change();',
      t
    );
  end loop;
end $$;
