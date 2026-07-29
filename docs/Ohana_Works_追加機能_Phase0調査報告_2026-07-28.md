# Ohana Works 追加機能 Phase 0 調査報告
## 個別目標シート・架け橋カリキュラム・支援保育事業

- 作成: Claude Code(Sonnet 5)、2026-07-28
- 対象: `Ohana_Works_追加機能_実装指示書_v1_2026-07-28.md`(以下「指示書」) §5 Phase 0
- 併読元: `Ohana_Works_追加機能_個別目標・架け橋・支援保育_設計指示書案.md`(以下「原案」)
- 本書は調査・報告のみ。実装コードは一切含まない
- 実施時点: HEAD=`7bf8073`、マイグレーション最新=136番、working tree clean(実施前に確認済み)

---

## 0. 最重要発見(実装判断に直結)

### 0.1 職員のロール割当(employee_roles)がほぼ空

```sql
select r.code, count(*) from employee_roles er join roles r on r.id=er.role_id group by r.code;
-- system_admin: 1件のみ(このセッションでの検証用アカウント)
```

`roles`マスタ自体は7種(system_admin / labor_manager / director[園長] / chief[主任] / office_manager[園管理者] / viewer / staff)存在するが、**実在55名の職員のうち、director・chief・office_managerが割り当てられている人は0名**。原案・指示書は「大原利奈=園長」「高木俊=施設長」等の役職実態を前提に承認者を決めているが、**この対応関係はDBのどこにも入力されていない**。

`positions`(役職マスタテーブル)も0件、`employees.position_id`が設定されている職員も0件。つまり「役職」という情報は現状**このシステムのどこにも構造化データとして存在しない**(紙・口頭・別Excel等で管理されている可能性が高い)。

**影響**: 指示書§4-D2は「Phase 0で対応表を作ってからRLSを書く」としているが、対応表を作る前に**そもそも55名分の役職(主任/管理者/園長/施設長)をemployee_rolesへ登録する作業自体がPhase 1着手前の前提作業として必要**。これは調査では埋められず、人事データの入力(誰が主任か等の一覧)をユーザーから受け取る必要がある。§4-D2に記載の対応表(大原利奈=園長、高木俊=施設長)はこの55名分の一部でしかなく、他の職員(主任候補者等)の一覧は未確認。

### 0.2 「施設長」に対応するroleコードが存在しない

既存の`roles`は7種のみで、複数施設を横断する「施設長」という区分に直接対応するコードがない。候補:
- (a) `system_admin`を代用(全施設アクセス可能な点は一致するが、意味的にはシステム管理者であり施設長とは異なる)
- (b) `office_manager`または`director`を高木俊に**3施設分**(BABY MAHALO・Mahalo Station・Halelea)割り当てる(`employee_roles.office_id`は施設単位で複数行持てるため技術的には可能)
- (c) 新規role `facility_head`を追加する

指示書は「役職ロールで判定せず、年度・施設・対象業務ごとの付与テーブルで持つ」(原案§11.4)方針を採っているため、**最終承認者の指定は`roles`を経由せず専用の「承認者指定テーブル」で持つのが素直**(0.1の対応表整備を待たずに個別目標シートの承認者だけは先に確定できる)。

### 0.3 「日常記録」: 実データは0件。ただしスキーマは再利用第一候補(2026-07-29 実データ確認により訂正、末尾「訂正履歴」参照)

原案・指示書は「園児の発達・支援記録テーブルはほぼ存在しない可能性が高い」としており、実データを確認した結果、これは**その通り**だった。`child_personal_journals`(個人日誌、`20260714000067`)は**総件数0件**(施設別・クラス別内訳、直近1年件数、記入率、status分布、記入者傾向のいずれも算出不可)。保育業務全体が本番でまだ実質稼働前(`children`在籍3件のみ)であることと整合しており、日常記録も一切蓄積されていない。

一方で、**スキーマ(列構造)自体は架け橋・支援保育が必要とする形に既に近い**。新規テーブルを作らず、日常記録の実体としてこのテーブルを再利用する第一候補と位置づける。

```sql
create table child_personal_journals (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  business_date date not null,
  content_fact text,            -- 事実
  content_support text,         -- 支援内容
  content_reaction text,        -- 反応
  content_progress text,        -- 経過
  content_consideration text,   -- 配慮事項
  content_handover text,        -- 引き継ぎ
  ai_generated_text text,
  current_text text,
  status text not null default 'draft' check (status in ('draft', 'submitted', 'approved')),
  created_by uuid references employees(id),
  approved_by uuid references employees(id),
  approved_at timestamptz,
  ...
  unique (child_id, business_date)
);
```

- 園児×日付でユニーク、`content_support`(支援内容)・`content_consideration`(配慮事項)・`content_progress`(経過)という列が既にあり、まさに架け橋・支援保育がAI下書きの根拠として使いたい情報の形をしている
- `status`は`draft/submitted/approved`と、共通基盤で使う語彙(D3-4)の**部分集合として既に運用されている**(職員向け連絡帳と同時生成、`20260714000067`のコメントより)
- `ai_generated_text`列があり、AI生成結果を保持する前例が既にある(ただし生成元は現状モック、0.4参照)
- 保護者には非公開(職員向け専用)、施設内職員+管理者を上限とする2段階の可視性制御(Tier1固定RLS + Tier2 `childcare_office_settings.personal_journal_visibility_scope`)という設計パターンが既にある

**ただし**: これは「毎日の連絡帳と同時に書く簡易日誌」であり、原案が求める「個別支援計画」「面談記録」「関係機関連携記録」のような構造化された支援計画・経過記録ではない。実データ0件のため、5歳児クラス・3〜5歳児クラスでの記入分量・品質の評価は現時点では不可能で、**日常記録の入力運用そのものを新規に確立する必要がある**(指示書§6.2の懸念通り)。

**判断**: `child_personal_journals`は実データ0件だが、`content_support`(支援内容)・`content_consideration`(配慮事項)・`status`(draft/submitted/approved)という語彙を既に備えており、**新規テーブルを作らず日常記録の実体として再利用する第一候補**とする。ただし「参照元として今すぐ使えるデータ」ではなく「今後の入力運用が確立すれば根拠として使える器」という位置づけであり、架け橋・支援保育のAI下書き機能着手前に、まず日常記録の入力運用(誰が・いつ・どの端末で記入するか)を確立し、一定期間データを蓄積してから根拠記録として活用する順序が必要。この結論をユーザーへ報告し、運用案の承認を得る。

### 0.4 AI実行の実態: Provider抽象化はゼロ、モック実装が1件のみ

`supabase/functions/generate-contact-note/index.ts`が既存の唯一のAI連携コードだが、`ANTHROPIC_API_KEY`が本番に未登録のため`callAI()`は完全にモック(`mockGenerate`)。Provider切替、プロンプト版管理、実行履歴テーブルはいずれも存在しない。指示書D5の「新規構築」判断は妥当で、既存流用できる資産はゼロ(`ai_style_profiles`はトーン設定jsonbのみで、実行履歴やProvider抽象化ではない)。

---

## 1. 原案 §10.1 の12項目 調査結果

### 1) 現行アプリ・Web・Supabaseのディレクトリ構成

```
admin_web/          Next.js(Vercel: adminweb-lovat.vercel.app)。ルート: attendance, childcare, employees,
                     feature-flags, login, notices, payroll, settings, shifts (/hr は存在しない)
lib/                Ohana Staff(Flutter、職員向け)。bundle id com.ohanagroup.ohanaWorks。
                     lib/screens/childcare/ に保育業務Web相当のFlutter版画面あり(Web化は将来方針、原案の
                     childcare.ohanaworks.jp相当は現状 admin_web/childcare のみが実体)
lib/kiosk/           Ohana Kids(キオスク、Flutter、APP_MODE=kiosk)
parent_app/          Ohana Family(保護者向け、Flutter)
supabase/migrations/ マイグレーション本体(136番まで、admin_web配下に誤配置しないよう指示書§3.1で明記済み)
supabase/functions/  Edge Functions(Deno)
scripts/             給与関連CSV出力スクリプト(単発実行、Node)
```

原案が前提とする`admin.ohanaworks.jp`/`childcare.ohanaworks.jp`の2ドメイン運用は実在せず、admin_web 1本(ドメイン未取得)。指示書§2の整理と一致することを確認。

### 2) 職員・施設・園児・クラス・在籍・保護者のテーブル

| テーブル | 要点 |
|---|---|
| `offices` | 4施設(大和オハナ保育園、BABY MAHALO、Mahalo Station、Halelea)、削除せず履歴管理(`status`列) |
| `employees` | 55名(在職)。`position_id`列はあるが**全員null**(0.1参照) |
| `employee_office_assignments` | 兼務園を含む所属履歴(primary/concurrent) |
| `roles` / `employee_roles` / `role_permissions` | RBAC本体。**employee_rolesは1件のみ**(0.1参照) |
| `children` | 現状3件(テスト含む実質的にほぼ空、保育業務は本番未稼働) |
| `childcare_classes` / `child_class_enrollments` | 年度・クラス・在籍履歴。EXCLUDE制約で期間重複禁止(135番で追加) |
| `guardians` / `guardian_child_links` | 保護者ドメイン。3ドメイン分離(職員/保育業務職員側/保護者)は`manages_childcare()`系と`my_guardian_id()`系の完全独立関数群で維持 |

### 3) ロール・権限・施設スコープ・RLS

- 職員側: `my_employee_id()` → `manages_childcare(office_id)` / `has_childcare_office_access(office_id)` / `is_labor_manager_plus()` 等、用途別の判定関数を都度定義するパターン(汎用エンジンなし)。指示書D3の「機能別RPC+機能別RLS」踏襲方針と一致
- 保護者側: `my_guardian_id()` → `guardian_has_child_access(child_id)` 等。**直近の実バグ**(`20260714000098`でRLSが`guardian_id`一致から`guardian_has_child_access(child_id)`へ変更され、共同保護者間で紐付け行が相互に見えるようになった。フロント側が追従せずカード重複バグが発生、本セッションで修正済み)。**教訓**: RLSポリシーの変更はマイグレーション文面だけでなく`pg_policy`から実際の定義を都度確認すること(移行時に複数回、この食い違いで誤判断した)
- 監査: `log_event_change()`トリガーが多数のテーブルに一律適用され`event_logs`に記録。機微アクセスは別途`log_sensitive_access(action_label, target_id, target_summary)`(`sensitive_access_logging`、109番系)

### 4) 文書・添付・Storage・署名URL

Storageバケットは3つ、**すべて非公開**(`public: false`):

```
payslips           (給与明細PDF)
notice-attachments (お知らせ添付)
class-photos       (クラス写真)
```

署名URLはいずれも`createSignedUrl(path, 300)`(5分)で統一。原案§3.4「PDFや添付を公開URLにしない」は既に全面的に遵守されている。新機能もこのパターン(非公開バケット+5分署名URL)を踏襲すればよい。

### 5) 承認・差戻し・確定・版管理

汎用の承認エンジンは存在しない。個別実装例:
- 有給等の申請承認(`approve_paid_leave_request`等、個別RPC)
- 給与確定フロー(`confirm_payroll_run`、`draft/confirmed/transferred`的な状態遷移)
- 保育連絡帳の`draft/submitted/approved`(`child_personal_journals`、0.3で詳述)

「版・supersedes」方式の前例は今回調査した範囲では**見つからなかった**(改訂時に新版を作り旧版を残す設計は新規)。指示書D4の方針(version+supersedes_id、UPDATE経路を塞ぐ)は既存パターンの延長にはなく、新規に確立する必要がある。

### 6) 通知

`notifications`をoutboxとし、Edge Function `dispatch-pending-notifications`をpg_cron(`* * * * *`、毎分)が処理してFCM送信。既存4種の発火元(給与明細公開・申請結果・シフト変更・個別/グループ連絡、118〜121番)はいずれも業務RPCから直接`insert into notifications`する形。新機能の配布通知・期限アラートもこのパターンで行を積めば良い(指示書§2の記載と一致、追加調査での相違なし)。

### 7) AI Provider・AIログ・プロンプト

0.4で詳述。ゼロベース構築(指示書D5通り)。

### 8) PDF・Excel・Word・ZIP出力

| 形式 | 実装 | 場所 |
|---|---|---|
| PDF | `pdfkit`(Node)。`NotoSansJP`フォントを`fs.readFileSync`で読み込みカスタム登録。バッファ生成後Storageへアップロード+レスポンスとして直接返却 | `admin_web/src/app/api/payroll/payslip/route.ts`(Next.js API Route) |
| Excel | `exceljs`。**ブラウザ側(クライアント)で生成**しダウンロードさせる方式 | `admin_web/src/lib/export/*.ts`、`scripts/*.ts`(Node単体スクリプト) |
| Word | **実装例なし** |
| ZIP | **実装例なし** |

行政様式の複雑なレイアウト再現(セル結合・印刷範囲・改ページ)は`exceljs`で対応可能な範囲だが実績はない。Word生成・ZIP梱包は指示書D7が指摘する通り新規領域。日本語フォント埋め込みPDFの実績(pdfkit+NotoSansJP)は個別目標シート・架け橋PDFにそのまま転用できる。

### 9) 類似する既存機能と再利用候補

- `child_personal_journals`(0.3、最重要)
- `ai_style_profiles`(トーン設定のみ、AI Provider抽象化ではない)
- `childcare_office_settings`(施設単位の設定値パターン。年度単位の設定を持つ前例はないため、支援保育の「年度・期の開設状態」は新規テーブルが必要という指示書D6-3の判断は妥当)
- 給与確定フロー・有給申請承認(状態遷移+承認者記録の実装例として参照可能)

### 10) テスト、CI、環境分離

- `.github/`ディレクトリ**なし**。CI設定は存在しない
- `test/`ディレクトリはFlutterプロジェクト標準の空テンプレートのみ(実質未使用)
- ステージング環境は現状なし(指示書§5 Phase 0.5で導入決定済み、本報告と並行して着手可)

### 11) 職員・園児・施設・年度・記録から自動取得可能な項目

| 項目 | 取得元 | 備考 |
|---|---|---|
| 施設名・住所 | `offices` | |
| 職員氏名・職員番号・役職・所属・入社日 | `employees`, `employee_office_assignments` | **役職は0.1の通り現状取得不可**(未入力) |
| 園児氏名・生年月日・年齢・在籍 | `children`, `child_class_enrollments`, `childcare_classes` | 年齢クラス判定は既存の年齢区分ロジック(`age_group`列、実装済み)を流用可 |
| 保護者情報 | `guardians`, `guardian_child_links` | |
| 過去の連絡帳・個人日誌 | `family_daily_reports`, `child_personal_journals` | 0.3参照 |
| 進学予定小学校 | **存在しない**(`elementary_schools`等のテーブルは0件、要新規作成) |
| 関係機関マスタ | **存在しない**(要新規作成) |

### 12) 同一情報を複数画面・様式で重複入力している箇所

保育業務側は「家庭連絡帳」と「個人日誌(職員向け)」が同じ日次入力から**同時生成**される設計(`20260714000067`のコメント「連絡帳と同じ入力から職員向けの個人日誌を同時生成」)であり、二重入力を避ける設計が既に実践されている。新機能もこの「1回入力→複数文書へ反映」の考え方を踏襲すべき(原案§3.0・指示書D3のスナップショット方式と整合)。それ以外に明確な二重入力箇所は現状の保育業務範囲(まだ本番未稼働)では確認できなかった。

---

## 2. 差分表(原案§10.2 形式)

| 要求(原案) | 分類 | 根拠 |
|---|---|---|
| 施設マスタ・住所・連絡先の自動入力 | **既存のまま再利用** | `offices`テーブル |
| 職員氏名・所属・入社日の自動入力 | **既存のまま再利用** | `employees`, `employee_office_assignments` |
| 職員の役職(主任/園長等)の自動入力 | **新規(データ投入)** | `positions`0件、`employees.position_id`全員null。テーブル定義済みだが未入力。マスタ投入作業が必要(0.1) |
| 主任・園長・法人管理者への権限判定 | **新規** | `employee_roles`が実質空(0.1)。既存`roles`(director/chief/office_manager)は使えるが、実データ投入が前提 |
| 「施設長」ロール | **未確定** | 既存roleに直接対応なし(0.2)。付与テーブル方式を提案 |
| 承認ワークフロー共通部品 | **新規** | 汎用エンジンなし(D3方針通り、機能別実装) |
| 文書テンプレート版管理 | **新規** | `document_templates`相当のテーブルなし |
| AI Provider・AIログ | **新規** | 0.4参照 |
| 機能フラグ基盤 | **既存を拡張** | `feature_flags`/`feature_flag_office_overrides`あり。新規3キー追加のみ |
| 監査ログ | **既存を拡張** | `log_event_change`/`log_sensitive_access`をそのまま適用 |
| 通知 | **既存を拡張** | `notifications`outbox+`dispatch-pending-notifications`に業務RPCから行を積むだけ |
| Storage・署名URL | **既存のまま再利用** | 非公開バケット+5分署名URLのパターンをそのまま踏襲 |
| PDF生成 | **既存を拡張** | `pdfkit`+`NotoSansJP`のパターンを踏襲 |
| Excel生成 | **既存を拡張** | `exceljs`のパターンを踏襲(ただし複雑な行政様式再現は未検証、Phase 3で技術検証) |
| Word生成 | **新規** | 実装例なし |
| ZIP生成 | **新規** | 実装例なし |
| 日常の発達・支援記録 | **既存を拡張(スキーマは再利用第一候補、実データは0件)** | `child_personal_journals`のスキーマが部分的に該当(0.3)。実データ0件のため入力運用の確立が先に必要。個別支援計画・期別評価等の構造化項目は新規 |
| 進学予定小学校マスタ | **新規** | `elementary_schools`等なし |
| 関係機関マスタ | **新規** | `partner_agencies`等なし |
| 版管理(supersedes) | **新規** | 前例なし |
| ステージング環境 | **新規(導入決定済み)** | 指示書§5 Phase 0.5 |

---

## 3. 機微情報の権限表(ドラフト・要確認)

| 情報 | 対象機能 | 閲覧可能ロール(想定) | 経路 | 未確定点 |
|---|---|---|---|---|
| 職員の目標シート本文 | 個別目標シート | 主任以上(作成施設)、法人管理権限者(全施設) + 本人(配布後released分のみ) | 専用RPC(管理用/本人用を分離、指示書D2) | 「法人管理権限者」=system_admin想定でよいか要確認 |
| 園児の健康・配慮事項 | 架け橋・支援保育 | 園長、主任、法人管理者、個別指定職員 | security definerの最小列RPC(fetch_my_children_office_names方式を踏襲) | 「個別指定職員」の付与テーブルは新規設計が必要 |
| 支援保育の様式1・2本文 | 支援保育 | 支援児童確認担当者、主任、園長を含む複数名確認者 | 同上 | 「支援児童確認担当者」は年度・施設単位の付与(原案§11.4)、テーブル未設計 |
| 個人日誌(child_personal_journals) | 架け橋・支援保育のAI根拠 | 既存: 同施設職員+管理者(Tier1)、施設設定でadmin_onlyへ絞り込み可(Tier2) | 既存`fetch_personal_journal` | 架け橋・支援保育のAIがこれを根拠として参照してよいか(施設のadmin_only設定時の扱い含め)要確認 |

**注記**: 上表はドラフトであり、Phase 1着手前にユーザーの確認・修正を経て確定する(指示書§5 Phase 0の指示通り)。

---

## 4. 質問リスト(Phase 0で判明・未解決の確認事項)

1. **【最重要・作業前提・進行中】** 55名の職員について、主任・管理者・園長に相当する人を一覧化してご提供いただけますか。承認フロー関係者(数名〜十数名程度)分を先行提供いただく方針が決定済み(2026-07-29)。Phase 2の承認RLS検証は、そのリストが揃い次第着手する
2. **【新規発見・要確認】氏名の不一致**: 指示書§4-D2に記載の「施設長=高木俊」について、`employees`テーブルを`高木`で検索した結果、該当は`高木哲平`(職員番号0170、たかぎてっぺい)の1名のみで、「高木俊」という氏名の職員は存在しない。同一人物の表記違いか、別人(未登録)かの確認が必要。確認できるまでoffice_managerロールの付与を保留する
3. 指示書§6.2に記載の残る未確定事項(Anthropic Console契約名義、主任ステップの実運用、機微情報AI送信ポリシー等)は指示書側で既に整理されているため、本報告に重複記載しません

### 解決済み

- **`child_personal_journals`の活用可否**: 2026-07-29に実データ確認済み(§0.3、§6訂正履歴参照)。総件数0件のためスキーマの再利用可否のみ判定でき、「新規テーブルを作らず日常記録の実体として再利用する第一候補」で確定。分量・品質による設計変更の懸念は、実データが無いため現時点では発生しない(今後データが蓄積された段階で改めて確認が必要)
- **「施設長」の表現方法**: 2026-07-29決定。roleを経由せず、専用の承認者指定テーブルで直接指定する方式を採用(§0.2の追補)。ただし承認者指定は「誰が最終承認者か」のみを解決するため、編集権限(§4.3「主任・園長・法人管理者」)を持たせる場合は別途`employee_roles`への役職付与も必要(下記氏名確認後に対応)
- **`/hr/goal-sheets`の命名**: 2026-07-29決定。既存admin_webは`/childcare/contacts/copy`・`/notices/groups`のように既存の親ルート配下へ関連画面をネストする規則が一貫しており、新規`/hr`名前空間には前例がない。個別目標シートはHRドメインの一機能として`/employees/goal-sheets`に配置する

---

## 5. Phase 0 完了条件との対応

- 原案§10.1 12項目: 調査済み(§1)
- 原案§10.2 差分表: 作成済み(§2、ファイルパス・テーブル名を根拠に記載)
- 機微情報の権限表ドラフト: 作成済み(§3、要ユーザー確認)
- 未確定事項の質問リスト: 作成済み(§4)

**本報告の承認をもってPhase 0完了とし、承認前は実装(マイグレーション作成・コード変更)に入りません。**

---

## 6. 訂正履歴

### 2026-07-29: §0.3「日常記録の実在確認」を実データ確認により訂正

- **訂正前**: `child_personal_journals`のスキーマ調査のみに基づき、「原案の想定より状況が良い」「日常記録として実質的に最も近い」と評価していた
- **訂正内容**: ユーザー許可のもと読み取り専用(SELECTのみ)で実データを確認した結果、`child_personal_journals`は**総件数0件**(施設別・クラス別内訳、直近1年件数、content_support/content_consideration記入率、status分布、記入者傾向のいずれも算出不可)。保育業務全体が本番でまだ実質稼働前であることと整合する結果だった
- **訂正後の位置づけ**: `child_personal_journals`は実データ0件。ただしスキーマは支援内容・配慮事項・状態語彙を備えており、新規テーブルを作らず日常記録の実体として再利用する第一候補とする(§0.3、§2差分表を修正済み)
- **教訓**: スキーマの存在だけで「使える記録がある」と評価せず、実データの有無を確認するまでは暫定評価であることを明示する
