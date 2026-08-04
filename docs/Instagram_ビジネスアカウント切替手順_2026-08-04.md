# Instagram ビジネスアカウント切替 + Graph API 投稿準備 手順書

作成: 2026-08-04 / 対象: 俊(自分で作業できる粒度)。Phase 4c(Instagram実投稿)の前提。
目的: OhanaGroup の Instagram から、システムが**自動でカルーセル投稿**できる状態を作る。

> 前提知識: Instagram の自動投稿(Content Publishing API)は、**Instagramプロアカウント(ビジネス)**+**Facebookページ連携**+**Meta開発者アプリ**+**長期アクセストークン**の4点が揃って初めて可能。個人アカウントや「クリエイター」では投稿APIが使えない場合があるため**ビジネス**にする。

---

## ステップ0. 準備するもの
- [ ] OhanaGroup の Instagram アカウント(投稿に使うもの・**1アカウント**=グループ共通)。
- [ ] Facebook アカウント(管理者用。無ければ作成)。
- [ ] スマホ(Instagramアプリ操作)+ PC(Meta開発者サイト操作)。

## ステップ1. Instagram をプロ(ビジネス)アカウントへ切替
- [ ] Instagramアプリ → 自分のプロフィール → 右上メニュー →「設定とプライバシー」。
- [ ] 「アカウントの種類とツール」→「プロアカウントに切り替える」。
- [ ] カテゴリ選択(例: 教育/保育) → **「ビジネス」**を選択(「クリエイター」ではなく**ビジネス**)。
- [ ] 完了後、プロフィールに「プロフェッショナルダッシュボード」が出ることを確認。

## ステップ2. Facebookページを作成し Instagram と連携
- [ ] PCで facebook.com → 「ページ」→「新しいページを作成」。
  - ページ名: 例「オハナ保育園グループ」/ カテゴリ: 保育園・幼稚園。
- [ ] 作成したページ → 「設定」→「リンク済みアカウント」→「Instagram」→ OhanaGroup の Instagram を**接続**(ログイン認証)。
- [ ] Instagramアプリ側でも プロフィール →「編集」→「ページ」で当該Facebookページが紐付いていることを確認。
> このFacebookページ連携が、Graph API から Instagram を操作する土台になる。

## ステップ3. Meta開発者アプリを作成
- [ ] developers.facebook.com にログイン →「マイアプリ」→「アプリを作成」。
  - タイプ: **「ビジネス」**。アプリ名: 例「Ohana Works SNS投稿」。
- [ ] アプリのダッシュボード →「製品を追加」→ **「Instagram Graph API」**(および必要なら「Facebook ログイン」)を追加。
- [ ] 「アプリの設定」→「ベーシック」で **アプリID / app secret** を控える(後でトークン取得に使用)。

## ステップ4. 必要な権限(スコープ)と審査
- [ ] 投稿に必要なスコープ:
  - `instagram_basic`
  - `instagram_content_publish`(**投稿に必須**)
  - `pages_show_list` / `pages_read_engagement`(ページ経由のIG取得)
  - `business_management`(必要に応じて)
- [ ] これらは**アプリレビュー(審査)が必要**な場合がある(用途説明・スクリーンキャスト提出)。
  - 審査中は「開発モード」で**アプリ管理者/テスターのアカウント**に対しては動作するので、まず開発モードで疎通確認 → 本番公開時に審査。
  - 審査申請では「自園の公式アカウントに、自園の活動写真を投稿する」用途を明記。

## ステップ5. アクセストークンの取得(長期トークン)
- [ ] Meta の「グラフAPIエクスプローラ」(developers.facebook.com/tools/explorer)で:
  1. 上記アプリを選択 → 必要スコープを付与 → **ユーザーアクセストークン**を生成。
  2. `GET /me/accounts` で **Facebookページのアクセストークン**と **page id** を取得。
  3. `GET /{page-id}?fields=instagram_business_account` で **Instagram Business Account ID(ig-user-id)** を取得。
- [ ] **短期トークン → 長期トークン(約60日)へ交換**:
  ```
  GET https://graph.facebook.com/v20.0/oauth/access_token
    ?grant_type=fb_exchange_token&client_id={app-id}&client_secret={app-secret}
    &fb_exchange_token={短期トークン}
  ```
- [ ] 控えるもの(俊 → CCへ安全に共有・Vault投入用): **長期トークン / ig-user-id / page-id / app-id / app-secret**。
> トークンは秘匿情報。チャット等の平文で残さず、Vault投入時のみ使用する運用にする。

## ステップ6. システムへの設定(CC実装後・Phase 4c)
- [ ] CC が用意する Edge Function 用に、上記を**本番 Vault**へ投入(値はCCに渡さず俊が投入 or CCが手順提示):
  - `INSTAGRAM_ACCESS_TOKEN`(長期トークン)
  - `INSTAGRAM_IG_USER_ID`
  - (必要なら `META_APP_ID` / `META_APP_SECRET`= トークンリフレッシュ用)
- [ ] **トークンのリフレッシュ運用**: 長期トークンは約60日で失効 → CCが cron or 手動で更新する仕組みを用意(失効前に自動延長 or 俊へ再認証通知)。

## ステップ7. 動作確認(CC実装後)
- [ ] まず**モック投稿**でパイプライン(承認→投稿)をE2E確認(Phase 4a)。
- [ ] トークン投入後、**テスト投稿1枚**で疎通確認(開発モード/自アカウント)。
- [ ] カルーセル(複数枚)投稿を確認 → 本番運用開始。

---

## 補足: 制約の要点
- カルーセル**最大10枚**・画像は**JPEG推奨**・アスペクト比 4:5〜1.91:1(システム側で自動リサイズ/変換)。
- **25投稿/24h**(グループ1投稿/日なら問題なし)。
- 画像は Meta 側が**公開URLから取得**する方式 → システムは一時的に画像を公開URLで提供する必要がある(R2/Storage の署名付きURL等。CC側で設計)。
- 動画は本スコープ外(写真カルーセルのみ)。

不明点(審査で詰まる・トークン取得でエラー等)があれば、エラーメッセージ・画面を添えて共有してください。CCが次アクションを提示します。
