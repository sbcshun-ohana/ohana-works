-- 255: 給食管理 Phase 1 ②(食数の日次テーブル)。設計指示書v1.0 §11。
-- 算出エンジン(256)が暫定算出→クラス承認で確定→期限内変更を履歴化する土台。
-- 職員食数=フルカバーの確定シフト(自動)+自己発注(staff_meal_entries)。自己発注UIはPhase3。

-- 職員の給食可否(自己発注=食べる / 除外=喫食しない)。employee×date で一意。
create table staff_meal_entries (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  office_id uuid not null references offices(id),
  business_date date not null,
  will_eat boolean not null,   -- true=食べる(自己発注) / false=喫食しない(除外)
  source text not null check (source in ('self_order', 'optout', 'admin')),
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  unique (employee_id, business_date)
);
create index idx_staff_meal_entries_office_date on staff_meal_entries(office_id, business_date);
alter table staff_meal_entries enable row level security;
create policy staff_meal_entries_select on staff_meal_entries
  for select using (is_childcare_staff());

-- 施設×日の食数メタ(9:31スナップショット時刻・Station固有欄はPhase2)。
create table meal_count_days (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  business_date date not null,
  computed_at timestamptz,           -- 暫定算出(9:31)を行った時刻
  milk_bottles int,                  -- Mahalo Station固有: 今日の牛乳本数(手入力・Phase2)
  updated_at timestamptz not null default now(),
  unique (office_id, business_date)
);
create trigger trg_meal_count_days_updated_at
  before update on meal_count_days for each row execute function set_updated_at();
alter table meal_count_days enable row level security;
create policy meal_count_days_select on meal_count_days
  for select using (is_childcare_staff());

-- 行区分×食事区分の食数(暫定/確定・クラス承認者)。
create table meal_count_rows (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  business_date date not null,
  row_key text not null,
  meal_slot text not null check (meal_slot in ('am_snack', 'lunch', 'pm_snack')),
  child_count int not null default 0,
  staff_count int not null default 0,
  is_confirmed boolean not null default false,   -- クラス承認で確定
  confirmed_by uuid references employees(id),
  confirmed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (office_id, business_date, row_key, meal_slot)
);
create index idx_meal_count_rows_office_date on meal_count_rows(office_id, business_date);
create trigger trg_meal_count_rows_updated_at
  before update on meal_count_rows for each row execute function set_updated_at();
alter table meal_count_rows enable row level security;
create policy meal_count_rows_select on meal_count_rows
  for select using (is_childcare_staff());

-- 変更履歴(変更前後値・変更者・時刻・厨房確認者=§5.2アラート用)。
create table meal_count_changes (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  business_date date not null,
  row_key text not null,
  meal_slot text not null,
  field text not null check (field in ('child', 'staff')),
  old_count int not null,
  new_count int not null,
  changed_by uuid references employees(id),
  changed_at timestamptz not null default now(),
  acknowledged_by uuid references employees(id),   -- 厨房ページでの確認
  acknowledged_at timestamptz
);
create index idx_meal_count_changes_unack on meal_count_changes(office_id, business_date) where acknowledged_at is null;
alter table meal_count_changes enable row level security;
create policy meal_count_changes_select on meal_count_changes
  for select using (is_childcare_staff());

comment on table meal_count_rows is
  '給食管理の日次食数(255)。9:31暫定→クラス承認で確定→期限内変更は meal_count_changes へ履歴化。書込は256のRPC。';
