-- 386: 請求決済 Phase1(その1) — 機能フラグ2本+料金マスター基盤(詳細設計§3・2026-08-28俊承認)。
--   承認事項: 料金マスターをPhase1に含める/税区分列なし(詳細設計優先)/初期データは2026年度値(387)
--   /備品(supply)は品目=fee_items 1行モデル・単価は後日登録。
--   office_calendars(詳細設計§3)は新設しない: 375 の office_closure_days + is_office_closed が
--   同目的を充足済み(重複実装禁止)。営業曜日の正 = office_pickup_deadlines(081)も375が消費済み。
--   権限: 料金マスター改訂・承認系 = 統括園長以上 = 既存 is_executive_director_or_admin()(205)流用。
--   金額はKids・一般職員に非表示(AC-22)のため全表 RLS有効・ポリシー無し(定義者RPC経由のみ)。

-- 期間規約(全マスター共通): effective_to = 適用最終日(その日を含む)。次版は effective_to+1日 開始。
create extension if not exists btree_gist;   -- exclusion制約用(171導入済み・保険の冪等宣言)

-- ============================================================
-- (1) 機能フラグ2本(既定OFF・施設別)。payment は billing とのANDで単独ON不可(AC-25)。
-- ============================================================
insert into feature_flags (feature_key, name, description, default_enabled) values
  ('billing_enabled', '請求管理',
   '園児契約・料金マスター・請求管理全般。既定OFF・施設別ON。', false),
  ('billing_payment_enabled', '請求オンライン決済',
   'Stripe決済ボタンの表示(請求閲覧は billing_enabled のみで可)。billing_enabled とのAND判定=単独ONは無効。', false)
on conflict (feature_key) do nothing;

create or replace function is_billing_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_feature_enabled_for_office('billing_enabled', p_office_id);
$$;
grant execute on function is_billing_enabled_for_office(uuid) to authenticated, service_role;

-- payment単独ON不可: billing AND payment の合成判定(gate=infection_gate と同型の考え方)。
create or replace function is_billing_payment_enabled_for_office(p_office_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select is_feature_enabled_for_office('billing_enabled', p_office_id)
     and is_feature_enabled_for_office('billing_payment_enabled', p_office_id);
$$;
grant execute on function is_billing_payment_enabled_for_office(uuid) to authenticated, service_role;

-- ============================================================
-- (2) 課金項目マスター fee_items(施設別)。category=請求明細15種別(§12.4)と1:1。
--     備品(supply)・おむつ(diaper)等の「品目」は category 内に1品目=1行で持つ
--     (例: category='supply', name='帽子')。単価は fee_rate_versions で版管理。
-- ============================================================
create table fee_items (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  category text not null check (category in (
    'monthly_base','monthly_extension','extension','closing_overrun',
    'meal_main','meal_side','temp_care','temp_care_meal','temp_care_snack',
    'diaper','supply','event','misc','adjustment_plus','adjustment_minus')),
  name text not null,
  calc_unit text not null check (calc_unit in
    ('monthly','per_30min','per_10min','per_day','per_piece','one_time')),
  display_note text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, category, name),
  unique (id, category)   -- 参照側のカテゴリ整合検証用(387 seedで突合・Phase2 RPCで検証)
);
create trigger trg_fee_items_updated before update on fee_items
  for each row execute function set_updated_at();
alter table fee_items enable row level security;

-- ============================================================
-- (3) 単価の版 fee_rate_versions。整数円・適用日時点の再現(AC-14/AC-20)・版の削除禁止(運用)。
--     適用期間の重複はexclusion制約で防止(設計未規定だが適用日再現の前提防御。btree_gist=171導入済)。
-- ============================================================
create table fee_rate_versions (
  id uuid primary key default gen_random_uuid(),
  fee_item_id uuid not null references fee_items(id),
  amount int not null check (amount >= 0),   -- 整数円(本案§0)
  version int not null,
  effective_from date not null,
  effective_to date,
  approved_by uuid references employees(id),
  approved_at timestamptz,
  source_note text,                          -- 根拠資料・版(§16)
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  unique (fee_item_id, version),
  constraint fee_rate_versions_no_overlap exclude using gist (
    fee_item_id with =,
    daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') with &&
  )
);
alter table fee_rate_versions enable row level security;

-- ============================================================
-- (4) 契約プラン contract_plans(企業主導型 M8/S10/H8 行+大和 認定2行)。
--     大和の月極保育料は自治体徴収 = monthly_fee_item_id null(整合表#1)。
-- ============================================================
create table contract_plans (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  name text not null,
  cert_type text check (cert_type in ('standard','short')),   -- 大和のみ
  usage_start time not null,
  usage_end time not null,
  age_band text check (age_band in ('age0','age1_2')),        -- 企業主導型のみ
  monthly_fee_item_id uuid references fee_items(id),          -- null=自治体徴収(大和)
  overtime_fee_item_id uuid references fee_items(id),         -- null=契約時間外料金なし
  saturday_usage_end time,                                    -- 土曜の利用終了が平日と異なる場合
  effective_from date not null,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (cert_type is null or age_band is null),   -- 大和(認定)と企業主導型(年齢帯)は排他
  unique (office_id, name, effective_from),
  constraint contract_plans_no_overlap exclude using gist (
    office_id with =, name with =,
    daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') with &&
  )
);
create trigger trg_contract_plans_updated before update on contract_plans
  for each row execute function set_updated_at();
alter table contract_plans enable row level security;

-- ============================================================
-- (5) 大和の月極延長プラン(30分3,000円/1時間6,000円・月単位・月途中変更不可)。
-- ============================================================
create table monthly_extension_plans (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  name text not null,
  coverage_end time not null,                 -- 18:30 / 19:00
  fee_item_id uuid not null references fee_items(id),
  effective_from date not null,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  unique (office_id, name, effective_from),
  constraint monthly_extension_plans_no_overlap exclude using gist (
    office_id with =, name with =,
    daterange(effective_from, coalesce(effective_to, 'infinity'::date), '[]') with &&
  )
);
create trigger trg_monthly_extension_plans_updated before update on monthly_extension_plans
  for each row execute function set_updated_at();
alter table monthly_extension_plans enable row level security;

-- ============================================================
-- (6) 閉園時刻超過の実費ルール(BABY=10分450円。他園は2026年度は行なし=無効、将来INSERTで有効化)。
-- ============================================================
create table closing_overrun_rules (
  id uuid primary key default gen_random_uuid(),
  office_id uuid not null references offices(id),
  fee_item_id uuid not null references fee_items(id),
  enabled_from_fiscal_year int,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (office_id, fee_item_id)
);
create trigger trg_closing_overrun_rules_updated before update on closing_overrun_rules
  for each row execute function set_updated_at();
alter table closing_overrun_rules enable row level security;

-- 閲覧・編集RPCは Phase2(管理画面)で追加する。それまで直接アクセスは不可(RLSポリシー無し)。
-- E2E検証は SQLエディタ(postgres)で行う。
