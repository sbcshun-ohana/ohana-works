# Ohana Works 園内記録機能 実装設計書 v2

作成日: 2026-07-30
対象読者: **実装を担当する Claude Code(Sonnet/Opus)**。本書は実装指示書として読めるように書かれている。
前提資料: `Ohana_Works_追加機能_実装指示書_v1_2026-07-28.md`(既存の規約・環境情報はそちらに従う)
ステータス: **俊さんの承認待ち。§12「判断待ち事項」が解決するまで Phase B 以降に着手しないこと。**

---

## 1. この機能が何であるか(1段落で)

園児1人ひとりについて、職員だけが読み書きできる時系列の記録(「園内記録」)を新設する。保護者アプリには**一切**表示しない。用途は園内の申し送り・経過観察の蓄積であり、将来的に支援保育事業(Phase 3)の様式2「子どもの姿」等のAI下書きの参照元になる。**保護者非表示・AI参照範囲の制御・根拠の追跡可能性**の3点がこの機能の存在理由であり、実装で妥協してはならない部分である。

## 2. 設計原則(実装判断に迷ったらここに戻る)

1. **保護者ドメインからはテーブルごと到達不能にする。**列単位・行単位の出し分けはしない。保護者向けRLSポリシーは1本も作らず、保護者向けRPCの戻り値にも含めず、parent_app には型定義すら置かない。
2. **AI参照可否の判定ロジックはDB関数1箇所にだけ存在させる。**フロントエンドで絞り込みを再実装しない。判定条件が2箇所に書かれた瞬間、将来必ず食い違う。
3. **記録は消えない。**論理削除のみ。AI生成の根拠になった記録が物理削除されると、確定文書の根拠を市に説明できなくなる。
4. **迷ったら書かない・送らない側に倒す。**AI送信対象かどうか曖昧な記録は送信しない。RLSで許可すべきか曖昧なアクセスは拒否する。

## 3. スコープ

**含む**: DBスキーマ、RPC、RLS、閲覧監査、機能フラグ、Ohana Kids(iPad)入力画面、admin_web 閲覧・追記画面、拒否側E2E、AI参照用の取得関数(関数まで。AI生成本体は Phase 3 のAI下書き実装に委ねる)。

**含まない**: Ohana Staff(職員スマホ)対応、通知連携、既存「備考」欄からのデータ移行(調査のみ行い、移行判断は俊さんに委ねる)、AI生成UIそのもの。

## 4. データモデル

### 4.1 テーブル `child_internal_notes`

```sql
create table child_internal_notes (
  id                uuid primary key default gen_random_uuid(),
  child_id          uuid not null references children(id),
  office_id         uuid not null references offices(id),
  note_date         date not null,
  category          text not null check (category in (
                      'handover',        -- 申し送り
                      'observation',     -- 経過観察
                      'guardian_contact',-- 保護者対応
                      'external_agency', -- 関係機関
                      'other'            -- その他
                    )),
  body              text not null check (length(body) > 0),
  ai_excluded       boolean not null default false,
  author_employee_id uuid not null references employees(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create index idx_cin_child_date    on child_internal_notes (child_id, note_date desc) where deleted_at is null;
create index idx_cin_office_date   on child_internal_notes (office_id, note_date desc) where deleted_at is null;
create index idx_cin_child_cat     on child_internal_notes (child_id, category, note_date desc) where deleted_at is null;
```

### 4.2 設計判断の理由(実装者が構造を変えたくなったとき用)

- **`category` はマスタテーブルではなく CHECK 制約。**区分キーは英語の固定値とし、日本語表示名はフロントエンド側の定数ファイル1箇所(admin_web と Ohana Kids で共有できる場所、なければ各アプリ1箇所ずつ)に持つ。表示名の変更はフロントのみで完結し、区分の追加は明示的なマイグレーションになる。区分の追加は AI 送信範囲に影響するので、マイグレーションとして俊さんのレビューを通るべき変更である。マスタテーブル化は「園ごとに区分を変えたい」という要望が実際に出てから。
- **`ai_excluded`(除外フラグ)であって `ai_allowed`(許可フラグ)ではない。**AI送信対象は「区分が許可リストに入っている AND ai_excluded = false」の単一ルール。許可フラグにすると「区分では対象外だが個別フラグは true」という矛盾状態が表現できてしまい、優先順位の解釈が実装者ごとにぶれる。除外フラグなら意味は一方向(どんな区分でも除外だけはできる)で曖昧さがない。
- **`note_date`(対象日)と `created_at`(入力日時)は別。**「先週の様子を今日書く」は普通に起きる。AI が様式2の第N期を生成するときは第N期の期間で `note_date` を絞る。入力日時で絞ると期をまたいだ記録が混入する。
- **`office_id` は児童の現所属から導出せず、書き込み時点の値を保存する。**転園後も「どの施設での記録か」が保持される。書き込みRPC内で `child_class_enrollments` の有効レコードから解決し、呼び出し側には渡させない(改竄防止)。
- **論理削除のみ**(§2-3)。UNIQUE制約は張らない(同じ子に同じ日に複数件は正常)。

### 4.3 機能フラグ

既存の機能フラグ機構(マイグレーション137番のキーと同方式)に `child_internal_notes_enabled` を追加。ステージングでは大和オハナ保育園のみON(既存シードの方式に合わせ、`exists()` ガード付き・環境非依存で書く)。

## 5. RPC(すべて SECURITY DEFINER・職員ドメイン専用)

命名・エラー処理・監査呼び出しは既存の支援保育RPC群(マイグレーション140番)の流儀に合わせること。**実装前に140番の該当関数を必ず読むこと。**

| 関数 | 引数 | 動作 |
|---|---|---|
| `create_child_internal_note` | `p_child_id, p_note_date, p_category, p_body, p_ai_excluded` | 呼び出し職員の権限確認(§6) → `office_id` をサーバ側で解決 → INSERT。作成した行を返す |
| `update_child_internal_note` | `p_note_id, p_body, p_category, p_ai_excluded, p_note_date` | §6の編集権限を満たす場合のみ UPDATE。`updated_at` 更新 |
| `soft_delete_child_internal_note` | `p_note_id` | §6の削除権限を満たす場合のみ `deleted_at = now()` |
| `fetch_child_internal_notes` | `p_child_id, p_from date default null, p_to date default null, p_categories text[] default null, p_limit int default 50, p_offset int default 0` | 閲覧権限確認 → **`log_sensitive_access()` を必ず呼ぶ** → 新しい順で返す。`deleted_at is null` のみ |
| `fetch_child_internal_notes_for_ai` | `p_child_id, p_from date, p_to date` | **AI参照可否の判定はこの関数だけが持つ(§2-2)。**条件: `category in ('handover','observation') and ai_excluded = false and deleted_at is null and note_date between p_from and p_to`。呼び出し権限は主任以上。`log_sensitive_access()` を呼ぶ。将来AI生成実装はこの関数**のみ**を使い、独自クエリを書いてはならない |

注意: `fetch_child_internal_notes_for_ai` の許可区分 `('handover','observation')` は関数内のリテラルでよい(§12-4で俊さんが変更した場合はマイグレーションで関数を差し替える)。「保護者対応」「関係機関」を生成時に明示チェックで含める案(§12-4)が採用された場合は `p_include_categories text[]` 引数を追加するが、**既定値は必ず狭い側**にする。

## 6. 権限と RLS

### 6.1 権限マトリクス

| ロール | 閲覧 | 作成 | 編集 | 論理削除 |
|---|---|---|---|---|
| 保護者 | ✗(ポリシー無し) | ✗ | ✗ | ✗ |
| 一般職員(担任) | 自施設の在籍児 | 可 | 自分の記録のみ、作成から24時間以内 | 自分の記録のみ、作成から24時間以内 |
| 主任・管理者・園長 | 自施設の在籍児 | 可 | 自施設のすべて | 自施設のすべて |
| system_admin | 全施設 | 可 | 全施設 | 全施設 |

> **役職の実態に関する注記(2026-07-30 追記・修正)**: 本システムに「施設長」という役職コードは存在しない(`roles` は system_admin / labor_manager / director[園長] / chief[主任] / office_manager[園管理者] / viewer / staff の7種)。実装済みの `is_child_internal_notes_chief`(= `is_support_childcare_chief`)は `r.code in ('chief','office_manager','director','system_admin')` かつ施設スコープ(`office_id is null` なら全施設)で判定する。したがって**「全施設」の権限を持つのは `system_admin`(または `employee_roles.office_id is null` の管理ロール)のみ**。業務上の「施設長(オーナー=複数施設の統括者)」は現状 `system_admin`、または複数施設分の `office_manager` として表現される(専用ロールは無い)。将来 `docs/統括管理者_調査報告_2026-07-30.md` の付与方式が実装されれば、その付与で複数施設に管理権限が及ぶ。

「自施設」「主任以上」の判定は既存の職員権限判定関数を再利用する(Phase 2/3 で使ったもの。新しい判定ロジックを書かない)。

- **24時間ルールの理由**: 記録は申請の根拠になるため、時間が経った記録が書き換わると根拠の信頼性が崩れる。24時間は誤字修正のための窓。それ以降の訂正は新しい記録の追記で行う(画面にその旨を表示)。24時間の判定は `created_at` 基準でRPC内に置く(RLSポリシーには置かない — ポリシーとRPCの二重実装を避け、判定はRPC側1箇所)。
- RLSはテーブルに対して有効化し、**職員ドメインのポリシーも SELECT のみ**とする(直接の INSERT/UPDATE/DELETE はポリシーで塞ぎ、書き込みは必ずRPC経由)。`office_id` 解決や24時間判定をバイパスさせないため。

### 6.2 保護者非表示の担保(全項目必須)

1. 保護者ロール向けポリシーを1本も作らない(デフォルト拒否)
2. 保護者向けRPC(`fetch_my_children_*` 系、家庭連絡帳系)の戻り値に一切含めない — **grep で `child_internal_notes` が保護者向け関数に出現しないことを確認し、確認結果を報告に含める**
3. parent_app のコードベースに型定義・APIクライアント・画面のいずれも追加しない
4. §10 の拒否側E2Eを全件PASSさせる
5. 入力・閲覧画面の双方に「この記録は保護者には表示されません」を常時表示する

## 7. 画面

### 7.1 Ohana Kids(iPad) — 主入力

- 園児詳細に「園内記録」タブを追加(機能フラグONの施設のみ表示)
- 上部: 新規入力(対象日は当日が既定・区分セレクタ・本文・「AI参照から除外」チェック・保存ボタン)。1画面完結、モーダル遷移なし — 現場で数十秒で書き終えられること
- 下部: 同児の記録を新しい順に無限スクロール表示(区分バッジ・対象日・記載者・本文)
- 「保護者には表示されません」の常時表示(§6.2-5)

### 7.2 admin_web — 閲覧・追記

- `/childcare/children`(園児マスタ)の児童詳細に「園内記録」セクションを追加
- 区分・期間でのフィルタ、新規追記、24時間以内の自分の記録の編集・削除
- 支援保育画面(`/childcare/support-childcare`)の申請詳細から「この児童の園内記録を見る」導線を追加(該当児童でフィルタ済みの状態で開く)

### 7.3 表示名定数(区分キー → 日本語)

**2026-07-30 現場確認済み(竹内主任・大原園長)。英語キーは変更しない。**

```
handover: 申し送り / observation: 個人日誌 / guardian_contact: 保護者との面談記録 /
external_agency: 療育等との連携記録 / other: その他
```

**名称衝突の確認(2026-07-30)**: `observation` の表示名「個人日誌」は既存テーブル `child_personal_journals`(コード内コメントでも「個人日誌」と呼ばれる)と同名。Phase A調査の結果、`child_personal_journals` を閲覧・一覧表示する画面やメニュー項目は現状どのアプリにも存在しない(連絡帳AI生成に伴う書き込み専用の副次テーブルで、読み取り専用の`select`は既存行の有無を確認するためだけに使われている)。**そのため現時点でユーザーが画面上で名称衝突を目にすることはない。**ただし将来`child_personal_journals`を閲覧できる画面が追加された場合は、この表示名との混同に注意すること。

## 8. AI参照との接続(このフェーズでは関数まで)

- 将来のAI下書き実装は `fetch_child_internal_notes_for_ai` **のみ**を入口とする(§5)
- 生成に使った記録の `id` は全件 `ai_run_evidence_links` に登録する(Phase 1 の既存機構)
- 参照できる記録が0件のときはAI生成を実行せず「参照できる園内記録がありません。先に記録を入力してください」と表示する — この0件ガードの仕様を実装指示書のAI下書き節に追記しておくこと
- 園児氏名の非送信(プレースホルダ置換)は AI 生成側の責務であり本フェーズでは実装しない。ただし `fetch_child_internal_notes_for_ai` の戻り値に児童氏名を含めない(id と本文だけ返す)ことで構造的に支援する

## 9. 既存「備考」の調査(Phase A で実施・移行はしない)

現行システムで「備考」と呼ばれる自由記載欄の所在を全アプリ(admin_web / Ohana Kids / parent_app / スキーマ)から洗い出し、以下を表にして報告する: テーブル・カラム名/表示画面/保護者から見えるか/実データ件数(ステージングと本番それぞれ。**本番は読み取りクエリのみ**)。移行・廃止の判断は俊さんが行う。**勝手にデータ移行やカラム削除をしないこと。**

## 10. テスト(拒否側E2E必須)

Phase 2/3 と同方式: ステージングの実アカウントで動的に検証し、型チェック・ビルド通過を「検証済み」と呼ばない。

| # | アカウント | 操作 | 期待 |
|---|---|---|---|
| 1 | 保護者(テスト保護者) | `child_internal_notes` を PostgREST 経由で直接 SELECT | 0件または拒否 |
| 2 | 保護者 | `fetch_child_internal_notes(自分の子のid)` を直接呼ぶ | 拒否(権限エラー) |
| 3 | 保護者 | `create_child_internal_note` を直接呼ぶ | 拒否 |
| 4 | 一般職員(他施設) | 他施設の児童で `fetch_child_internal_notes` | 拒否または0件 |
| 5 | 一般職員(自施設) | 主任が書いた記録を `update_child_internal_note` | 拒否 |
| 6 | 一般職員(自施設) | 自分の記録を24時間経過後に update(created_at をテストデータで過去に設定) | 拒否 |
| 7 | 一般職員(自施設) | 自分の記録を24時間以内に update | 成功 |
| 8 | 主任 | 一般職員が書いた自施設の記録を update | 成功 |
| 9 | 主任 | `fetch_child_internal_notes_for_ai`(区分混在のテストデータ) | handover/observation かつ ai_excluded=false のみ返る |
| 10 | 一般職員 | `fetch_child_internal_notes_for_ai` | 拒否 |
| 11 | 任意の職員 | 直接 INSERT(RPC経由でない) | 拒否 |

正常系: Kids からの入力→admin_web での表示、フィルタ、論理削除後に一覧から消えること、`log_sensitive_access` の記録が残ること。実機確認(ブラウザ・iPad)は俊さんが行う。確認手順を箇条書きで提示すること。

## 11. 実装フェーズと完了条件

| Phase | 内容 | 完了条件 |
|---|---|---|
| A | §9 の備考調査 + 既存権限判定関数・機能フラグ機構・140番RPCの流儀の確認 | 調査報告の提出。**俊さんの承認を得てからBへ**(§12が未解決なら着手不可) |
| B | マイグレーション(テーブル・RPC・RLS・フラグ)。番号は適用時点の連番を取る(本書内の番号をハードコードしない)。**適用前に全文提示・承認必須。**本番固有値の直書き禁止・シードは `exists()` ガード | ステージング適用、`migration list --linked` 差分0、テスト#1〜11 PASS |
| C | admin_web 画面(§7.2) | tsc/ESLint/next build クリア、俊さんの実機確認 |
| D | Ohana Kids 画面(§7.1) | ビルドクリア、俊さんの iPad 実機確認 |
| E | (Phase 3 AI下書き実装と同時)`fetch_child_internal_notes_for_ai` の接続・evidence_links 登録・0件ガード | Anthropic Console 契約後 |

## 12. 判断待ち事項(実装者は勝手に決めないこと — 未回答のまま実装に進む場合は §12 の既定値を使い、その旨を報告する)

| # | 論点 | 既定値(俊さんが未回答の場合) |
|---|---|---|
| 1 | 区分の日本語名(現場確認: 竹内主任・大原園長) | §7.3 の仮名称 |
| 2 | Ohana Staff(職員スマホ)対応 | 対応しない(スコープ外) |
| 3 | 一般職員の編集窓 24時間 | 24時間 |
| 4 | AI送信対象区分に guardian_contact/external_agency を明示チェックで含める案 | 含めない(handover/observation のみ) |
| 5 | 既存「備考」の移行 | 移行しない(調査報告のみ) |

## 13. 実装者への禁止事項(再掲・厳守)

- 保護者ドメインに関わる一切の実装(ポリシー・RPC戻り値・parent_app コード)
- AI参照可否ロジックの複製(SQL関数以外の場所への条件の再実装)
- マイグレーションの承認前適用、本番環境への一切の書き込み
- 物理 DELETE、既存「備考」データの移行・削除
- 型チェック・ビルド通過のみを根拠に「検証済み」と報告すること

## 14. 本番リリース時のチェック項目(2026-07-30 追記)

マイグレーション145番(テーブル・RLS・RPC)は`feature_flags`にグローバルキー
`child_internal_notes_enabled`を`default_enabled = false`で登録するのみで、
**どの施設に対しても機能フラグを有効化しない。** 本番へマイグレーションを
適用しただけでは、どの施設でも園内記録機能は使えない状態のままである。

本番リリース時に必要な作業(admin_web・Ohana Kids画面の実装・実機確認完了後):

- [ ] マイグレーション145番を本番へ適用済みであることを確認
- [ ] 対象施設(俊さんが指定する施設)に対して`feature_flag_office_overrides`へ
      `child_internal_notes_enabled`の有効化行を追加する(本番の実施設IDを使用。
      ステージングのseed_staging.tsのような自動投入スクリプトは本番には使わない —
      対象施設・対象時期はリリース都度俊さんの指示を仰ぐ)
- [ ] 有効化後、対象施設の職員アカウントで実機確認(Ohana Kids・admin_web双方)
- [ ] 保護者アプリに一切表示されないことを本番でも再確認(§6.2のE2Eと同水準)
