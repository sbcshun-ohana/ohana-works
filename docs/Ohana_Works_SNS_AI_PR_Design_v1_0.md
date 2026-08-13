# Ohana Works SNS自動広報システム 設計仕様書

**文書種別**: Claude / Claude Code 実装引継ぎ用・初期設計仕様書  
**版**: v1.0  
**作成日**: 2026-08-09  
**対象システム**: Ohana Works  
**対象**: Ohanaグループ4施設のSNS・Web広報運用  
**ステータス**: 初期設計確定版（現行Ohana Works実装確認後に技術詳細を追補する）

---

## 0. この文書の目的

本設計書は、Ohana Worksに「日々のクラス活動および任意の広報素材から、AIがSNS・Web向けコンテンツを生成・最適化し、管理者承認後に投稿する広報機能」を追加するための初期設計仕様である。

今後、本設計書をClaudeへ引き継ぎ、Claude Codeによる実装を行うことを前提とする。

本機能は単なる「Instagram自動投稿ツール」ではない。

目標は、Ohanaグループの保育活動を日々の記録から広報資産へ変換し、以下をバランスよく向上させることである。

- Ohanaグループの知名度向上
- 投稿への「いいね」「保存」「シェア」「コメント」等の反応向上
- 園児募集への自然な接続
- 保育士・職員採用への自然な接続
- 地域に対するOhanaの活動・考え方の認知向上
- Google検索・Googleマップ等からの発見性向上
- SNS運用担当者の作業負担軽減
- データ分析による継続的な広報品質向上

**「バズること」自体を目的にしてはならない。**

最上位目標は、**Ohanaの素敵な保育、子どもたちの経験、職員の明るさ・努力・挑戦、地域との関係を、事実に基づいて正しく魅力的に世の中へ届けること**である。

---

# 1. Ohanaブランドの基礎思想

## 1.1 Ohanaという名称

「Ohana」はハワイ語の「家族」を由来とする。

ブランド全体の根底には、子ども・職員・関係者が支え合いながら、明るく元気に過ごす「家族」のような組織文化がある。

## 1.2 保育の中心

Ohanaの保育は、保護者の要望を最優先することを目的とするのではなく、**子どもにとって何が大切かを中心に考える**。

保護者支援は大切にするが、広報上も「何でも保護者の希望に応える園」という誤解を招く表現は避ける。

伝えるべき中心価値は以下。

- 子どもに多くの経験・機会を提供する
- 家庭だけでは経験しにくい体験を保育園だからこそ提供する
- 子どもの主体性を尊重する
- 挑戦、失敗、再挑戦、成功という過程を大切にする
- 多くの経験から豊かな感受性を育てる
- 子ども自身が「小さな夢」をたくさん見つけられる環境をつくる
- 将来の職業・生きがい・夢につながる「扉」となる経験を提供する
- 世界、芸術、自然、農業など幅広い分野に触れられる環境をつくる

## 1.3 特徴的な活動

AIは以下をOhanaブランドを説明する主要要素として理解すること。

- 農業・田んぼ・畑・収穫等の農業体験
- 特徴的なお遊戯会
- 遊び・園外活動に利用できる専用バス
- 近隣公園への園外活動
- 海や自然に触れる体験
- 都会への外出・芸術鑑賞
- 劇団四季等の芸術体験
- 日常の枠に収まらない多様な体験
- 子どもが「次のイベント」を楽しみにできる保育

ただし、AIは「他園にはない」「地域唯一」「No.1」等の比較優位を、客観的根拠なしに記載してはならない。

## 1.4 職員文化

職員向けブランドとして以下を理解する。

- 職員数・保育士数に余裕を持たせ、過剰労働を前提としない
- 時間内に終わらない仕事は「個人が頑張る」より、業務量・必要性・優先順位を見直す
- 不要に近い業務は廃止・簡素化する
- 役職ごとの役割を明確化する
- 新卒向け育成プログラム・マニュアルを重視する
- 中途採用者も働きやすい環境を整える
- 子育て中職員を支える
- 職員の子どもを無料で預けられる託児の仕組みがある
- 子どもの体調不良による欠席・早退等を職員同士で理解し支える文化がある
- 早番・遅番等、ライフスタイルに応じた役割がある
- 幅広い年齢層が働いている
- 子育て中の職員同士の支え合いがある
- 職員が「やりたい保育」をプロジェクトチームとして実現できる
- 本部に依存するのではなく、全員で保育を支える
- 「One for all, All for one」に近い精神を大切にする
- 明るく、元気で、楽しく仕事ができることを大切にする

給与・手当・募集条件等の変動可能性がある情報は、常に最新の正式情報を確認した場合のみ使用すること。

---

# 2. 広報の基本戦略

## 2.1 優先順位

以下のいずれか1つだけを最優先にはしない。

1. 知名度・ブランド向上
2. 園児募集
3. 保育士・職員採用
4. 地域への発信

日々の活動そのものの魅力を伝え、その結果として園児募集・採用につながることを目指す。

## 2.2 日常投稿の基本姿勢

毎回「園児募集中」「職員募集中」と直接広告する方式を避ける。

主として以下を感じてもらう。

- Ohanaは楽しそう
- 活動の幅が広い
- 子どもに多くの経験を提供している
- 保育園の枠にとらわれない活動をしている
- 子どもの主体性を大切にしている
- 先生たちが明るい
- 先生たち自身も楽しみ、考え、挑戦している
- この園なら子どもが多くの経験をできそう
- この園なら保育士として面白い仕事ができそう

## 2.3 投稿を固定フォーマット化しない

AIは投稿ごとに最も適した方向性を判断する。

使用可能な主な方向性:

- 子どもの姿中心
- 活動中心
- 子どもの発見中心
- 子どもの挑戦・成長ストーリー
- 保育の意味中心
- Ohanaの特色中心
- 職員目線
- 職員の工夫・楽しさ
- 採用ブランディング
- 季節感
- 地域性
- 面白さ
- 温かさ
- 感動
- 専門性
- 複数施設の一日の様子
- 過去活動の振り返り

「ランダム」ではなく、素材と過去投稿履歴を踏まえた多様性制御とする。

---

# 3. 固定ルールとAI改善可能ルール

本システムではルールを必ず2層に分離する。

## 3.1 固定ガードレール（AIによる自動変更禁止）

以下は投稿分析結果にかかわらずAIが勝手に変更してはならない。

### 個人情報
- 園児名をSNSに一切出さない
- 職員名をSNSに一切出さない
- 保護者名その他個人を特定する情報を出さない
- 病気・家庭事情・発達状況等、個別のセンシティブ情報を投稿しない

### 肖像・画像
- SNS掲載NG園児を投稿しない
- 掲載NG園児が誤って写った可能性をAIが検出した場合は安全フローへ回す
- 第三者が識別可能な状態で写った場合はぼかし等で加工
- 遠景・群衆等、合理的に個人を特定できない場合は一律ぼかし不要

### 表現
- 根拠のない情報を創作しない
- 「唯一」「No.1」「地域初」「他園にはない」等を根拠なく使用しない
- 元データに存在しない具体的事実を捏造しない
- 子どもの実際の発言・反応を意味が変わらない範囲で言い換えることは可
- 実際にはなかった理想的な発言を創作してはならない
- 強制的・一方的な保育に見える表現を避ける
- 子どもが考え、選び、試し、挑戦する主体性を尊重した表現にする
- 元データから適切な言い換えができない場合は、その発言を使用しない
- 「失敗で終わった」印象を強く残す結末を避ける
- 失敗→再挑戦→成功、または失敗→次の挑戦への意欲という成長の流れは積極活用可
- バズ狙いの煽り、過剰演出、誤解を招く切り抜きを禁止

### 位置情報・安全
- 園外活動の現在地・行動予定をリアルタイムで外部発信しない
- 原則、活動終了後に投稿
- 子どもの安全に影響する情報を投稿しない

### 承認
- AI単独で外部公開しない
- 最終公開には統括管理者・統括園長以上の承認を必須とする

## 3.2 AIが自律改善してよい領域

以下は投稿実績・媒体特性・ユーザー反応を分析し、AIが次回以降自動改善してよい。

- 投稿構成
- 文章量
- 書き出し
- 締め方
- 絵文字の使い方
- 投稿テーマの見せ方
- 投稿日時
- ハッシュタグ選定
- 各媒体の選定
- 施設・活動の組み合わせ
- 定期投稿候補の優先順位
- コンテンツストック再編集
- 採用・園児募集・地域・ブランド要素の比率
- 動画の尺
- 動画のカット構成
- テロップ
- BGMの方向性
- CTAの有無・表現
- 過去コンテンツ再利用のタイミング

AIが変更した改善内容は必ず改善履歴に記録する。

---

# 4. 投稿タイプ

本システムには最低2種類の投稿生成機能を実装する。

## 4.1 定期投稿（クラス活動連動型）

既存の「クラス活動」情報を参照してSNS投稿候補を自動生成する。

### 基本
- 4施設のクラス活動を対象
- Ohanaグループの共通SNSアカウントへ投稿
- 1投稿に複数施設・複数クラスが含まれてよい
- 施設名を明記し「どの施設で何をしたか」が分かること
- メインとなる活動は大和オハナ保育園が多くなることを許容
- 各施設を人工的に均等配分しない

### 写真
- 1投稿 最大5枚
- 写真がない活動は原則SNS投稿候補にしない
- すべての写真とすべての活動を必ず使用する必要はない
- 写真と活動内容の整合性をAIが確認
- 異なるクラス・活動は、必要に応じて段落や見出しで分割
- 無理に1本のストーリーに連結しない

### 投稿数
- 定期投稿は最大1日1件
- 毎日必須ではない
- 投稿価値がある場合のみ投稿
- 自由投稿は別枠で追加可能

## 4.2 自由投稿・特別広報型

クラス活動に紐づかない任意の広報を作成する機能。

### 入力
- 写真
- 動画
- 何があったか
- 何を伝えたいか
- 投稿目的
- 管理者指定投稿日時

### 投稿目的
以下の3カテゴリから選択可能とする。

- 採用活動
- 園児募集
- 地域向け

設計上は複数選択に対応可能とする。

### AI処理
AIが以下を提案・生成する。

- 投稿文章
- 媒体ごとの文章
- 投稿先媒体
- ハッシュタグ
- メンション
- 画像処理
- 動画編集
- CTA
- BGM
- テロップ

管理者はAIが選んだ媒体を承認画面で変更可能にする。

### 投稿日時
自由投稿では管理者の指定日時を優先する。

AIは改善案を提示してもよいが、管理者指定を上書きしない。

---

# 5. 特別広報: お遊戯会

お遊戯会は日常イベントとは別枠の重要ブランドコンテンツとして扱う。

## 5.1 位置づけ

- 1年間の保育の締めくくり
- 子どもたちの成長を表現する場
- 先生たちが約1年間計画・準備するイベント
- 先生が裏方として子どもを支える
- 先生自身が演目の主役になることもある
- 保護者だけでなく、地域関係者、他園関係者、職員家族等も楽しみにしているイベント

## 5.2 事前広報

本番内容は当日まで原則秘密。

AIは以下を発信する。

- 準備の過程
- 子どもの成長
- 挑戦の様子
- 先生たちの努力
- プロジェクトとしての積み重ね
- 開催への期待感

以下は禁止。

- 演目の重要部分を事前公開
- サプライズ演出のネタバレ
- 当日まで秘密としている具体的内容の推測・公開

## 5.3 開催後

専用カメラ等で撮影された動画を編集し、特別広報コンテンツとして公開可能とする。

---

# 6. 投稿生成AI仕様

## 6.1 AI入力

AIは可能な限り以下を参照する。

- 施設
- クラス
- 年齢
- 活動日
- 活動記録
- 子どもの様子
- 子どもの発言
- 保育者コメント
- 写真 最大5枚
- 動画
- 過去のSNS投稿
- 直近の投稿傾向
- 投稿実績
- Ohanaブランド情報
- Ohana Works内の正式施設情報
- 必要に応じた公開Web情報

現行Ohana Worksのクラス活動データ構造は、実装着手前に必ず確認する。

SNS専用の二重入力をむやみに増やさず、既存データを正本として再利用する。

## 6.2 文章長

固定しない。

AIが素材に応じて判断する。

- 短く伝える投稿
- 標準的な投稿
- ストーリー型長文

を使い分ける。

## 6.3 トーン

基礎トーン:

- 明るい
- 楽しい
- 元気

投稿ごとに以下を組み合わせる。

- 温かい
- ワクワク
- 感動
- ユーモア
- 挑戦
- 発見
- 専門性
- 地域性

## 6.4 絵文字

多めを許可。

ただし文章の可読性を損なわない。

同じ絵文字パターンの連続使用を避ける。

## 6.5 ハッシュタグ

- 1投稿 最大5個
- 毎回同じに固定しない
- 毎回変える必要もない
- 投稿内容・地域・採用・園児募集・発見性等を分析してAI選定
- SEOとSNS内検索は別概念として評価
- 媒体別にハッシュタグ有効性を評価

## 6.6 CTA

毎回広告的CTAを入れない。

必要な投稿のみ自然な誘導を許可。

例:
- 気になることがあればDMへ
- 園見学についてDMで問い合わせ可能
- 採用についてDMで問い合わせ可能

Instagram本文内の外部リンク制約等、媒体仕様を考慮する。

---

# 7. 子ども・先生の発言の扱い

## 7.1 園児名・職員名

SNSでは一切使用禁止。

元データに含まれていても匿名化する。

## 7.2 子どもの発言

積極的に利用してよい。

ただし逐語録である必要はない。

AIは以下を満たす範囲で再構成可能。

- 元の発言・反応に根拠がある
- 意味・ニュアンスを変えない
- 個人を特定しない
- 実際には存在しない発言を創作しない

## 7.3 先生の発言

利用可能。

ただし、表現チェック必須。

子どもの選択肢をなくすような強制的・一方的な声かけに見える場合は、そのまま掲載しない。

事実と意図を変えない範囲で、子どもの主体性を支える表現へ修正する。

適切に修正できない場合は発言そのものを使用しない。

---

# 8. 失敗・挑戦の表現

以下は良いコンテンツとして積極活用する。

- 挑戦
- うまくいかない
- 工夫
- 再挑戦
- 成功
- 次も挑戦したいという意欲

ただし「最終的にうまくできませんでした」で終わるネガティブな表現は避ける。

成功に至らなくても、

- 次にまた頑張ろうと思った
- 新しい方法を考えた
- 先生たちが次の挑戦を支える

等、成長・継続へ接続する。

---

# 9. 写真処理

## 9.1 AI補正を許可

以下は自動処理可。

- 明るさ補正
- コントラスト等の軽い補正
- 傾き補正
- トリミング
- 縦横比変更
- 媒体最適化
- 軽い色調調整
- 不要余白カット
- 第三者ぼかし

## 9.2 禁止

活動記録としての事実を変える加工は禁止。

例:
- 存在しない人物を追加
- 存在しない物を追加
- 子どもの表情を別の表情に生成
- 実際と異なる場所へ背景置換
- 人数や活動状況を誤認させる編集

---

# 10. 動画機能

現行クラス活動に動画アップロード機能が不足する場合、Ohana Works本体を改修する。

## 10.1 動画アップロード

クラス活動および自由投稿で動画を広報素材として登録可能にする。

## 10.2 AI自動編集

以下をAIへ委任可能。

- 見せ場抽出
- 不要部分カット
- 複数動画結合
- 縦型化
- 媒体別尺調整
- 字幕
- 状況説明テロップ
- タイトル
- 場面順調整
- 速度調整
- BGM
- 音量調整

## 10.3 動画の最上位原則

「バズるため」の編集を優先しない。

Ohanaの保育の価値が正しく魅力的に伝わることを最優先する。

以下を禁止。

- 刺激的な煽り
- 誤解を招く切り抜き
- 子どもの失敗・感情を見世物化
- 活動の事実を変える編集
- 過剰な釣りタイトル

## 10.4 音声

子ども・先生の会話を主な情報源にしない。

理由:
- 子どもの発音を音声認識が誤認する可能性
- 先生の発言が常に広報に適した表現とは限らない

使用してよい音声例:
- 笑い声
- 歓声
- 挨拶
- 元気な返事
- 意味を誤認しにくい短い声

テロップは音声文字起こしだけでなく、

- 状況
- 表情
- 行動
- 活動記録

を総合して生成可能。

ただし映像・記録に根拠がない心理状態を断定しない。

## 10.5 BGM

AIが動画に合わせて自動選択可能。

条件:
- 著作権・ライセンス上利用可能であること
- 各SNSの利用条件に適合すること
- 利用可否が不明な音源は使用しない
- 音源・ライセンス根拠を投稿履歴へ記録可能にする

---

# 11. メディア保存・削除

## 11.1 初期方針

元動画は永久保存しない。

**投稿完了から原則30日後に元動画を自動削除**する。

Ohana Worksには最低限以下を残す。

- 投稿先SNS
- 投稿URL
- 実際に投稿した文章
- 投稿日時
- 投稿分析データ
- 投稿ID
- 関連施設・クラス・活動カテゴリ

## 11.2 写真

写真についても永久保存を必須としない。

実装時に以下を確認し、保存期間を設定可能にする。

- ストレージコスト
- 保護者アプリ側での必要性
- 過去広報再利用の価値
- 個人情報最小化

初期実装では管理画面から保存期間を設定できる構造を推奨する。

## 11.3 アーカイブ

将来拡張として「重要コンテンツのみ保存」フラグを追加可能とする。

---

# 12. 肖像権・SNS掲載同意

## 12.1 現状

入園時に肖像権に関する同意を取得している。

一部家庭はSNS掲載NG。

## 12.2 将来

保護者アプリ導入後、同意管理をアプリ内で完結できる構造を目指す。

## 12.3 AI安全補助

基本ルールは「掲載NG園児を撮影素材に含めない」。

AIによる顔認識・検出は、この運用を置き換えるのではなくヒューマンエラー対策の第二防衛線とする。

掲載NG園児の可能性を検出した場合:
1. 投稿処理停止
2. 自動マスキング・トリミング候補を生成可能
3. 再安全チェック
4. 管理者確認
5. 承認後のみ投稿

生体情報としての顔認証データをどこまで保持するかは、実装時に法務・プライバシー観点を含めて最小化する。

---

# 13. 第三者の写り込み

識別可能な第三者が写っている場合:
1. AI検出
2. ぼかし等の加工
3. 加工後安全チェック
4. 承認待ちへ

遠景・群衆等で個人特定が合理的に困難な場合、加工必須としない。

加工によって素材が不自然になる場合、別素材使用を管理者へ提案する。

---

# 14. 公開前AI安全チェック

**すべての投稿は管理者承認依頼の前にAI安全チェックを通過すること。**

最低チェック項目:

- 園児名なし
- 職員名なし
- 保護者・第三者個人情報なし
- SNS掲載NG園児チェック
- 第三者写り込みチェック
- 個人を特定できる情報チェック
- 写真と文章の整合性
- 動画と文章の整合性
- 子どもの主体性を損なう表現
- 強制的な声かけ表現
- 元データにない事実の創作
- 根拠のない比較表現
- 危険なリアルタイム位置情報
- ネタバレ
- 外部施設正式名称
- メンション先確認
- BGMライセンス
- 誤解を招く加工
- 不適切・差別的・攻撃的表現
- 投稿媒体の規約上の問題

### 判定
- PASS: 承認待ちへ
- AUTO_FIXED: AI修正後、再チェック
- NEEDS_REVIEW: 管理者確認が必要
- BLOCKED: 投稿不可

安全チェックの結果は承認画面で確認可能にする。

---

# 15. 管理者承認フロー

対象権限:
- 統括管理者
- 統括園長
- それ以上の役職

### 操作
管理者は以下を行える。

1. そのまま承認
2. 文章を直接編集して承認
3. AIへ修正指示
4. AI再生成
5. 写真変更
6. 投稿媒体変更
7. 投稿時刻変更
8. 却下

### 固定
承認なしで外部公開しない。

### 管理者修正
AIが将来の改善に利用できるよう、以下を履歴化。

- AI初稿
- 管理者修正後
- 差分
- 修正理由（任意）
- 投稿結果

ただし管理者の1回の修正を普遍的ルールとして過学習しない。

---

# 16. 投稿日時最適化

## 16.1 定期投稿

AIが以下を分析して推奨投稿日時を決定する。

- 曜日
- 時刻
- 媒体
- 投稿形式
- 投稿テーマ
- 過去リーチ
- 保存
- シェア
- コメント
- プロフィールアクセス
- フォロワー反応

管理者が内容・投稿時間を承認後、指定時刻に自動投稿。

土日祝も投稿可能。

## 16.2 承認期限を逃した場合

推奨時刻までに承認されなかった投稿は破棄しない。

翌日以降の最適時刻をAIが再計算し、再度承認候補として提示する。

---

# 17. コンテンツストック

未投稿候補を「コンテンツストック」として管理する。

AIはストックを常時再評価可能。

- 優先順位変更
- 複数活動統合
- 再編集
- 投稿日時変更
- テーマ変更
- 過去素材との組み合わせ
- 古くなった候補の投稿見送り提案

ただし公開には再度管理者承認が必要。

---

# 18. 投稿間隔

定期投稿は最大1日1件。

毎日投稿する必要なし。

自由投稿は追加可能。

「公開済みの定期投稿」と「公開済みの自由投稿」の双方を最終投稿日としてカウントする。

### 無投稿管理
- 3日投稿なし: AIが未投稿素材・ストックを再評価
- 5日投稿なし: ダッシュボードに「投稿候補不足」を表示
- 7日投稿なし: 「要対応」として優先表示

価値のない投稿を穴埋め目的で無理に作らない。

---

# 19. 過去投稿の再利用

過去の活動を振り返り投稿として再利用可能。

条件:
- 過去の活動であることを明示
- 今日の出来事のように誤認させない
- 季節・イベント・農業サイクル等、「今振り返る意味」があること
- 単なる投稿穴埋めにしない

---

# 20. 外部情報の検索・補完

AIは必要に応じて公開Web情報を検索し、事実確認・正式名称補完をしてよい。

例:
- 公園名
- 施設名
- イベント正式名称
- 劇場名
- 店舗・企業・団体名

職員の入力した名称が不正確でも、公式情報等で正しい名称を確認して補正する。

### 禁止
- 確認できない情報を推測
- 外部情報から子どもの行動予定を補完
- 不要な個人情報を付加
- 作品のネタバレ
- 根拠のない評価・比較

---

# 21. 外部施設・作品の扱い

劇団四季等の名称は正式名称を確認できれば本文利用可。

ただし作品・演劇等は内容紹介ではなく、

- 子どもがどう楽しんだか
- どのような経験になったか
- 芸術に触れる機会としての意味

を中心にする。

物語・結末・演出・サプライズ等のネタバレは避ける。

---

# 22. メンション

公式アカウントであることを十分確認できる場合のみメンション可。

確認できない場合はメンションしない。

同名アカウント、ファンアカウント、非公式アカウント等への誤メンションを防止する。

---

# 23. Instagram位置情報

基本位置情報:
**大和オハナ保育園**

投稿元が別施設でも原則これを使用可能。

ただし遠足・園外活動等で特定訪問先が投稿の中心の場合、AIが正式場所を確認して訪問先を位置情報として選択可能。

リアルタイム現在地公開は禁止。

---

# 24. 対象媒体戦略

## 24.1 現状

- Instagram: メイン
- Facebook: Instagram連携投稿
- Google Business Profile: 4施設すべて登録済み
- Webサイト: STUDIOで構築

## 24.2 初期推奨媒体

### Phase 1
1. Instagram
2. Facebook
3. Google Business Profile
4. STUDIO Webサイトへの活動コンテンツ連携

### Phase 2
5. YouTube Shorts
6. TikTok

### Phase 3 / 必要性評価
7. その他SNS

X等についてはアカウントを増やすこと自体を目的にせず、ターゲット・成果・API条件を確認して採否を判断する。

---

# 25. 媒体別コンテンツ最適化

同じ文章を全媒体へコピーしない。

「1つの保育活動」から媒体ごとに最適なコンテンツを生成する。

## Instagram
- 写真・動画
- 感情
- ストーリー
- 明るさ
- Ohanaらしさ
- 保存・シェア
- 最大5ハッシュタグ
- 必要に応じDM導線

## Facebook
- Instagramとの連携を活用可能
- 必要に応じFacebook向けに文章調整
- 地域・保護者世代への文脈を評価

## Google Business Profile
- 各施設のローカル検索・認知
- 施設に関係する情報を優先
- 4施設へ一律投稿しない
- 投稿の内容と対象施設をAIが判断
- 園児募集等の変動情報は管理者が明示した場合のみ掲載

## STUDIO Web
- 活動記事の蓄積
- 地域名・施設名・活動名
- 検索から発見できる情報資産
- SNSとは異なるSEO向け文章
- 構造化データ・ページタイトル・description等を設計可能にする

## TikTok
- 短尺動画・写真投稿
- 動画中心に最適化
- 若年層等の利用特性を考慮
- 「バズ狙い」ではなく保育価値の伝達
- API公開投稿にはTikTok側の審査・同意等が必要になるためPhase 2

## YouTube Shorts
- 短尺動画
- タイトル・説明・検索性
- Ohanaの活動アーカイブ
- API認証・監査条件を実装前に確認

---

# 26. 2026-08時点で確認した外部APIの実装前提

**重要: API仕様は変更されるため、Claude Codeが実装に入る直前に公式ドキュメントを再確認すること。**

## Meta / Instagram
Meta公式Content Publishing APIでは、単一画像、動画/Reels、複数画像・動画のカルーセル等の公開に対応する。

Facebook Pages APIでもPage投稿の作成・管理が可能。

実装ではMeta App、適切なアカウント種別・権限・アクセストークン管理が必要。

## Google Business Profile
Google Business Profile APIにはローカル投稿の作成・編集・削除機能がある。

4園それぞれのlocation IDを正しく保持し、該当施設にだけ投稿する。

OAuth権限管理が必要。

## STUDIO
2026年4月17日から正式版Data Connect APIが提供されており、Businessプラン以上で外部APIデータを動的リスト・動的ページ等に表示可能。

想定アーキテクチャ:
Ohana Worksの公開用Content API
→ STUDIO Data Connect API
→ 活動一覧・活動詳細ページ

「STUDIO CMSへ書き込む」のではなく、Ohana Worksをコンテンツ正本としてSTUDIOが読み込む構造を第一候補とする。

現契約プランの確認が必要。

## TikTok
Content Posting APIでDirect Post / Uploadが利用可能。

未監査クライアントによるDirect Postは公開範囲に制限があるため、公開運用前にTikTok側の審査・要件確認が必要。

## YouTube
YouTube Data APIで動画アップロードが可能。

APIプロジェクトの確認・監査条件、OAuth、YouTube API quota等を実装前に確認する。

---

# 27. SEO / MEO設計

## 27.1 SEO

InstagramのハッシュタグとWeb SEOを同一視しない。

Web記事では以下を構造化する。

- 施設名
- 地域
- 年齢
- 活動名
- 活動カテゴリ
- 日付
- タイトル
- 本文
- meta description
- OGP
- 画像ALT
- canonical
- 構造化データ
- 内部リンク

AIは不自然なキーワード詰め込みを行わない。

## 27.2 地域キーワード

具体的なSEOキーワードは実装時に検索実態を調査して構築する。

候補カテゴリ:
- 大和市 保育園
- 大和駅 保育園
- 大和市 認可保育園
- 大和市 保活
- 大和市 保育士 求人
- 大和市 保育士 転職
- 地域 + 農業体験
- 地域 + 英会話
- 地域 + 自然体験
- 地域 + 園外活動

上記は固定キーワードではなく初期候補。

## 27.3 MEO

4園のGoogle Business Profileを活用。

- 正式施設情報の整備
- 写真
- 投稿
- 口コミ
- 返信
- 必要に応じたCTA
- 投稿と施設の整合性

を管理する。

---

# 28. Google口コミ一元管理

Ohana Worksで4園分のGoogle口コミを一元管理する。

### 機能
- 新着取得
- 施設別表示
- AI内容分類
- 返信案作成
- 管理者修正
- 承認
- 返信
- 履歴保存
- 要注意判定

---

# 29. SNSコメント管理

AIがコメントを取得・分類する。

分類例:
- 好意的
- 一般質問
- 入園問い合わせ
- 採用問い合わせ
- 見学
- 実利用に基づく苦情
- 事実確認必要
- 挑発・荒らし
- 誹謗中傷等の可能性
- 緊急・安全上の問題

### 通常コメント
AI返信案
→ 管理者承認
→ 返信

AI単独返信は禁止。

---

# 30. DM管理

DMもOhana Worksで一元管理。

### 通常
DM受信
→ AI分類
→ 必要情報確認
→ AI返信案
→ 管理者承認
→ 送信

### 不明情報
AIが推測して回答してはならない。

管理者へ質問
→ 管理者が現状を回答
→ AI再生成
→ 管理者承認

### 特に変動的な情報
- 園児募集
- 年齢別空き
- 採用有無
- 職種別採用基準
- 勤務条件
- 人員状況

過去の回答だけから現在状況を断定禁止。

---

# 31. 入園・採用問い合わせ

園児・職員の空き状況とSNS投稿を自動直結しない。

管理者が戦略的に「今この募集を広報したい」と自由投稿で入力した場合のみ、その内容を投稿に利用する。

### DMで入園・採用問い合わせを受けた場合
AIは過去情報から勝手に「募集しています」「空きがあります」と回答しない。

1. 要対応として表示
2. 管理者が現在状況確認
3. AI返信案
4. 管理者承認
5. 返信

---

# 32. 営業・広告DM

業者・営業・広告目的のDMは通常問い合わせと分離。

AIがカテゴリ判定し、重要な入園・採用問い合わせと混在させない。

自動返信は原則行わない。

---

# 33. クレーム・誹謗中傷対応

## 33.1 実際の利用・保育に関係する苦情

AIは必要な事実確認項目を管理者へ提示。

事実確認後、返信案を作成。

管理者承認必須。

## 33.2 単なる敵対・荒らし・誹謗中傷等の可能性

AIは単純な反論文を生成してすぐ返信しない。

以下を分析・提案する。

- 内容分類
- 想定される被害
- 拡散リスク
- 返信する/しない
- 証拠保全
- プラットフォームへの報告検討
- 必要に応じて専門家相談
- その他の対応選択肢

法的評価は断定しない。

---

# 34. 問い合わせSLA・未処理管理

即時プッシュ通知は必須としない。

ダッシュボードで未処理を確実に管理する。

### 期限
- 入園・採用・見学等、優先度高: 2営業日以内
- 一般問い合わせ: 3営業日以内

これは「通常待ってよい時間」ではなく、取りこぼしを防ぐ最終ライン。

通常はできる限り即時対応。

### 表示
- 未処理
- 対応中
- 管理者確認待ち
- AI案作成済み
- 送信待ち
- 完了
- 期限接近
- 期限超過

既読を「対応済み」とみなさない。

---

# 35. 問い合わせ履歴・AIナレッジ

過去対応はAIの参考資料として利用可能。

ただし以下に分離する。

## 恒常情報
例:
- 日曜日の保育有無
- 施設の基本概要
- 固定の利用方法

正式施設情報を最優先し、過去回答も参考にできる。

## 変動情報
例:
- 園児空き
- 現在の採用状況
- 職種ごとの募集条件
- 人員配置

過去回答は参考に留め、現在の事実確認を優先。

### 最新優先
管理者が新しい方針を示した場合、過去回答より新方針を優先。

### 保存
DM個人情報を永久保存することを避ける。

可能であれば、
過去DM → 匿名化・一般化 → Ohana問い合わせ対応ナレッジ
へ変換し、個別データの保存期間を短くする。

具体的な保存期間・件数は実装時に個人情報最小化と有用性を比較して設定する。

---

# 36. 広報ダッシュボード

利用権限:
**統括管理者・統括園長以上**

### ホームに表示
- 今日の投稿予定
- 承認待ち
- 自由投稿予定
- コンテンツストック
- 投稿間隔
- 3/5/7日アラート
- 新着コメント
- 新着DM
- Google口コミ
- 入園問い合わせ
- 採用問い合わせ
- 要対応
- 期限接近
- 期限超過
- 誹謗中傷等リスク
- 媒体別成果
- AI改善レポート

### 投稿分析
- リーチ
- インプレッション
- いいね
- コメント
- 保存
- シェア
- 動画再生
- 視聴維持
- プロフィール閲覧
- フォロワー変化
- Web遷移
- 取得可能なその他媒体指標

APIで取得できない指標は無理に推測しない。

---

# 37. AI継続改善エンジン

投稿結果を常時分析する。

### 分析軸
- 活動カテゴリ
- 施設
- 年齢
- 写真枚数
- 動画有無
- 文章長
- 投稿構成
- 絵文字
- ハッシュタグ
- 投稿曜日
- 投稿時刻
- 投稿媒体
- CTA
- 職員要素
- 子どもの発言
- 農業
- お遊戯会
- 園外活動
- 芸術
- 地域
- 採用
- 園児募集

### AIは次回から自動改善可能

安全ガードレール以外は管理者の個別承認なしに改善してよい。

### 変更履歴
必ず記録。

例:
- 変更日時
- 対象ルール
- 変更前
- 変更後
- 根拠データ
- 期待効果
- 実績
- 必要に応じロールバック

---

# 38. 過去Instagram分析

初期導入時に可能な限り過去Instagramを取得・分析する。

分析対象:
- 投稿文
- 写真
- 動画
- Reels
- 投稿日
- 時刻
- いいね
- コメント
- 再生
- 保存・シェア等取得可能データ
- 投稿テーマ

### 目的
- Ohanaらしい表現の抽出
- 活動幅の把握
- 明るさの表現
- 職員の見せ方
- 子どもの見せ方
- 地域発信の特徴
- 高反応コンテンツの共通点
- 低反応コンテンツの改善点
- お遊戯会投稿のブランド要素抽出

過去投稿の文体を機械的にコピーしない。

---

# 39. 施設情報の正本

SNS用に施設情報を重複入力しない。

**Ohana Worksにある基本施設情報をSingle Source of Truthとする。**

AIが回答・投稿する際に参照。

不足項目のみ実装確認後に追加する。

### 情報を分類
- 恒常
- 準恒常
- 変動
- 投稿ごとに指定

AIは情報の鮮度を考慮する。

---

# 40. 保護者アプリとの境界

本設計書の主対象はSNS自動広報。

ただしクラス活動素材は将来的に保護者アプリでも使用する。

確定済み事項:
- 保護者アプリとSNSは別文章を生成
- SNS用と保護者向け用は別承認
- 一方だけ承認、一方を却下可能
- 保護者アプリでは4園の活動を共通フィードで閲覧可能とする方向
- 写真枚数はSNSと同程度でよい

詳細な保護者アプリ仕様は本SNS設計のスコープ外とし、現行Ohana Works確認後に別仕様として扱う。

---

# 41. 推奨システムアーキテクチャ

## 41.1 論理構成

```text
[Ohana Works]
  |
  +-- Class Activity
  +-- Free Post
  +-- Facility Master
  +-- Consent / Privacy
  +-- Media Upload
  |
  v
[Content Ingestion Layer]
  |
  +-- Text normalization
  +-- Facility/activity mapping
  +-- Media metadata
  |
  v
[AI Analysis Layer]
  |
  +-- Activity understanding
  +-- Photo/video understanding
  +-- Brand analysis
  +-- External fact verification
  +-- Risk detection
  |
  v
[Content Generation Engine]
  |
  +-- Instagram
  +-- Facebook
  +-- Google Business Profile
  +-- STUDIO Web
  +-- TikTok (Phase 2)
  +-- YouTube Shorts (Phase 2)
  |
  v
[Safety Gate]
  |
  +-- Privacy
  +-- Consent
  +-- Fact checking
  +-- Language checks
  +-- Location safety
  +-- Third-party checks
  +-- Copyright/BGM
  |
  v
[Admin Approval]
  |
  +-- Edit
  +-- AI regenerate
  +-- Channel override
  +-- Schedule override
  +-- Approve / Reject
  |
  v
[Scheduler / Publisher]
  |
  +-- Platform adapters
  +-- Retry
  +-- Idempotency
  +-- Publish log
  |
  v
[Analytics]
  |
  +-- Metrics ingestion
  +-- Performance analysis
  +-- AI optimization
  +-- Dashboard
```

---

# 42. 推奨ドメインモデル

実装時に現行DBへ合わせて調整する。

## `social_content_source`
- id
- source_type: class_activity | free_post | archive
- source_id
- facility_ids[]
- class_ids[]
- activity_date
- purpose[]
- source_text
- status
- created_at
- created_by

## `social_media_asset`
- id
- source_id
- type: image | video
- storage_path
- mime_type
- width
- height
- duration
- facility_id
- class_id
- consent_scan_status
- third_party_scan_status
- safety_status
- expires_at
- archive_flag
- created_at

## `social_content_plan`
- id
- source_id
- generation_version
- content_strategy
- primary_goal
- secondary_goals[]
- selected_channels[]
- suggested_publish_at
- manager_publish_at
- status
- created_at

## `social_channel_content`
- id
- plan_id
- channel
- facility_id nullable
- caption
- hashtags[]
- title
- description
- alt_text[]
- mentions[]
- location_tag
- media_asset_ids[]
- cta
- safety_status
- approval_status
- approved_by
- approved_at

## `social_publication`
- id
- channel_content_id
- platform_post_id
- platform_url
- scheduled_at
- published_at
- status
- error_code
- retry_count
- final_caption
- final_media_manifest
- created_at

## `social_safety_check`
- id
- plan_id / channel_content_id
- check_type
- status
- severity
- explanation
- auto_fix_applied
- reviewed_by
- created_at

## `social_approval_log`
- id
- content_id
- action
- before_payload
- after_payload
- instruction
- actor_id
- created_at

## `social_metric_snapshot`
- id
- publication_id
- metric_name
- metric_value
- measured_at

## `social_ai_optimization_log`
- id
- rule_key
- previous_value
- new_value
- evidence_summary
- effective_from
- rollback_at nullable

## `social_inbox_thread`
- id
- platform
- external_thread_id
- facility_id nullable
- classification
- priority
- due_at
- status
- current_owner
- created_at
- updated_at

## `social_inbox_message`
- id
- thread_id
- direction
- external_message_id
- text
- sanitized_text
- received_at / sent_at
- ai_draft
- final_reply
- approved_by

## `social_review`
- id
- platform
- facility_id
- external_review_id
- rating
- text
- classification
- reply_status
- ai_reply
- final_reply
- created_at

---

# 43. ステータス設計

## 投稿
- DRAFT_SOURCE
- AI_ANALYZING
- GENERATING
- SAFETY_CHECK
- AUTO_FIX
- NEEDS_REVIEW
- READY_FOR_APPROVAL
- APPROVED
- SCHEDULED
- PUBLISHING
- PUBLISHED
- FAILED
- REJECTED
- EXPIRED
- ARCHIVED

## 問い合わせ
- NEW
- NEEDS_ADMIN_INFO
- AI_DRAFT_READY
- WAITING_APPROVAL
- READY_TO_SEND
- SENT
- CLOSED
- OVERDUE
- RISK_REVIEW

---

# 44. 投稿失敗・API障害

外部SNS APIは必ず失敗する前提で設計する。

### 必須
- Idempotency
- Retry with exponential backoff
- API error log
- token expiration detection
- permission error
- upload error
- duplicate post prevention
- publish status polling when needed
- manual retry
- channel-specific failure isolation

1媒体の失敗で他媒体の成功投稿を巻き戻さない。

---

# 45. OAuth・認証情報

アクセストークン等をDB平文保存しない。

- Secret Manager等
- 暗号化
- 最小権限
- token refresh
- expiration monitoring
- connection status dashboard

を実装する。

---

# 46. 通知

即時プッシュ通知を必須としない。

ダッシュボード中心。

最低限:
- 承認待ち
- 投稿失敗
- API連携切れ
- 5日投稿なし
- 7日投稿なし
- 重要問い合わせ期限接近
- 期限超過
- 高リスクコメント/口コミ

を見落とさないUIにする。

---

# 47. 監査ログ

以下は削除しない監査ログを推奨。

- 誰が承認
- 誰が修正
- AIが何を修正
- いつ公開
- どこへ公開
- 投稿文章
- 投稿URL
- 安全チェック結果
- エラー
- AIルール変更
- 問い合わせ返信承認

---

# 48. AIプロンプト設計方針

1つの巨大プロンプトに全ルールを入れない。

推奨分割:

1. Brand Policy
2. Safety Policy
3. Content Understanding
4. Platform Strategy
5. Caption Generation
6. Hashtag Selection
7. Media Editing Plan
8. Safety Reviewer
9. Fact Verifier
10. Comment/DM Classifier
11. Reply Generator
12. Performance Analyst
13. Optimization Agent

### 優先順位
`Safety > Fact > Brand > Manager instruction > Platform optimization > Engagement`

「高反応だから安全ルールを緩める」は禁止。

---

# 49. AI生成時の最低出力スキーマ例

```json
{
  "strategy": {
    "primary_angle": "child_experience",
    "secondary_angles": ["ohana_brand", "recruiting_brand"],
    "reason": "..."
  },
  "channels": [
    {
      "channel": "instagram",
      "caption": "...",
      "hashtags": ["#...", "#..."],
      "mentions": [],
      "location": "大和オハナ保育園",
      "media_ids": ["..."],
      "publish_at": "...",
      "cta": null
    }
  ],
  "safety": {
    "status": "PASS",
    "checks": []
  },
  "facts": {
    "verified": [],
    "unverified_removed": []
  }
}
```

実装ではJSON Schema / typed DTOで厳格に検証する。

---

# 50. 分析指標

「再生数」だけを成功としない。

### 主要KPI候補
- Reach
- Saves
- Shares
- Comments
- Positive comment rate
- Profile visits
- Follower growth
- Web access
- DM inquiries
- Admission interest
- Recruiting interest

媒体で取得できない指標は代替推測せず「取得不可」とする。

---

# 51. AI評価関数の考え方

バズ偏重を防ぐため単一指標にしない。

例:

```text
Content Value Score =
  0.20 * Reach Quality
+ 0.20 * Save Rate
+ 0.20 * Share Rate
+ 0.15 * Positive Engagement
+ 0.10 * Profile Intent
+ 0.10 * Inquiry Intent
+ 0.05 * Brand Diversity
```

これは実装時の例であり固定係数ではない。

ただし、安全違反がある場合はスコアに関係なく公開不可。

---

# 52. STUDIO連携の推奨実装

第一候補:

```text
Ohana Works DB
   ↓
Public Content API
   ↓
STUDIO Data Connect API
   ↓
/activities
/activities/{slug}
```

### Public Content API
公開済みデータだけ返す。

公開前・個人情報・内部コメント等は絶対に返さない。

### ページデータ例
- slug
- title
- facility
- published_at
- activity_date
- hero_image_url
- body
- tags
- meta_title
- meta_description
- alt_text
- structured_data

実装前に現STUDIO契約プランがBusiness以上か確認する。

---

# 53. Google Business Profile投稿

4園それぞれlocation IDを保持。

AIが活動の施設を判断し、関連するBusiness Profileへ投稿。

共通アカウントだからといって4園すべてに同じ投稿を機械配信しない。

複数施設の内容の場合:
- 各施設向けに編集して複数Locationへ出す
- または最も関連する施設のみ

をAIが判断し、管理者承認画面で確認可能にする。

---

# 54. Instagram / Facebook

Instagramを主要SNSとする。

既存Facebook自動連携がある場合、
- Meta側の既存クロスポストを継続するか
- Ohana Worksから各媒体へ個別投稿するか

を実装前に確認。

重複投稿を絶対に防ぐ。

長期的にはOhana WorksからInstagram/Facebookを個別チャネルとして扱える構造を推奨する。

---

# 55. TikTok / YouTube導入条件

初期リリースに必須としない。

導入条件:
- 公式アカウント作成
- API利用申請
- OAuth
- 必要なアプリ監査
- 公開投稿可否確認
- 子どもが主となる動画のプラットフォームポリシー確認
- 運用成果の目的設定

準備完了後にチャネルアダプタを追加する。

---

# 56. 実装フェーズ

## Phase 0: 現行Ohana Works調査
- 現DB
- クラス活動
- 写真保存
- 権限
- 保護者同意
- 施設情報
- 管理者ロール
- 現在のAI機能
- インフラ
- ストレージ
- ジョブ/Queue
- 通知
- 認証

## Phase 1: SNS広報コア
- クラス活動→投稿候補
- 自由投稿
- 写真
- AI文章生成
- 安全チェック
- 管理者承認
- Instagram
- Facebook
- Scheduler
- History

## Phase 2: 広報ダッシュボード
- Analytics
- コメント
- DM
- Google口コミ
- SLA
- AI改善

## Phase 3: Google / Web
- Google Business Profile
- STUDIO公開API
- SEO記事
- MEO

## Phase 4: 動画AI
- 動画upload
- AI編集
- Reels
- media lifecycle
- BGM
- safety

## Phase 5: 外部動画SNS
- YouTube Shorts
- TikTok

フェーズ分割は実装リスクを抑えるための推奨であり、既存コード状況によりClaude Codeが最適化してよい。

---

# 57. 実装開始前にClaude Codeが必ず確認する事項

本設計書だけを見て既存実装を推測しない。

リポジトリを調査し、最低以下を確認する。

1. 技術スタック
2. DB
3. ORM
4. Storage
5. Auth
6. Role / Permission
7. Facility model
8. Child model
9. Class model
10. Class Activity model
11. Media model
12. Parent consent model
13. AI provider / abstraction
14. background job / scheduler
15. push / notification infrastructure
16. audit log
17. admin UI
18. parent app/API
19. secrets
20. deployment
21. current Instagram/Facebook integration
22. current external API integration style

既存機能を壊さず、既存データを再利用する。

---

# 58. 現行実装確認後に再質問が必要な項目

以下は現時点でユーザーへ再質問せず、まずコード・DBを確認する。

- クラス活動の現在の入力項目
- 写真アップロード枚数
- 動画対応有無
- SNS同意管理の現在モデル
- 施設マスター不足項目
- 保護者アプリのクラス活動公開仕様
- STUDIOプラン
- Meta Appの有無
- Google Business Profile API接続状態
- Instagram Professional account / Facebook Page関係
- 過去Instagram insights取得可能範囲
- ストレージ契約・費用

コード調査で解決できない点だけユーザーへ質問する。

---

# 59. 非機能要件

## Security
- 最小権限
- token encryption
- audit
- access control
- media signed URL
- PII minimization

## Reliability
- retry
- queue
- idempotency
- scheduled publishing persistence
- failure isolation

## Maintainability
- platform adapter pattern
- prompt versioning
- policy versioning
- model abstraction
- schema validation

## Observability
- publish logs
- API latency
- API failure
- AI generation failure
- safety block rate
- approval rate
- cost tracking

## Cost
AI動画処理・画像解析はコスト増大要因。

- 生成前の軽量判定
- batch processing
- media lifecycle
- unnecessary re-analysis avoidance
- cached metadata

を設計する。

---

# 60. 重要な実装原則

1. **Ohana Worksを情報の正本にする**
2. **SNSのためだけの二重入力を増やさない**
3. **AIが推測で事実を作らない**
4. **AIが安全ルールを自己変更しない**
5. **管理者承認なしに公開しない**
6. **投稿は媒体ごとに最適化する**
7. **バズではなく保育価値の伝達を優先する**
8. **過去実績からAIが継続改善する**
9. **変動情報は古い回答を事実として使わない**
10. **重要問い合わせを埋もれさせない**
11. **外部API障害を前提にする**
12. **子どもの安全・個人情報をエンゲージメントより優先する**
13. **既存Ohana Worksのコード・DB確認後に実装詳細を決定する**
14. **API仕様は実装直前に公式情報で再確認する**

---

# 61. Claude / Claude Codeへの実装指示

この設計書を受け取ったClaude / Claude Codeは、直ちに新規コードを書き始めるのではなく、以下の順序で作業すること。

### Step 1
既存Ohana Worksリポジトリを解析する。

### Step 2
本設計の要件と既存機能を比較し、

- 既存で実現済み
- 改修
- 新規
- 外部API準備
- ユーザー確認必要

に分類する。

### Step 3
DB変更案、API変更案、画面変更案、Job/Queue、Storage、AI Pipelineを提示する。

### Step 4
個人情報・同意・権限・公開フローについて影響範囲を確認する。

### Step 5
外部APIについて最新公式ドキュメントを再確認する。

### Step 6
実装を小さな単位に分割し、既存テストを壊さない形で進める。

### Step 7
各フェーズで以下をテストする。

- 正常投稿
- 承認拒否
- AI再生成
- 投稿予約
- API失敗
- token失効
- 二重投稿防止
- NG園児
- 第三者
- 個人名
- 事実誤認
- 位置情報
- 不適切発言
- DM変動情報
- SLA期限
- 高リスクコメント
- media expiry

---

# 62. 初期受入テスト例

## Case 1: 通常クラス活動
写真3枚＋活動記録
→ AI生成
→ 安全PASS
→ 管理者編集
→ 19:30予約
→ Instagram公開
→ Facebook公開
→ URL保存

## Case 2: 複数施設
大和オハナ保育園＋Haleleaの写真
→ 1投稿
→ 各施設の活動が明確に分かれる文章
→ 施設混同なし

## Case 3: 写真なし
活動記録のみ
→ 原則投稿候補から除外

## Case 4: 園児名
元文章に園児名
→ SNS文章から完全除去

## Case 5: SNS掲載NG可能性
AI安全検出
→ 投稿停止
→ マスキング候補
→ 再チェック
→ 管理者承認

## Case 6: 第三者
公園写真に識別可能な第三者
→ 自動ぼかし
→ 再安全チェック

## Case 7: 根拠なし比較
AIが「地域唯一」を生成
→ Fact/Safety Gateで拒否
→ 表現修正

## Case 8: 承認遅延
推奨時間を過ぎる
→ 翌日以降に再提案

## Case 9: 自由投稿
「0歳児募集を地域向けに発信」
→ 管理者指定日時
→ AI媒体選択
→ 管理者承認
→ 投稿

## Case 10: 入園DM
「0歳児空いていますか？」
→ 過去投稿から回答しない
→ 管理者へ現状確認
→ AI返信案
→ 承認
→ 返信

## Case 11: 誹謗中傷
→ 通常返信案ではなくRisk Review
→ 管理者へ対応案

## Case 12: 動画
動画素材
→ AI編集
→ BGMライセンス確認
→ 不要音声処理
→ Reels
→ 公開30日後元動画削除

---

# 63. 今後の追加確認

本仕様書はSNS広報機能の初期設計として十分な要件を含む。

次の大きな作業は「追加質問」ではなく、**現行Ohana Worksのコード・DB・画面構成とのFit & Gap分析**である。

Fit & Gap後に不足情報が発生した場合のみ追加確認する。

---

# 64. 公式資料（2026-08-09時点・実装前に再確認）

- Meta Instagram Content Publishing  
  https://developers.facebook.com/documentation/instagram-platform/content-publishing

- Meta Facebook Pages API / Posts  
  https://developers.facebook.com/documentation/pages-api/posts

- Google Business Profile - Create Posts  
  https://developers.google.com/my-business/content/posts-data

- Google Business Profile - localPosts.create  
  https://developers.google.com/my-business/reference/rest/v4/accounts.locations.localPosts/create

- STUDIO Data Connect API  
  https://help.studio.design/ja/articles/6500751-data-connect-api-api%E9%80%A3%E6%90%BA

- TikTok Content Posting API  
  https://developers.tiktok.com/products/content-posting-api

- TikTok Direct Post  
  https://developers.tiktok.com/doc/content-posting-api-reference-direct-post

- YouTube Data API - Uploading a Video  
  https://developers.google.com/youtube/v3/guides/uploading_a_video

---

# 65. 最終定義

この機能は「SNS自動投稿機能」ではなく、

> **Ohana Works AI広報エンジン**

として設計する。

日々の保育活動を、
「保育記録」から
「子どもの経験を伝える広報資産」へ変換し、

- Ohanaの知名度
- 地域とのつながり
- 園児募集
- 採用
- ブランド
- 検索発見性

を長期的に向上させる。

AIは広報担当者の代替ではなく、素材の理解、編集、配信最適化、分析、継続改善を担う。

最終責任は人間の管理者が持ち、

**安全・事実・子どもの尊厳・Ohanaらしさを守ったうえで、AIが広報方法を継続的に進化させるシステム**とする。
