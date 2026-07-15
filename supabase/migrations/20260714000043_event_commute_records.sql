-- イベント直行日の通勤費(event_commute_records)。
--
-- 保育園以外のイベント先へ直行する日は、通常の施設への通勤費とは別に
-- 実費を支給する。1職員につき1日1件のみ登録可能(unique制約)。
-- special_duty_allowances(特殊業務手当)と同じく、labor_manager_plusが
-- confirmed=trueにするまで給与計算エンジンには反映されない(承認制)。

create table event_commute_records (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id),
  work_date date not null,
  destination text,
  amount int not null check (amount >= 0),
  taxable boolean not null default true,
  confirmed boolean not null default false,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (employee_id, work_date)
);

create index idx_event_commute_records_employee_month
  on event_commute_records (employee_id, work_date);

alter table event_commute_records enable row level security;

create policy event_commute_records_labor_manager_only on event_commute_records
  for all using (is_labor_manager_plus()) with check (is_labor_manager_plus());
