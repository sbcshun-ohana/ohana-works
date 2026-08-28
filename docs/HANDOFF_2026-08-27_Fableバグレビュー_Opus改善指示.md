# HANDOFF: Fableバグレビュー結果 → Opus改善指示(2026-08-27)

> **実行状況(2026-08-28)**: ✅ P1(1-1)・P2(2-1〜2-7)・P3(3-1〜3-5)すべて実装済み。
> 検証: admin `tsc --noEmit` PASS / Kids・parent_app `dart analyze` PASS。migration追加なし(全てコード修正)。
> **P4俊回答(2026-08-28)**: 4-3=理由は任意のまま(変更なし) / **4-4=外出中の小バッジ復活→実装済み**(board行・「外」後に戻り/降園なしの児に「外出中(HH:MM)」紫バッジ・出欠状況ベース) / 4-5=Kidsのみで運用(変更なし) / **4-8=園側記録+紙渡しで確定**(project_billing.md修正済み)。
> **4-1=解決(2026-08-28)**: 俊がstagingで実行 `count=0` → child_outings に未クローズの取り残しなし。**移行migration不要・切り捨て確定**。
> **実機確認3件=全解決(2026-08-28)**:
> ①保護者アプリの登降園実績クラッシュ = 週末行の Container(color+decoration併用) 326実装時からのバグ→修正済み。「取得失敗」= **RPC 326がstaging未適用だった**→俊が適用し完全動作(病欠/都合欠表示・2-1のキー修正も実機確認済)。catchに debugPrint 恒久追加。
> ②当日の外出中可視化(4-4) = 右側バッジ案から**タイムバーのセグメント色変え(青→外出で紫→戻りで青)+ラベル「外出中 HH:MM〜」**に俊指示で変更・実機確認済み。
> ③4-7 = **実害確定→修正済み**。attendance/page.tsx の内部コンポーネントをJSX要素から関数呼び出し展開に変更(再マウント解消)。備考欄の連続入力を実機確認済み。
> 残: 4-2(049コメント注記の可否)・4-6(旧315 RPCは旧ビルド淘汰後drop)= 低優先・記録のみ。

**発行**: Fable 5(4系統並列レビュー: DB/admin_web/Kids/横断回帰 + Fable本体でクロス検証済み)
**対象範囲**: 本日のコミット e25d7fe〜f67e513(migration 375-384・登降園/一時外出統合/休園日/帳票PDF/園内記録導線/請求Phase0)
**実行者**: Opus(このファイルの P1→P2→P3 の順に修正。P4は俊の判断待ち=勝手に実装しない)

## ワークフロー厳守事項(memory: feedback_implementation_workflow)
- migration新規は**採番385から**(380は意図的欠番・384まで適用済み)。
- migration作成→**Fableレビュー**(Agent, model:fable)→俊に**全文SQL提示**(省略・`...`禁止)→俊がSQLエディタで適用→**BEGIN/ROLLBACKのE2E**提示→結果確認。
- コード検証: admin=`cd admin_web && npx tsc --noEmit` / Kids=`dart analyze <files>`。
- コミットは俊の指示があってから。メッセージ末尾に Co-Authored-By 行。
- iPad再起動: `pkill -f "APP_MODE=childcare"; flutter run -d 863C8BA4-3D4D-4815-8A00-7AC5B9D0B5EF --dart-define=APP_MODE=childcare`(background実行+"Flutter run key commands"待ち)。

---

## P1: 出荷ブロッカー(最優先・即修正)

### 1-1. attendance-pdf のフォントが本番バンドルに入らず PDF が 500
- **file**: `admin_web/next.config.ts:13-16`
- **事象**: `outputFileTracingIncludes` に `/api/childcare/therapy-qr` と `/api/childcare/therapy-records-pdf` しか無く、本日新設の `/api/childcare/attendance-pdf`(`route.ts:9` で NotoSansJP-Regular.ttf を fs.readFileSync)が未登録。**Vercel本番でENOENT→500**(devでは再現しない)。過去に同種障害(コミット d91a315)の前例があり config コメントにも明記されている既知の罠。
- **修正**: `"/api/childcare/attendance-pdf": ["src/assets/fonts/**/*"],` を追加。
- **検証**: tsc + 該当行の目視。可能なら preview デプロイで PDF ボタン実打。

## P2: 機能欠陥(今回リリース範囲・コード修正のみ・migration不要)

### 2-1. 保護者アプリ: 病欠/都合欠が一度も表示されないキー不一致【326由来の既存バグ・実機未検出】
- **file**: `parent_app/lib/models/attendance_record_day.dart:28`
- **事象**: RPC 326(`fetch_guardian_attendance_month`)の返却キーは **`absence_kind`**(RETURNS TABLE の OUT列名がJSONキー)。モデルは `m['attendance_kind']` を読むため**常にnull** → `attendance_record_screen.dart:60,69-71` の「病欠/都合欠」ラベル・色分けが一度も発火せず常に汎用「欠席」。
- **修正**: `absenceKind: m['absence_kind'] as String?,` に変更(1行)。
- **検証**: parent_app を `dart analyze`。実機確認は俊の登降園実績画面で病欠日を表示。

### 2-2. 監査履歴モーダルに外出理由(outing_reason)が出ない【DB/adminの2系統レビューが独立に同一指摘】
- **file**: `admin_web/src/app/childcare/attendance/page.tsx:67`(AUDIT_FIELDS)+ `fmtAuditVal`
- **事象**: 381で `child_attendance_events.outing_reason` が追加され Kids が理由を保存するが、AUDIT_FIELDS に列が無く「理由を療育→健診に変更」等が履歴に一切表示されない(時刻だけの取消/登録に見える)。
- **修正**: `child_attendance_events` 配列に `["outing_reason", "外出理由"]` を追加。`fmtAuditVal` の `if (key === "reason")`(therapy/checkup/otherマップ)を `key === "reason" || key === "outing_reason"` に拡張。
- **検証**: tsc。実機: Kidsで理由を変更→adminの「履歴」で「外出理由: 療育 → 健診」が出ること。

### 2-3. Excel出力が出力監査(379)に記録されない
- **file**: `admin_web/src/app/childcare/attendance/page.tsx` `onExport()`(238行付近)
- **事象**: `log_report_output` はPDF経路(281)のみ。379は `format check in ('pdf','csv','xlsx')` でxlsx記録を明確に想定(§7出力監査)。
- **修正**: `onExport()` の3分岐それぞれのExcel生成後に `log_report_output` を呼ぶ。`p_format:'xlsx'`、`p_report_type` は `attendance_register`(出欠)/`attendance_time`(時刻)/`attendance_child`(園児別)。`p_params:{year,month}`(園児別は child_id も)。`selectedOffice` 空ガードも追加(P3-4と共通)。ReportLogsModal の `REPORT_TYPE_LABEL` にも `attendance_time: "登降園時刻表"` / `attendance_child: "園児別実績"` を追加。
- **検証**: tsc。Excel出力→出力履歴モーダルに xlsx 行が出ること(俊のstaging実機)。

### 2-4. 主任(chief)が出力履歴を開くと権限エラーが「履歴はありません」に化ける
- **file**: `admin_web/src/app/childcare/attendance/page.tsx` `openReportLogs`(249-255)+ ReportLogsModal
- **事象**: `fetch_report_output_logs` は管理者以上(chief不可・379仕様)。chiefで押すとRPCエラー → `setErr`(赤帯はモーダル**背後**)+`setReportLogs([])` → モーダル内「出力履歴はありません。」と誤表示。
- **修正**: ReportLogsModal 用のエラーstate(例 `reportLogsErr`)を追加し、権限エラー時はモーダル内に「出力履歴の閲覧は管理者以上です」等を表示(`err.message` に 'not authorized' 含む場合の分岐で可)。ページ側 `setErr` はこの経路では使わない。
- **検証**: tsc。chiefロールで実機確認(staging: テスト主任アカウント)。

### 2-5. AppHeader「保育業務」入口が attendance ゲート素通し+一般職員に赤帯
- **file**: `admin_web/src/components/AppHeader.tsx:61-63` および isActive 判定(`item.href === "/childcare/attendance"` 比較箇所)
- **事象**: ChildcareNav は `attendance_mgmt_enabled` で登降園管理を隠すが、ヘッダー「保育業務」は無条件で `/childcare/attendance` へ。①フラグOFF施設でゲートバイパス ②一般職員が押すと `fetch_attendance_matrix_for_office`(主任以上)のエラー赤帯が最初に見える。
- **修正**: 入口を `{ href: "/childcare/daily-board", label: "保育業務" }` に変更し、isActive 判定の比較値も `/childcare/daily-board` に合わせる(「/childcare 配下でアクティブ・重要事項説明書除外」のロジックは維持)。
- **検証**: tsc。保育業務タブ→デイリーボード着地・タブのアクティブ表示が全 /childcare 配下で維持されること。

### 2-6. 出席簿PDF: 「都合欠」がセル幅(18pt)に収まらず行重なり
- **file**: `admin_web/src/app/api/childcare/attendance-pdf/route.ts`(kindLabel/registerSymbol・cell)
- **事象**: 「都合欠」(size7で約21pt)が折返し → rowH=15 を超過して次行と重なる。ページ最下行では pdfkit 自動改ページが発火し以降の座標が崩れる。
- **修正**: PDFの registerSymbol を画面と同じ**1文字**(「病」「都」、種別未設定は「欠」)に変更し、タイトル下に凡例「◯=出席 病=病欠 都=都合欠」を1行追加。
- **検証**: tsc + Nodeスモーク(既存の scratchpad/pdf_smoke.js 方式)。都合欠を含む月で目視。

### 2-7. 実績表PDF: pageGuard 余白不足で見出し孤立/座標崩れ
- **file**: `attendance-pdf/route.ts:146,154-158`
- **事象**: `y > height-40` では園児見出し(rowH+2)+表ヘッダ(rowH)≈34pt を保証できず、境界で孤立ヘッダや pdfkit 自動改ページとの desync。
- **修正**: グループ開始前(見出し描画前)のガードを `y > doc.page.height - 90` に強化(ループ内の行ガードは現状維持)。
- **検証**: 同上スモーク+多人数月の目視。

## P3: UX改善(小・まとめて1コミットで可)

### 3-1. Kids: 狭幅(<800px)で園内記録に到達できない
- **file**: `lib/screens/childcare/contacts/daily_contact_list_screen.dart:146-148` 付近(非splitの onTap)
- **事象**: 非split時は一覧タップ→`DailyContactDetailScreen`(連絡帳のみ・タブ無し)へ直遷移し `initialTab:'internal'` が捨てられる。Split View 等でホーム/ボードの園内記録入口が機能しない。
- **修正**: 非split かつ `widget.initialTab=='internal'` のときは `ChildInternalNotesTab` を Scaffold(AppBar=園児名)で包んだ画面へ push する分岐を追加(新規画面クラスは同ファイル内プライベートで可)。
- **検証**: dart analyze。シミュレータの幅を狭めて確認。

### 3-2. Kids: 外出理由プリフィルの競合ガード
- **file**: `lib/screens/childcare/daily_board/daily_board_screen.dart` `_AttendanceEditSheet.initState`(1964-1968付近)
- **修正**: `.then((r) { if (mounted && _outingReason == null) setState(() => _outingReason = r); })` — ユーザーが先にチップを選んだ場合に遅延fetchで上書きしない。

### 3-3. Kids: 'other' 理由がフラグOFF施設で選択表示されない
- **file**: 同ファイル 理由チップ構築(2092-2097付近)
- **修正**: チップ配列を `(_outingOtherEnabled || _outingReason == 'other') ? ['therapy','checkup','other'] : ['therapy','checkup']` に。

### 3-4. admin attendance: 出力まわりの小ガード3点
- **file**: `admin_web/src/app/childcare/attendance/page.tsx`
- (a) `openReportLogs`/`onExportPdf`/`onExport` の冒頭に `if (!selectedOffice) return;`
- (b) 年月切替中(rows再取得中)の出力ボタン disabled(取得中フラグを立てる or busy を fetch にも適用)
- (c) closures/openDays RPC の error を握りつぶさず `setErr`(151-169付近)
- **検証**: tsc。

### 3-5. AuditModal: 追跡外列のみの変更で空行に見える
- **file**: 同ファイル `auditDetail`(87-105付近)
- **修正**: `diffs.length === 0 && row.action === "UPDATE"` のとき「(詳細対象外の変更)」を1行表示。

## P4: 俊の判断が必要(**勝手に実装しない** — AskUserQuestionで確認してから)

| # | 論点 | 背景 | 選択肢 |
|---|---|---|---|
| 4-1 | **child_outings の取り残しデータ** | 381にバックフィル無し。適用時点で未クローズの旧一時外出が存在すると、どこにも表示されず・クローズ手段も無い(監査履歴でのみ閲覧可) | まず staging/本番の `select count(*) from child_outings where return_at is null and not converted_to_departure;` を俊に実行依頼 → 0件なら「切り捨て確定」を記録のみ / 残件ありなら out/return イベント+outing_reason への一括変換 migration(385) |
| 4-2 | **383の意味混在(銀行休業日)** | `is_bank_business_day`(049)が `year_end_new_year` を休業扱い → 12/29・30(実際の銀行は営業日)が休業扱いに。現行の唯一の利用経路(給与振込日25日→前営業日繰上げ)では実害ゼロ(検証済)だが時限バグ | (a) 049にコメント注記のみ(推奨・低リスク) (b) holiday_type を分離する migration |
| 4-3 | **外出理由の必須化** | 現状 null 許容(理由未選択で外時刻のみ保存可能) | 現状維持(null=理由不明を許容) / Kids保存時に必須バリデーション |
| 4-4 | **当日中の「外出中」可視性** | 315バッジ廃止により、外出中の児がボード上「在園中」のまま(検知は翌日以降のアラートのみ)。俊指示どおりの帰結だが安全面の再確認 | 現状維持 / ボード行に「外(時刻)」の小バッジを out イベントから復活(child_attendance_events ベースなら軽実装) |
| 4-5 | **admin からの外出理由入力** | 理由チップは Kids のみ。admin で新規に「外」を入れると理由 null(既存理由は coalesce で保全) | Kidsのみで運用 / admin daily-board・attendance の編集にも理由セレクト追加 |
| 4-6 | **315 書き込み系RPCの無効化** | `start_child_outing` 等が grant 付きで残置。未更新の旧iPadビルドが呼ぶと「見えない外出記録」になる | 旧ビルド淘汰後に drop / いま例外throwへ差し替え(migration 385系) |
| 4-7 | **DayView入れ子コンポーネントの再マウント** | attendance/page.tsx のビュー群が親関数内定義=1打鍵ごと再マウント構造(314由来の既存)。備考・時刻入力のフォーカス喪失の**疑い**(実機未確認) | まず俊のstaging実機で「日別ビューの備考欄に連続入力できるか」を確認 → 問題あればトップレベル関数化のリファクタ |
| 4-8 | **一時預かり児の連絡帳の方針矛盾**(billingメモ済) | 2026-08-14「保護者にも公開」vs 2026-08-27「園側記録+紙渡し」 | どちらが最終か俊確認 → project_billing.md を修正 |

## 参考: 性能系(急がない・記録のみ)
- 378 監査RPC: event_logs の jsonb 全走査。運用年数で劣化 → 将来 `create index on event_logs (target_type, (coalesce(after_data->>'child_id', before_data->>'child_id')))` の式インデックス。
- 378 表示順: 同一tx置換が「登録→取消」の逆順に見えることがある(uuid タイブレークの限界・表示のみ)。
- 381 未クローズ遡及が7日限定(316は無制限)= 意図的な性能フィルタ。8日超の未クローズは自動消滅する挙動変化として記録済み。

## レビューで「問題なし」を確認済みの主要項目(再調査不要)
- 381: 感染症ゲート(212)一字一句保持 / 理由coalesce据置の全ケース / daily_child_status・FK無干渉 / 314・317無影響 / 廃止RPCのクライアント参照ゼロ / cron差し替え正当
- 383: holidays 参照は 049・338・370・375 のみ。338/370(給食cron)は12/29-30スキップ=意図どおりの是正。edge functions 参照ゼロ
- 保護者アプリへの理由露出なし(326は outing_reason を返さない)/ キオスクQR系(171含む)無影響
- 384: スキーマ実在・読み取り専用・v1制限はコメント明記済み
- ソースコードの未コミット差分ゼロ(docs 5点と parent_app pod系のみ未追跡/未ステージ=対象外)

## 完了条件
1. P1・P2 を修正 → tsc / dart analyze / PDFスモーク PASS → 俊確認 → コミット(P1は単独コミット推奨)。
2. P3 をまとめて修正 → 同上。
3. P4 を AskUserQuestion で俊に確認 → 決定に従い実装 or 記録。
4. 本ファイルの各項目に完了マークを付けて更新し、memory(project_attendance_mgmt / project_billing)へ反映。
