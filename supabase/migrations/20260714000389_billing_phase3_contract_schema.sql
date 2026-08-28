-- 389: 請求決済 Phase3(その1) — 園児契約履歴4表+免除書類バケット(詳細設計§4・2026-08-28俊承認)。
--   月次履歴の期間規約: start_month/end_month は「月初日」で月を表現。end_month=その月まで有効
--   (inclusive)・null=継続。翌契約は end_month の翌月から。重複はexclusionで防止
--   (月初日同士のdaterange '[]' は月単位の重複判定として機能する)。
--   権限: 直テーブルアクセス不可(RLS有効ポリシー無し・386と同方針)。操作は390のRPC経由のみ。
--   契約プランと園児の施設一致はRPC側で検証(転園時の履歴保全のためFKでは縛らない)。

-- ============================================================
-- (1) child_contracts — 月次契約履歴(AC-01継続・AC-02予約変更=閉じて作る)
-- ============================================================
create table child_contracts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id),
  contract_plan_id uuid not null references contract_plans(id),
  start_month date not null check (extract(day from start_month) = 1),
  end_month date check (end_month is null or (extract(day from end_month) = 1 and end_month >= start_month)),
  superseded_by uuid references child_contracts(id),  -- 自動クローズの由来(この契約の追加で閉じられた)。
                                                      -- 手動クローズ(退園等)と区別し、予約削除時の再オープン誤爆を防ぐ
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  constraint child_contracts_no_overlap exclude using gist (
    child_id with =,
    daterange(start_month, coalesce(end_month, 'infinity'::date), '[]') with &&
  )
);
create index idx_child_contracts_child on child_contracts(child_id);
alter table child_contracts enable row level security;

-- ============================================================
-- (2) child_extension_contracts — 大和の月極延長加入履歴(月単位・月途中変更不可)
-- ============================================================
create table child_extension_contracts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id),
  monthly_extension_plan_id uuid not null references monthly_extension_plans(id),
  start_month date not null check (extract(day from start_month) = 1),
  end_month date check (end_month is null or (extract(day from end_month) = 1 and end_month >= start_month)),
  superseded_by uuid references child_extension_contracts(id),  -- 由来リンク(child_contractsと同旨)
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  constraint child_extension_contracts_no_overlap exclude using gist (
    child_id with =,
    daterange(start_month, coalesce(end_month, 'infinity'::date), '[]') with &&
  )
);
create index idx_child_extension_contracts_child on child_extension_contracts(child_id);
alter table child_extension_contracts enable row level security;

-- ============================================================
-- (3) child_exemptions — 無償化・免除(kind別期間・非課税証明PDF=§11.1・俊確定⑤)
--     company_paid = 自社職員の子(会社負担=請求0円・利用実績は記録)
-- ============================================================
create table child_exemptions (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id),
  kind text not null check (kind in ('free_childcare','meal_main','meal_side','company_paid','custom')),
  start_month date not null check (extract(day from start_month) = 1),
  end_month date check (end_month is null or (extract(day from end_month) = 1 and end_month >= start_month)),
  document_state text not null default 'not_required'
    check (document_state in ('not_required','pending','confirmed','deficient')),
  document_path text,                        -- exemption-documents バケット内のパス
  document_fiscal_year int,                  -- 書類の有効年度(§11.1・毎年度更新)
  document_confirmed_by uuid references employees(id),
  document_confirmed_at timestamptz,
  note text,
  created_by uuid references employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint child_exemptions_no_overlap exclude using gist (
    child_id with =,
    kind with =,
    daterange(start_month, coalesce(end_month, 'infinity'::date), '[]') with &&
  )
);
create index idx_child_exemptions_child on child_exemptions(child_id);
create trigger trg_child_exemptions_updated before update on child_exemptions
  for each row execute function set_updated_at();
alter table child_exemptions enable row level security;

-- ============================================================
-- (4) child_age_band_snapshots — 企業主導型の年齢区分の年度確定(クラス基準=俊確定②)
--     0歳児クラス=age0 / 1・2歳児クラス=age1_2。進級時(年度)に切替・誕生日では変わらない。
-- ============================================================
create table child_age_band_snapshots (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id),
  fiscal_year int not null,
  age_band text not null check (age_band in ('age0','age1_2')),
  basis_class_id uuid references childcare_classes(id),
  determined_at timestamptz not null default now(),
  unique (child_id, fiscal_year)
);
alter table child_age_band_snapshots enable row level security;

-- ============================================================
-- (5) 免除書類バケット(非公開)。世帯収入の機微書類のため統括園長以上のみ
--     (205 document-templates と同型・パス: {child_id}/{fiscal_year}/xxx.pdf)
-- ============================================================
insert into storage.buckets (id, name, public)
values ('exemption-documents', 'exemption-documents', false)
on conflict (id) do nothing;

drop policy if exists "exemption_docs_select" on storage.objects;
drop policy if exists "exemption_docs_insert" on storage.objects;
drop policy if exists "exemption_docs_update" on storage.objects;
drop policy if exists "exemption_docs_delete" on storage.objects;
create policy "exemption_docs_select" on storage.objects for select
  using (bucket_id = 'exemption-documents' and is_executive_director_or_admin());
create policy "exemption_docs_insert" on storage.objects for insert
  with check (bucket_id = 'exemption-documents' and is_executive_director_or_admin());
create policy "exemption_docs_update" on storage.objects for update
  using (bucket_id = 'exemption-documents' and is_executive_director_or_admin());
create policy "exemption_docs_delete" on storage.objects for delete
  using (bucket_id = 'exemption-documents' and is_executive_director_or_admin());
