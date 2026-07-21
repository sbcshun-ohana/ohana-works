# Ohana Works 開発状況報告書

作成日: 2026-07-21
対象: 現リポジトリのソースコード実態調査に基づく実装状況(設計書ではなく実装済み範囲のみを記載)

対象コードベース:
- `lib/`(リポジトリルート、Flutterプロジェクト名`ohana_works`) — **職員アプリ**。`--dart-define=APP_MODE=`で3フレーバーをビルド分岐する単一コードベース(`staff`=職員個人向け / `kiosk`=施設iPad勤怠・登降園キオスク / `childcare`=保育業務専用iPad)
- `admin_web/`(Next.js 16 / React 19) — **管理者Web**
- `parent_app/`(独立したFlutterプロジェクト) — **保護者アプリ**
- `supabase/`(115マイグレーション) — バックエンド(Postgres/RLS/RPC/Edge Functions)

---

## 1. 全体概要

### 現在完成している機能
- 職員の勤怠打刻(QR表示・キオスク打刻・代理打刻)一式
- 職員の各種申請(有給・欠勤・遅刻早退・登録情報変更)と承認フロー
- 有給自動付与・月次勤怠集計(管理者エンジン)
- 給与計算エンジン・振込一覧Excel・給与明細PDF発行・施設別給与Excel(admin_web)
- 職員マスタ・給与関連CSV一括取込(10種類、admin_web設定画面)
- お知らせ機能(既読管理・添付・返信・配信対象分析)
- 保育業務: デイリーボード・当日欠席選択・クラス活動記録・連絡帳入力/承認・保護者管理(職員側+admin_web側)
- 保護者アプリ: メール/Apple/Googleログイン、招待受諾、園児一覧、登降園QR、家庭連絡帳、園連絡帳(本文/お知らせ分割済み)、保護者からの申請・連絡、クラス写真
- 監査ログ基盤(`event_logs`への自動記録、ただし閲覧UIは未実装)

### 開発中の機能
- 保護者アプリ全体(このセッションで継続的に機能追加中。ホーム画面グリッド化、保護者申請の項目再編など直近も変更あり)
- 連絡帳AI生成のバックエンド接続(モック動作中、実API呼び出しは未実装)
- 全銀協フォーマット振込CSV(出力ロジックはあるが銀行仕様の最終確認待ち、アプリ内でも「ベストエフォート出力」と明記)

### 未実装機能
- 職員個人の給与明細セルフビュー・勤怠履歴セルフビュー(現状は管理者向け一覧のみ)
- プッシュ通知のDBトリガーからの自動送信(送信基盤自体はあるが、自動起動する仕組みがほぼ無い)
- 監査ログ(`event_logs`)の閲覧UI
- 身体測定・発達記録・保育料プラン・曜日別登降園設定・台帳詳細(保育業務、意図的に将来フェーズ送り)
- ヒヤリハット・週案/月案/年間計画(指示書スコープ外として明記)

---

## 2. 共通基盤

### 認証
- Supabase Auth(email/password)を職員・保護者共通の認証基盤として使用
- **職員**: `employees.auth_user_id → auth.users`。DBトリガーによる自動プロビジョニングは無く、admin_webのCSV一括取込(`import_employees_csv`)等で既存authユーザーとemployee行を紐付ける運用
- **保護者**: `guardians.auth_user_id → auth.users`。招待コード方式(`accept_guardian_invitation` RPC)でアカウント作成。ログイン手段はメール/パスワード・Sign in with Apple・Google Sign-In(いずれもparent_appに実装済み、直近セッションでApple/Google追加)
- 職員・保護者は完全に独立したID空間(同一`auth.users`テーブルだが紐付けカラム・RLS関数系列が別)

### Supabase
- `supabase/config.toml`はリポジトリに存在せず、プロバイダ設定等はダッシュボード側で管理
- 115マイグレーションが適用済み(直近の作業は保護者アプリ基盤に集中)
- Edge Functions 9本(打刻QR発行/解決、登降園QR発行/解決、代理打刻、デバイスペアリング、プッシュ送信、AI連絡帳生成)

### DB
- 詳細は「11. データベース」参照。ドメイン別(職員基盤/勤怠/給与/保育業務/保護者/通知・監査)に整理された約90テーブル超

### 権限
- 3ドメインに意図的に分離されたRLS権限モデル(コード内コメントで明記):
  1. **職員業務(給与・勤怠)ドメイン**: `my_employee_id()` / `is_labor_manager_plus()` / `manages_office()`
  2. **保育業務ドメイン**: `manages_childcare()` / `has_childcare_office_access()` / `has_childcare_class_access()`(労務管理者ロールは意図的に除外)
  3. **保護者ドメイン**: `my_guardian_id()` / `guardian_has_child_access()` / `guardian_is_primary_for_child()` + 職員が保護者データを見るためのブリッジ関数(`staff_has_guardian_data_access()`等)
- ドメイン間で互いのテーブルを参照しない設計がSQL関数レベルで強制されている

### 通知
- **アプリ内お知らせ**: 職員アプリで完成(既読・添付・返信・配信対象分析)
- **プッシュ通知**: `push_device_tokens`テーブル + `send-push-notification` Edge Function(FCM HTTP v1、実装済み)は存在するが、**DBトリガーから自動起動する仕組みはほぼ無い**(唯一`resolve-guardian-qr`内で家庭連絡帳未提出時のプッシュを直接送信する箇所のみ確認)。他はクライアント側からの明示呼び出しに依存していると推測(職員アプリのlib/には呼び出し箇所なし)
- 保護者の通知設定(`guardian_notification_settings`)によるオプトアウトと、緊急系カテゴリの強制配信(`FORCE_DELIVER_CATEGORIES`)の仕組みは実装済み

### ログ
- `log_event_change()`トリガー関数による`event_logs`への自動記録(職員・給与・勤怠・保育業務・保護者関連の主要テーブルに適用済み)
- 機微情報アクセス専用の`sensitive_access_logs`テーブルは存在するが、記録用トリガー/関数は未確認(要フォローアップ)
- **admin_web側に監査ログ閲覧画面は無い**(記録のみでUIが無い状態)

---

## 3. 職員アプリ(staff/kioskフレーバー)

### 実装済み画面
- ログイン画面、ホーム画面(作者コメントで「仮のホーム画面」と明記された最小構成)
- 勤怠QR表示画面(90秒〜8時間有効、Realtime連携で自動更新)
- 各種申請メニュー・有給休暇申請・欠勤連絡・遅刻早退申請・登録情報変更申請・申請履歴
- 承認待ち申請一覧・承認詳細(管理者)
- 月次勤怠集計・結果閲覧(管理者)
- 給与計算画面・給与実行結果一覧(管理者、全職員分の内訳閲覧)
- 有給自動付与画面(管理者)
- お知らせ一覧・詳細・配信対象分析(管理者)
- **キオスク(iPad)**: デバイスペアリング、スキャン待受画面、打刻確認、代理打刻、打刻成功、登降園結果表示 の6画面

### 実装済み機能
- QRベースの職員打刻(発行→キオスクでの解決→確認の2段階フロー)、代理打刻(PIN認証)
- 有給残高照会・時間単位有給の年5日上限チェック等の業務ルールをクライアント側でも検証
- 給与計算RPC実行・結果閲覧(ロック/振込CSV/PDF発行/通知は明示的にスコープ外とコメントあり、それらはadmin_web側で実現)

### 未実装
- 職員個人の「自分の勤怠履歴」「自分の給与明細」セルフビュー(現状は管理者向け集計・一覧のみ)
- プッシュ通知(Firebase依存が職員アプリに一切無い。お知らせは全てアプリ内プル型)

---

## 4. 保育業務アプリ(childcareフレーバー、iPad専用)

### 実装済み画面
- 保育業務メニュー(施設・対象日選択付き)
- デイリーボード(在園状況、Realtime同期)
- 当日の欠席選択(クラス別園児一覧)
- クラス活動 一覧・詳細(入力→提出→承認/差戻し)
- 連絡帳 一覧・詳細(本文・個別お知らせ・備品利用・AI生成/編集・提出→承認/差戻し)
- 承認済み連絡帳コピー画面(外部システム/コドモンへの転記用)
- 保護者管理画面(招待発行・アカウント停止/再開)

### 実装済み機能
- クラス活動・連絡帳の下書き→提出→承認/差戻しワークフロー(担当者アサイン・再アサイン含む)
- 個別お知らせ・備品利用のチェック管理
- 承認済み連絡帳のクリップボードコピー+コピー済みマーク

### 未実装
- **連絡帳AI生成の本番実装**: `ANTHROPIC_API_KEY`未登録のためモック文言(「【AI生成(モック)】」等)を返す状態。実API呼び出し部分は`throw Error("Anthropic API呼び出しは未実装です")`のまま
- 身体測定・発達記録・保育料プラン・曜日別登降園設定・台帳詳細(テーブル自体未作成、将来フェーズ)
- ヒヤリハット・週案/月案/年間計画

---

## 5. 管理者Web

### 実装済み画面
- ログイン、勤怠(`/attendance`)、給与(`/payroll`)、職員(`/employees`)、設定(`/settings`)
- 保育業務: 出欠(`/childcare/attendance`)、クラス活動(`/childcare/class-activities`)、クラス写真(`/childcare/class-photos`)、連絡帳(`/childcare/contacts`、コピー用画面含む)、デイリーボード(`/childcare/daily-board`)、緊急連絡先(`/childcare/emergency-contacts`)、保護者管理(`/childcare/guardians`)、保護者からの申請(`/childcare/parent-requests`)

### 実装済み機能
- 勤怠修正・月間Excel出力、給与ロック連動
- 給与計算単位管理・確定・振込済みマーク・確定解除(要理由入力)、施設別給与Excel、振込一覧Excel、**全銀協フォーマットCSV出力(「ベストエフォート出力」と明記、銀行仕様の最終確認待ち)**、給与明細PDF発行(pdfkit、API Route経由)
- 職員の源泉徴収区分・社保/所得税扶養人数管理
- CSV一括取込10種(源泉税額表・職員マスタ・施設別基本給・通勤費・週所定労働時間・施設別手当・源泉徴収区分/扶養・標準報酬月額・保険加入状況・住民税)、いずれもプレビュー→エラー/警告表示→明示的な確定操作の設計で「自動確定は行わない」ことがUI文言で明記
- 保護者招待発行・アカウント停止再開、保護者申請の承認/差戻し

### 未実装
- 監査ログ閲覧画面(`event_logs`を見るUIが無い)
- サーバーサイドAPI Routeは給与明細PDF発行の1本のみ(他は全てSupabaseへの直接呼び出し)

---

## 6. 保護者アプリ

### 実装済み画面
- ログイン(メール/パスワード・Apple・Google)、招待コード入力
- ホーム(園児一覧)、園児詳細(グリッドメニュー、直近セッションで6項目に再編: 登降園QR・保護者からの申請・連絡・ご家庭からの連絡帳・保育園からの連絡帳・保育園からのお知らせ・クラス写真)
- 登降園QR表示
- 家庭連絡帳(当日入力)・履歴一覧
- 保育園からの連絡帳 一覧・詳細(個別お知らせは別画面に分離済み)
- 保育園からのお知らせ 一覧・詳細
- 保護者からの申請・連絡 一覧(種類別アイコン表示)・新規作成・詳細(職員とのやりとり付き)
- クラス写真一覧

### 実装済み機能
- Apple/Google/メールでのサインイン、招待コード受諾によるアカウント作成
- 家庭連絡帳: 体温(0.1℃刻みプルダウン)・検温時刻(時/分プルダウン)入力、37.5℃以上警告、0〜2歳児クラスのみ「自宅での様子」入力必須化(クラスage_group文字列から正規表現で年齢抽出)
- 園連絡帳の既読管理(`communication_book_reads`)に基づく未読バッジ(本文・お知らせで赤丸バッジ、0件は非表示。既読管理は連絡帳1行単位で本文・お知らせ共有)
- 保護者申請: 欠席・遅刻・早退・お迎えの方の変更・その他連絡(感染症は独立種類を廃止し欠席のチェックボックス+感染症マスタ複数選択に統合、直近マイグレーションで本番反映済み)

### 未実装
- 実際のGoogleアカウント・Appleアカウントを使った本番E2E認証フローの実機確認(モックでのUI確認は実施済みだが実アカウントでの完走確認は未実施)
- プッシュ通知の受信側実装状況は本報告書の調査範囲外(要確認)

---

## 7. 勤怠管理

- **打刻方式**: 職員個人はスマホでQRを表示するのみ。実際の打刻はキオスク(iPad)側で完結(発行→解決→確認の2段階、Realtime連携)。代理打刻(PIN認証)もキオスク側に実装済み
- **修正・承認**: admin_webの`/attendance`で実打刻時刻と承認時刻を並べて修正可能、月間Excel出力あり
- **月次集計**: 職員アプリの管理者向け画面からRPCを手動実行し、`attendance_summaries`に反映(残業・深夜・欠勤・遅刻等を集計)
- **給与ロック連動**: 給与確定(`payroll_runs.status`が`confirmed`/`transferred`)済み月は勤怠修正がロックされ、admin_web側でその旨を案内
- **職員個人のセルフ勤怠履歴閲覧機能は無い**

---

## 8. 給与計算

- **計算エンジン**: 職員アプリからRPC(`run_payroll`)を手動実行、`payroll_runs`/`payroll_details`に格納。基本給・各種手当・残業/深夜/休日割増・社保/所得税/住民税控除・借上宿舎控除など多数の控除項目に対応
- **確定・出力**: admin_webの`/payroll`で確定・振込済みマーク・確定解除(要理由・システム最高管理者限定)、施設別給与Excel、振込一覧Excel(銀行情報欠落者を赤字ハイライトし合計から除外)、全銀協CSV(ベストエフォート、銀行仕様の最終確認待ち)、給与明細PDF発行(API Route + pdfkit、Supabase Storageへ保存)
- **CSVマスタ取込**: 源泉税額表・週所定労働時間(社保加入判定用)・施設別基本給/手当/通勤費・扶養人数・標準報酬月額・保険加入状況・住民税、計10系統がadmin_webの設定画面で完備
- **職員個人の給与明細セルフビューは無い**(admin_webでPDF発行はできるが、職員本人が自分のスマホで見る画面は未確認/未実装)

---

## 9. 園児管理

- `children`(園児マスタ)・`childcare_classes`(クラス、`age_group`はフリーテキスト、CHECK制約なし)・`child_class_enrollments`(在籍履歴)
- 当日出欠(`child_daily_attendance`/`daily_child_status`)、登降園イベント(`child_attendance_events`)、出席修正(`child_attendance_corrections`)
- 連絡帳関連(`child_daily_contacts`とその拡張・個別お知らせ・備品利用)、クラス活動記録、クラス写真
- 職員内部向け個人記録(`child_personal_journals`)は保護者向け連絡帳と別テーブルで分離
- **園児の新規登録を行うadmin_web/職員アプリ画面は現状無い**(過去のセッション調査で確認済み。SQL直接投入が必要)
- 身体測定・発達記録・保育料プラン等は指示書上も今回のフェーズでは意図的にテーブル未作成

---

## 10. AI機能

- `generate-contact-note` Edge Functionが連絡帳AI生成・編集(短縮/加筆/柔らかく/配慮追加/明確化/再生成)の入口として職員アプリ(保育業務フレーバー)から呼び出される設計は完成
- **`ANTHROPIC_API_KEY`が未登録のため常にモック応答**(「【AI生成(モック)】」等の固定文言)を返す
- 実際のAnthropic API呼び出しロジックは未実装(コード内に「未実装」の例外がそのまま残る)
- `ai_style_profiles`テーブル(施設/クラス単位のAIトーン設定)は存在するが、実生成に接続されていないため実質未使用

---

## 11. データベース

### 作成済みテーブル(ドメイン別、主要なもの)
- **認証・職員基盤**: employees, employee_roles, roles, role_permissions, employee_office_assignments, employee_class_access, offices, positions, job_types, employment_types, employee_contacts, emergency_contacts, dependents, my_numbers, tax_withholding_statuses, devices
- **勤怠管理**: time_punches, daily_attendances, attendance_segments, attendance_summaries, attendance_summary_runs, attendance_approvals, shifts, shift_change_requests/approvals/logs, fixed_shift_patterns, qr_tokens, proxy_punches, requests, holidays, weekly_scheduled_hours, leave_grants, leave_grant_runs, leave_usages, disaster_events/responses
- **給与計算**: wage_masters, employee_allowances, allowance_masters, special_duty_allowances, payroll_runs, payroll_details, payroll_run_issues, payslips, bank_accounts, bank_transfer_accounts/files, insurance_enrollments, insurance_rate_tables, standard_monthly_remunerations, resident_taxes, withholding_tax_tables, commute_masters, company_housing_settings/deductions, burden_fee_masters/records, file_import_logs
- **保育業務・園児管理**: children, childcare_classes, child_class_enrollments, child_daily_attendance, daily_child_status, child_attendance_events/corrections, child_daily_contacts(+拡張3テーブル), class_daily_activities, child_contact_assignments, class_daily_photos, child_personal_journals, ai_style_profiles, individual_notice_masters, infectious_disease_masters, notices, notice_recipients/attachments
- **保護者アプリ基盤**: guardians, guardian_child_links, guardian_permissions, guardian_invitations, guardian_account_actions, guardian_emergency_contacts, guardian_notification_settings, guardian_qr_tokens, family_daily_reports(+revisions), parent_requests(+messages/revisions), communication_book_reads/confirmations
- **通知・監査**: push_device_tokens, notifications, notification_templates, alert_rules, alerts, feature_flags(+overrides), event_logs, sensitive_access_logs, audit_documents

### 未作成テーブル
- 園児の身体測定・発達記録
- 保育料プラン・曜日別登降園設定
- 台帳詳細(指示書で明示的に将来フェーズ送り)
- ヒヤリハット記録
- 週案・月案・年間指導計画
- 職員個人の給与明細/勤怠を保護者アプリ的なセルフビューで見せるための専用集計テーブル(現状はpayroll_details/attendance_summariesを管理者が横断的に見る設計のみ)

---

## 12. API

RPC(Postgres関数)・Edge Functionsとも大半が実装済み。REST的な独自API RouteはNext.js側に1本のみ(`/api/payroll/payslip`)、他は全てSupabaseクライアント(RPC/PostgREST)経由。

### 完成
- 打刻系Edge Functions(issue-qr-token, resolve-qr-punch, confirm-punch, proxy-punch, pair-device)
- 登降園系Edge Functions(issue-guardian-qr-token, resolve-guardian-qr — 家庭連絡帳未提出時のゲート・プッシュ送信込み)
- send-push-notification(FCM HTTP v1、送信ロジック自体は完成)
- 給与・勤怠・保育業務・保護者ドメインの主要RPC群(CSV取込10種、承認系、招待系、未読集計等)
- 給与明細PDF発行API Route

### 未完成
- `generate-contact-note`のAI実呼び出し部分(モックのまま)
- プッシュ送信の自動トリガー(DB側からの自動起動経路がほぼ無く、`resolve-guardian-qr`内の直接呼び出し以外は未確認)
- 全銀協CSV出力の銀行仕様最終検証(ロジックはあるが「ベストエフォート」)

---

## 13. 今後実装予定(優先順位付き)

1. **連絡帳AI生成の本実装**(`ANTHROPIC_API_KEY`登録+Anthropic API呼び出しロジック実装) — 保育業務アプリの中核価値のため最優先
2. **全銀協CSVの銀行仕様最終確認**(実際の振込に使う前に横浜銀行仕様との整合を検証) — 実損失リスクがあるため優先度高
3. **保護者アプリの実アカウントでのE2E確認**(実Google/Appleアカウントでのサインイン〜招待受諾〜各機能の完走テスト)
4. **プッシュ通知の自動送信トリガー整備**(現状ほぼ手動/限定的な自動化のみ。連絡帳承認・お知らせ配信・申請承認等での自動配信を検討)
5. **監査ログ(`event_logs`)閲覧UIのadmin_web実装**
6. **職員個人向けセルフビュー**(自分の勤怠履歴・給与明細をスマホで確認できる画面)
7. **園児登録UI**(現状SQL直接投入のみ。admin_webまたは職員アプリでの園児新規登録画面)
8. **身体測定・発達記録・保育料プラン等の将来フェーズ機能**

---

## 最後に:現在の完成率(概算)

コード実態(TODOコメント・モック・未実装例外の有無)ベースの概算。設計書に対する充足率ではなく、「作られている部分がどれだけ動く状態か」の目安です。

| 領域 | 完成率(概算) | 備考 |
|---|---|---|
| 共通基盤(認証・DB・権限・監査記録) | 約95% | 監査ログ閲覧UIのみ欠落 |
| 職員アプリ(staff/kiosk) | 約90% | 個人セルフビュー(勤怠/給与)が無い以外はほぼ完成 |
| 保育業務アプリ(childcare) | 約80% | AI生成が丸ごとモックのため、この一点が大きく完成率を下げている |
| 管理者Web | 約90% | 監査ログUI・全銀協CSV最終検証待ちを除きほぼ完成 |
| 保護者アプリ | 約80% | 機能自体は広く揃っているが、実アカウントでの本番E2E確認が未実施 |
| 通知基盤 | 約50% | 送信ロジックはあるが自動トリガーがほとんど無い |
| AI機能 | 約20% | 呼び出し口はあるが実装は完全にモック |

**全体の概算完成率: 約80%**

主要業務(勤怠・給与・保育業務・保護者連携)の「箱」と主要フローはほぼ全て実装済みで、残るギャップは (a) AI連絡帳生成の実API接続、(b) 通知の自動化、(c) 一部管理UI(監査ログ・園児登録)、(d) 保護者アプリの実機E2E確認 に集約されます。
