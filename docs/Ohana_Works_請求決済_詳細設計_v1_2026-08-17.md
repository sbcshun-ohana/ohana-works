# Ohana Works 園児契約・請求決済 詳細設計 v1.0(2026-08-17・CC作成)

正本: 本案v1.1(2026-08-13) > 草案。Phase 0 Fit & Gap(2026-08-14)と業務確認5点の回答、
入園時基本情報 Phase 0(2026-08-17)の共有エンティティ依存関係図を反映した物理設計。
**本書は俊レビュー用。承認後、Phase 1から migration 全文提示の通常フローで実装する(着手=第1弾リリース後)。**

## 0. 確定済み前提(再掲・変更なし)

- 請求=世帯1本(兄弟合算・AC-26)/期限=公開+10日/免税(税表示なし)/Stripe手数料園負担/自動引落なし(都度承認)
- 決済完了(Webhook署名検証後)=入金消込。ペイアウト×銀行明細の突合はv1システム外運用
- 料金ハードコード禁止(版管理)/発行済み請求は不変(差額は将来請求の調整)/AIに金額決定させない/整数円
- 年齢区分=在籍クラス基準・年度固定(スナップショット保存)/延長判定=実打刻・秒単位・1秒超過で1単位切上げ
- 週次予定=既存 child_weekly_schedule の期間履歴化(新設禁止)/一時変更・恒久相談=parent_requests拡張
- 機能全体=管理者以上(主任含めず)・金額はKids/一般職員に非表示(AC-22)/料金マスター・公開承認・手動消込=統括園長以上
- フラグ2段: `billing_enabled` → `billing_payment_enabled`(gateと同型・payment単独ON不可)

---

## 1. 世帯・代表保護者(入園時基本情報と同一基盤・二重概念禁止)

```sql
households (
  id uuid PK,
  display_name text,                      -- 例「山田家」(表示用・請求書の請求先名)
  representative_guardian_id uuid → guardians,  -- 代表保護者(通知・決済の既定宛先)
  notes text, created_at, updated_at
)
children.household_id  uuid → households (nullable・段階移行)
guardians.household_id uuid → households (nullable)
```

- **請求先=household**。登録保護者は全員が世帯の請求を閲覧・支払い可能(AC-19: 他世帯は不可)。
- 移行: guardian_child_links の primary 保護者集合が同一の園児群を世帯候補として自動生成→管理者画面で確認・統合/分割→確定。
  未使用の `children.family_group_id` は廃止(コメントで非推奨化・householdへ一本化)。
- 共同親権等で世帯を分けたい場合: 園児は1世帯にのみ属する(請求は1本)。もう一方の保護者は閲覧のみ(links で担保)。
- 入園時基本情報(M6)はこの households を拡張(住所等の属性追加)する。**本設計が世帯の設計責任を持つ**。

## 2. 在籍種別(M6 Phase 1と統一・本設計は前提として利用)

- `children.child_kind` text default 'regular' check ('regular','temporary') を M6 Phase 1 で追加。
- 一時預かり児= child_kind='temporary' の簡易レコード(名前・生年月日・世帯・保護者リンク)。
- 無償対象(自社職員の子)= 3章の exemption(kind='company_paid')で表現(利用実績は記録・請求は0円)。

## 3. 料金マスター(全て版管理・§16)

```sql
fee_items (                                -- 「課金項目」の器(施設別)
  id uuid PK, office_id → offices,
  category text check (                    -- 請求明細15種別(§12.4)と1:1
    'monthly_base','monthly_extension','extension','closing_overrun',
    'meal_main','meal_side','temp_care','temp_care_meal','temp_care_snack',
    'diaper','supply','event','misc','adjustment_plus','adjustment_minus'),
  name text, calc_unit text check ('monthly','per_30min','per_10min','per_day','per_piece','one_time'),
  display_note text, sort_order int, is_active bool
)
fee_rate_versions (                        -- 単価の版(適用日時点で再現=AC-14系)
  id uuid PK, fee_item_id → fee_items,
  amount int,                              -- 整数円
  version int, effective_from date NOT NULL, effective_to date,
  approved_by → employees, approved_at, source_note text,   -- 根拠資料・版(§16)
  unique(fee_item_id, version)
)
contract_plans (                           -- 契約プラン(企業主導型8/10/8行+大和認定2行)
  id uuid PK, office_id, name text,
  cert_type text check ('standard','short') null,   -- 大和のみ
  usage_start time, usage_end time,                 -- 契約利用時間(9:00〜17:00等)
  age_band text check ('age0','age1_2') null,       -- 企業主導型のみ
  monthly_fee_item_id → fee_items null,             -- 月極保育料(大和はnull=自治体徴収)
  overtime_fee_item_id → fee_items null,            -- 契約時間外料金(なし=null)
  saturday_usage_end time null,                     -- 大和短時間の土曜16:00等
  effective_from date, effective_to date, is_active bool
)
monthly_extension_plans (                  -- 大和の月極延長(30分3,000/1時間6,000)
  id uuid PK, office_id, name text, coverage_end time,   -- 18:30 / 19:00
  fee_item_id → fee_items, effective_from, effective_to, is_active
)
closing_overrun_rules (                    -- 閉園超過実費(BABY=10分450円・他園は器のみ2026無効)
  id uuid PK, office_id, fee_item_id, enabled_from_fiscal_year int null, is_active
)
office_calendars (                         -- 施設開所カレンダー(§16)。日付単位の休園。
  id uuid PK, office_id, calendar_date date, day_type text check ('open','closed','special'),
  note text, unique(office_id, calendar_date)
)  -- 曜日既定は既存 office_pickup_deadlines(81・未消費)を営業曜日の正として消費開始
```

- 初期データ: 草案§5の表を項目単位で突合できる投入SQLで提示(Phase 1で停止・俊承認)。
- 大和給食費: fee_items(meal_main 2,000円/meal_side 4,500円・3歳以上児=**在籍クラス基準**)。登園0日でも請求。

## 4. 園児側の契約履歴(園児マスター拡張)

```sql
child_contracts (                          -- 月次契約履歴(AC-01継続・AC-02予約変更)
  id uuid PK, child_id, contract_plan_id → contract_plans,
  start_month date NOT NULL,               -- 月初日で表現
  end_month date null,                     -- null=継続
  created_by, created_at, note text,
  exclude (child_id, 期間重複禁止)          -- 排他制約
)
child_extension_contracts (                -- 大和の月極延長(月単位・月途中変更不可)
  id uuid PK, child_id, monthly_extension_plan_id, start_month, end_month null
)
child_exemptions (                         -- 無償化・免除(適用期間付き・個別免除対応)
  id uuid PK, child_id,
  kind text check ('free_childcare','meal_main','meal_side','company_paid','custom'),
  start_month date, end_month date null,
  document_state text check ('not_required','pending','confirmed','deficient') default 'not_required',
  document_confirmed_by, document_confirmed_at, note
)                                          -- 無償化=住民税非課税証明の年度確認(§11.1)
child_age_band_snapshots (                 -- 年齢区分の年度確定(クラス基準・俊確定②)
  id uuid PK, child_id, fiscal_year int, age_band text,
  basis_class_id → childcare_classes, determined_at, unique(child_id, fiscal_year)
)
```

## 5. 週次予定の期間履歴化(整合表#3・既存拡張)

- `child_weekly_schedule` に `effective_from date not null default '2026-04-01'` / `effective_to date` を追加し、
  unique(child_id, weekday) → unique(child_id, weekday, effective_from) へ変更。
- K6/K7への既定値供給RPC(fetch_child_weekly_schedule ほか)は「対象日に有効な行」を返すよう再定義(AC-23回帰E2E必須)。
- 入力制限(AC-04): 保存RPCで契約プラン(usage_start/end+月極延長coverage)の範囲外を拒否。
- 変更予約: 新期間行の追加=旧行の effective_to 自動クローズ(進級一括と同じ「閉じて作る」運用)。

## 6. 延長料金計算(実打刻正本・§9)

```sql
billable_usage_days (                      -- 日次の課金実績(計算結果のスナップショット)
  id uuid PK, child_id, office_id, usage_date date,
  kind text check ('extension_am','extension_pm','monthly_ext_overrun','closing_overrun','temp_care_time'),
  over_seconds int, units int, unit_amount int, amount int,
  fee_rate_version_id → fee_rate_versions,
  basis jsonb,                             -- 打刻時刻・契約範囲・計算式のスナップショット
  calculated_at, invoice_item_id null,     -- 請求取込済みマーク(二重計上防止)
  waived_amount int default 0,
  unique(child_id, usage_date, kind)
)
fee_waivers (                              -- 園側事情の免除・取消(§9.5・管理者以上)
  id uuid PK, usage_day_id → billable_usage_days, original_amount, waived_amount,
  reason text NOT NULL, operator, operated_at, approved_by, approved_at
)
```

- 計算式(確定): `units = ceil(超過秒数 / 単位秒数)`。朝(契約開始前)・夕(契約終了後)は別切上げ合算(AC-07)。
  大和標準=7:00開始のため早朝延長なし(AC-08)。月極延長はcoverage_end超過分のみ追加(AC-09)。
  BABY閉園超過=20:00超を10分450円(AC-10)。判定は秒単位(打刻timestamptzそのまま)。
- 計算タイミング: **請求サイクル実行時に対象月分を一括生成**(正)+デイリーボード用の当日プレビューRPC(保存しない導出表示)。
  打刻修正(187)時: 未請求分(invoice_item_id null)は次回サイクルで自動再計算、公開済み分は差額候補を管理者へ提示(§9.6)。
- 一時預かり: 職員が利用実績(開始・終了)を登録→10分200円の決定論的計算+給食500/おやつ100(当日精算・都度請求)。

## 7. 請求(§12)

```sql
billing_cycles (id, office_id, billing_month date, status, opened_by/at, calculated_at, note)
invoices (
  id uuid PK, invoice_no text unique,      -- 採番: {施設コード}-{YYYYMM}-{連番3桁} 例 YMT-202609-012
  household_id → households, office_id, billing_month date,
  status text check (草案§12.7の13状態),
  total_amount int, paid_amount int default 0,   -- balance=total-paid(導出)
  due_date date,                           -- published_at + 10日
  approved_by/at, published_at, cancelled_at/by/reason,
  created_at, updated_at
)
invoice_items (
  id uuid PK, invoice_id, child_id null,   -- 世帯合算内の園児区分(世帯共通項目はnull)
  category text(15種別), description text, target_period text,
  quantity numeric, unit_amount int, amount int,
  fee_rate_version_id null, source_table text null, source_id uuid null,
  unique(source_table, source_id)          -- 元記録の二重計上防止(AC-11)
)
invoice_adjustments (                      -- 請求額調整(§12.5・統括承認必須)
  id uuid PK, household_id, adjustment_kind check ('plus','minus'), amount int,
  origin_invoice_id null, origin_item_id null,
  guardian_note text NOT NULL,             -- 保護者向け説明
  internal_note text, created_by/at, approved_by/at,
  applied_invoice_id null                  -- 取り込まれた将来請求
)
invoice_number_sequences (office_id, year_month, last_no int, PK(office_id, year_month))  -- 排他採番
```

- サイクル内容(AC-12): 企業主導型=当月月極+前月変動+調整/大和=前月固定・変動+調整(月極なし・給食費は固定)。
- フロー=草案§12.3どおり。自動チェック(§19の18項目)は `review_required` 遷移時に検査結果を保存し、
  エラーは自動修正せず一覧提示。承認=統括園長以上(AC-13)→公開→保護者アプリ表示。
- マイナス調整で合計<0 → 発行せず繰越残高警告(§12.5)。

## 8. 決済・入金(§13)+Stripe

```sql
payments (
  id uuid PK, invoice_id, method check ('stripe','cash','bank_transfer'),
  amount int, paid_at timestamptz,
  stripe_payment_intent_id text unique null,
  recorded_by null(手動時), memo, created_at
)
stripe_webhook_events (
  id uuid PK, stripe_event_id text unique,  -- 冪等(AC-16)
  event_type text, raw jsonb, status check ('processed','failed','skipped'),
  processed_at, error text
)
receipts (
  id uuid PK, receipt_no text unique,       -- {施設コード}-R-{YYYYMM}-{連番}
  invoice_id, payment_id, amount int, method, issued_at,
  household_name, child_names text[], note  -- 発行時点の写し(不変)
)
```

- 保護者フロー: 公開済み請求→明細確認→「支払いへ進む」→ **Stripe Checkout Session**(metadata=invoice_id)
  → Webhook(`stripe-webhook` Edge Function新設: 署名検証・stripe_event_id冪等・順不同/再送対応・raw保存・失敗キュー)
  → payments 行作成→ invoices.paid_amount 更新→ 残高0で `paid` → receipts 自動発行。
- 手動入金=統括園長以上のみ(AC-17)。部分入金=partially_paid、過入金=管理者確認状態(§13.4)。
- **領収書の提示方式(Q&A-2参照)**: v1はアプリ内の領収書画面(印刷可能なレイアウト・receiptsの不変写しを表示)を正とし、
  PDFダウンロードは admin_web の生成ルート(給与明細と同方式)を保護者向け署名URLで提供する案。
- 未払い通知(§14): 既存outbox+日次cron(期限翌日/3日/7日/以後7日毎・残高0で停止・施設別設定・一時停止状態あり)。

## 9. 権限写像(確定定義の適用)

| 操作 | 権限 |
|---|---|
| 契約・週次予定・実績の閲覧/入力 | 管理者以上(director/office_manager+統括系。**chief含めず**)。金額はKids・一般職員に一切非表示(AC-22) |
| 過去月の契約・認定・週次予定の変更 | 統括園長以上(AC-03) |
| 料金マスター登録・改訂/請求承認・公開/手動消込/調整承認 | 統括園長以上(`is_executive_director_or_admin()`=205実装済み) |
| 延長免除(園側事情) | 管理者以上・理由必須・監査 |
| 保護者 | 自世帯の契約・請求・領収書のみ(AC-19)。支払いは登録保護者なら誰でも可 |

## 10. 実装フェーズ(migration計画・着手=第1弾リリース後)

| Phase | migration内容 | 停止点 |
|---|---|---|
| 1 | households+移行候補生成/児kind(=M6と共同)/フラグ2本 | 全文提示→承認→E2E |
| 2 | 料金マスター群+**初期データ投入SQL(草案§5表と突合形式)** | 初期データで停止・俊承認 |
| 3 | 契約履歴4表+年齢スナップショット+園児マスターUI(契約タブ) | |
| 4 | 週次予定の期間履歴化+AC-23回帰E2E+AC-04入力制限 | |
| 5 | 一時変更/恒久相談=parent_requests拡張(197/201/202と同型) | |
| 6 | 延長計算エンジン(billable_usage_days+免除)+ボードプレビュー | 計算E2E(AC-06〜10) |
| 7 | 請求サイクル+請求管理画面+自動チェック18項目+調整 | |
| 8 | Stripe Checkout+Webhook Edge+手動消込+領収書+未払い通知 | 拒否側E2E一式 |
| 9 | 一時預かり・おむつ/備品連携・月次集計・コドモンCSV突合画面 | 並行運用開始(2027/1〜3) |

## 11. 俊へのQ&A(本設計の残確定事項)

1. **請求番号・領収書番号の形式**: `YMT-202609-012` のような「施設コード-年月-連番」で良いか。施設コード(YMT/BMH/MST/HLL等)の指定を。
2. **領収書のPDF**: v1は「アプリ内の領収書画面(印刷可)+必要時にPDFダウンロード」の2段構えで良いか。
3. **支払期限の起算**: 公開日+10日は暦日(土日祝含む)で良いか。
4. **行事費**: 明細種別は用意するが、入力は都度手入力(マスター化しない)で良いか。
5. **無償化の非課税証明書**: v1は受領記録(確認者・日付・年度)のみで、ファイル添付は将来拡張で良いか。
6. **大和の主食費・副食費の「3歳以上児」**: 年齢区分と同じく在籍クラス基準(幼児クラス在籍=対象)で良いか。
