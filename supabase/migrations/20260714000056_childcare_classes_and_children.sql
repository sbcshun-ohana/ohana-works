-- 保育業務 Phase0: クラス・園児マスタ(最小限)
-- 身体測定・発達記録・保育料プラン・曜日別登降園設定・台帳詳細等は今回はテーブルを作らず、
-- 将来フェーズでchildren.idを軸に追加できるようにする。

create table childcare_classes (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  school_year int not null,
  class_name text not null,
  age_group text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, school_year, class_name)
);
create trigger trg_childcare_classes_updated_at before update on childcare_classes
  for each row execute function set_updated_at();
create index idx_childcare_classes_office on childcare_classes(office_id);

-- 呼称サフィックスは既定で性別ルール(女児=ちゃん/男児=くん)を適用し、
-- honorific_suffixに値が入っている場合のみ園児ごとに自由文字列で上書きする
-- (「さん」「ちゃん・くん両方」等、性別ルールに収まらない呼び方に対応するためenum化しない)。
create table children (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  full_name text not null,
  display_name text not null,
  honorific_suffix text,
  gender text not null check (gender in ('男', '女', 'その他')),
  birth_date date not null,
  enrollment_date date not null,
  withdrawal_date date,
  enrollment_status text not null default '入園予定'
    check (enrollment_status in ('入園予定', '在籍中', '退園予定', '退園済み')),
  family_group_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_children_updated_at before update on children
  for each row execute function set_updated_at();
create index idx_children_office on children(office_id);
create index idx_children_family_group on children(family_group_id);

-- クラス在籍履歴(進級・クラス変更後も同一園児として記録継続)。
-- 現在の在籍 = effective_end_date is null の行。wage_masters等と同じ運用とし、
-- 変更時はRPCで旧行のeffective_end_dateを埋めてから新行をinsertする(DB制約では強制しない)。
create table child_class_enrollments (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  class_id uuid not null references childcare_classes(id),
  effective_start_date date not null,
  effective_end_date date,
  assigned_by uuid references employees(id),
  created_at timestamptz not null default now()
);
create index idx_child_class_enrollments_child on child_class_enrollments(child_id);
create index idx_child_class_enrollments_class on child_class_enrollments(class_id);
