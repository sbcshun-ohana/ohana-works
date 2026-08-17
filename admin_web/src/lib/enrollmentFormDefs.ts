// 入園時基本情報フォームの編集用フィールド定義(園側修正モーダル用)。
// 正本の定義は parent_app/lib/screens/enrollment/enrollment_form_definition.dart(キー契約はサーバRPCと共通)。
// ラベルのみのミラーは enrollmentFormLabels.ts(閲覧用)。こちらは入力タイプ・選択肢を含む編集用ミラー。

export type EditFieldType = "text" | "multiline" | "select" | "toggle" | "date" | "number";

export type EditFieldDef = {
  key: string;
  label: string;
  type?: EditFieldType;
  options?: string[];
  visibleWhenKey?: string;
  visibleWhenEquals?: string;
};

export type EditListGroupDef = {
  listKey: string; // ""=セクション自体が配列
  itemLabel: string;
  itemFields: EditFieldDef[];
};

export type EditSectionDef = {
  key: string;
  title: string;
  fields?: EditFieldDef[];
  listGroups?: EditListGroupDef[];
  isArray?: boolean; // guardians / family: セクション直下が配列
  itemLabel?: string;
  itemFields?: EditFieldDef[];
};

export const ENROLLMENT_EDIT_SECTIONS: EditSectionDef[] = [
  {
    key: "basic",
    title: "園児基本情報",
    fields: [
      { key: "full_name", label: "園児氏名" },
      { key: "name_kana", label: "ふりがな" },
      { key: "nickname", label: "愛称(呼び名)" },
      { key: "gender", label: "性別", type: "select", options: ["男", "女", "その他"] },
      { key: "birth_date", label: "生年月日", type: "date" },
    ],
  },
  {
    key: "address",
    title: "住所・世帯情報",
    fields: [
      { key: "postal_code", label: "世帯郵便番号" },
      { key: "prefecture", label: "都道府県" },
      { key: "city", label: "市区町村" },
      { key: "town", label: "町域" },
      { key: "address_line", label: "番地" },
      { key: "building", label: "建物名・部屋番号" },
      { key: "child_same", label: "園児住所は世帯と同じ", type: "toggle" },
      { key: "child_address", label: "園児住所(異なる場合)", type: "multiline" },
    ],
  },
  {
    key: "guardians",
    title: "保護者・勤務先・連絡先",
    isArray: true,
    itemLabel: "保護者",
    itemFields: [
      { key: "name", label: "氏名" },
      { key: "name_kana", label: "ふりがな" },
      { key: "relationship", label: "続柄" },
      { key: "living", label: "同居・別居", type: "select", options: ["同居", "別居"] },
      { key: "is_representative", label: "代表保護者", type: "toggle" },
      { key: "priority", label: "連絡優先順位" },
      { key: "phone_mobile", label: "携帯電話番号" },
      { key: "phone_home", label: "自宅電話番号" },
      { key: "email", label: "メールアドレス" },
      { key: "work_name", label: "勤務先名" },
      { key: "work_phone", label: "勤務先電話番号" },
      { key: "work_mobile", label: "勤務先直通携帯" },
      { key: "work_postal", label: "勤務先郵便番号" },
      { key: "work_address", label: "勤務先住所", type: "multiline" },
      { key: "work_note", label: "勤務先補足" },
    ],
  },
  {
    key: "pickup",
    title: "緊急連絡先・送迎・引き渡し",
    fields: [
      { key: "drop_person", label: "通常の送り担当者" },
      { key: "pickup_person", label: "通常の迎え担当者" },
      { key: "method", label: "通園方法", type: "select", options: ["徒歩", "自転車", "自動車", "公共交通機関"] },
      { key: "car_number", label: "車両ナンバー", visibleWhenKey: "method", visibleWhenEquals: "自動車" },
      { key: "car_model", label: "車種・色", visibleWhenKey: "method", visibleWhenEquals: "自動車" },
      { key: "car_driver", label: "主な運転者", visibleWhenKey: "method", visibleWhenEquals: "自動車" },
      { key: "car_parking_agreed", label: "駐車場注意事項に同意", type: "toggle", visibleWhenKey: "method", visibleWhenEquals: "自動車" },
      { key: "bicycle_acknowledged", label: "自転車注意事項を確認", type: "toggle", visibleWhenKey: "method", visibleWhenEquals: "自転車" },
      { key: "duration", label: "所要時間" },
    ],
    listGroups: [
      {
        listKey: "emergency",
        itemLabel: "緊急連絡先(上から優先順位順)",
        itemFields: [
          { key: "name", label: "氏名(会社等の場合は会社名)" },
          { key: "relationship", label: "続柄・園児との関係" },
          { key: "phone", label: "電話番号" },
        ],
      },
      {
        listKey: "proxies",
        itemLabel: "代理送迎者・引き渡し可能者",
        itemFields: [
          { key: "name", label: "氏名" },
          { key: "relationship", label: "続柄" },
          { key: "phone", label: "電話番号" },
          { key: "id_note", label: "本人確認に使う情報" },
        ],
      },
    ],
  },
  {
    key: "family",
    title: "家族・兄弟姉妹",
    isArray: true,
    itemLabel: "同居家族・兄弟姉妹",
    itemFields: [
      { key: "name", label: "氏名" },
      { key: "name_kana", label: "ふりがな" },
      { key: "relationship", label: "続柄" },
      { key: "birth_date", label: "生年月日", type: "date" },
      { key: "occupation_school", label: "職業または学校等" },
      { key: "sibling_facility", label: "在籍施設(保育園・学校等)" },
    ],
  },
  {
    key: "birth_growth",
    title: "出生・生育歴",
    fields: [
      { key: "gestational_weeks", label: "在胎週数" },
      { key: "birth_order", label: "第何子か" },
      { key: "birth_height", label: "出生時身長(cm)" },
      { key: "birth_weight", label: "出生時体重(g)" },
      { key: "newborn_notes", label: "出生時・新生児期の特記事項", type: "multiline" },
      { key: "feeding_method", label: "授乳方法", type: "select", options: ["母乳", "混合", "人工"] },
      { key: "weaning_age", label: "断乳・離乳時期" },
      { key: "baby_food_start", label: "離乳食開始時期" },
      { key: "milestones", label: "首すわり・おすわり・はいはい・初歯・初語等の時期", type: "multiline" },
      { key: "care_history", label: "これまでの養育者・生育環境", type: "multiline" },
    ],
  },
  {
    key: "health",
    title: "健康・医療・アレルギー",
    fields: [
      { key: "doctor_name", label: "かかりつけ医(医療機関名)" },
      { key: "doctor_phone", label: "かかりつけ医 電話番号" },
      { key: "doctor_address", label: "かかりつけ医 住所", type: "multiline" },
      { key: "medical_history", label: "既往歴・発症時期・現在の状態", type: "multiline" },
      { key: "episode_notes", label: "けいれん・脱臼・繰り返しやすい疾病等", type: "multiline" },
      { key: "has_allergy", label: "アレルギーあり", type: "toggle" },
      { key: "allergy_foods", label: "疑われる原因食材または物質", type: "multiline" },
      { key: "allergy_diagnosed", label: "医師の診断あり", type: "toggle" },
      { key: "allergy_doc_state", label: "診断書の提出状況", type: "select", options: ["未提出", "提出予定", "提出済み"] },
      { key: "care_notes", label: "園生活上の注意事項", type: "multiline" },
      { key: "normal_temp", label: "平熱(℃)" },
    ],
    listGroups: [
      {
        listKey: "medication",
        itemLabel: "服薬情報",
        itemFields: [
          { key: "name", label: "薬品名" },
          { key: "condition", label: "使用条件・使用時期" },
          { key: "note", label: "園で必要となる配慮・参照情報", type: "multiline" },
        ],
      },
    ],
  },
  {
    key: "lifestyle",
    title: "食事・睡眠・排泄・生活習慣",
    fields: [
      { key: "feeding", label: "授乳(回数・量・夜間授乳・使用ミルク)", type: "multiline" },
      { key: "meal", label: "離乳食・食事(回数・量・食べ方)", type: "multiline" },
      { key: "self_feeding", label: "自分で食べる状況・使用器具・食事中の様子", type: "multiline" },
      { key: "likes_dislikes", label: "好きな食べ物・苦手な食べ物・間食", type: "multiline" },
      { key: "sleep", label: "起床・就寝・昼寝・寝る姿勢・添い寝等", type: "multiline" },
      { key: "excretion", label: "排尿・排便・おむつ・排泄の自立状況", type: "multiline" },
      { key: "hygiene", label: "手洗い・洗顔・うがい・歯磨き等", type: "multiline" },
      { key: "clothing", label: "着脱できる衣類・援助が必要な衣類", type: "multiline" },
      { key: "language", label: "言葉の発達や伝わり方", type: "multiline" },
      { key: "social", label: "人見知り・他児との遊び・大人との関わり", type: "multiline" },
      { key: "play", label: "好きな遊び・玩具・興味", type: "multiline" },
    ],
  },
  {
    key: "thoughts",
    title: "性格・遊び・家庭の希望",
    fields: [
      { key: "good_points", label: "保護者から見た園児の良いところ", type: "multiline" },
      { key: "worries", label: "心配していること・気になる癖", type: "multiline" },
      { key: "hopes", label: "どのように育ってほしいか", type: "multiline" },
      { key: "values", label: "子育てで大切にしていること", type: "multiline" },
      { key: "requests", label: "園への希望", type: "multiline" },
      { key: "health_notes", label: "健康・身体上の特記事項", type: "multiline" },
      { key: "other", label: "その他伝えておきたいこと", type: "multiline" },
    ],
  },
  {
    key: "checkups",
    title: "健診・予防接種",
    fields: [
      { key: "checkup_3_4m", label: "3〜4か月児健診", type: "toggle" },
      { key: "checkup_6_7m", label: "6〜7か月児健診", type: "toggle" },
      { key: "checkup_9_10m", label: "9〜10か月児健診", type: "toggle" },
      { key: "checkup_18m", label: "1歳6か月児健診", type: "toggle" },
      { key: "checkup_3y", label: "3歳児健診", type: "toggle" },
      { key: "vac_hib", label: "ヒブ", type: "toggle" },
      { key: "vac_pneumo", label: "小児用肺炎球菌", type: "toggle" },
      { key: "vac_hepb", label: "B型肝炎", type: "toggle" },
      { key: "vac_rota", label: "ロタウイルス", type: "toggle" },
      { key: "vac_dpt", label: "四種混合(五種混合)", type: "toggle" },
      { key: "vac_bcg", label: "BCG", type: "toggle" },
      { key: "vac_mr", label: "麻しん風しん(MR)", type: "toggle" },
      { key: "vac_varicella", label: "水痘", type: "toggle" },
      { key: "vac_je", label: "日本脳炎", type: "toggle" },
      { key: "vac_notes", label: "補足(その他の接種等)", type: "multiline" },
    ],
  },
];
