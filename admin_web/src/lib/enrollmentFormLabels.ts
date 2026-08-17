// 入園時基本情報フォーム(218)のセクション・項目ラベル。
// 正本の項目定義は parent_app/lib/screens/enrollment/enrollment_form_definition.dart(草案§8-9)。
// ここは園側確認画面の表示用ミラー(キー契約はサーバRPCと共通)。

export const ENROLLMENT_SECTION_LABELS: Record<string, string> = {
  basic: "園児基本情報",
  address: "住所・世帯情報",
  guardians: "保護者・勤務先・連絡先",
  pickup: "緊急連絡先・送迎・引き渡し",
  family: "家族・兄弟姉妹",
  birth_growth: "出生・生育歴",
  health: "健康・医療・アレルギー",
  lifestyle: "食事・睡眠・排泄・生活習慣",
  thoughts: "性格・遊び・家庭の希望",
  checkups: "健診・予防接種",
};

// セクション表示順(JSONBキー順は不定のため)
export const ENROLLMENT_SECTION_ORDER = [
  "basic",
  "address",
  "guardians",
  "pickup",
  "family",
  "birth_growth",
  "health",
  "lifestyle",
  "thoughts",
  "checkups",
];

export const ENROLLMENT_FIELD_LABELS: Record<string, string> = {
  // basic
  full_name: "園児氏名",
  name_kana: "ふりがな",
  nickname: "愛称",
  gender: "性別",
  birth_date: "生年月日",
  // address
  postal_code: "郵便番号",
  prefecture: "都道府県",
  city: "市区町村",
  town: "町域",
  address_line: "番地",
  building: "建物名",
  child_same: "園児住所は世帯と同じ",
  child_address: "園児住所",
  // guardians(配列要素)
  name: "氏名",
  relationship: "続柄",
  living: "同居・別居",
  is_representative: "代表保護者",
  priority: "連絡優先順位",
  phone_mobile: "携帯電話",
  phone_home: "自宅電話",
  email: "メール",
  work_name: "勤務先名",
  work_phone: "勤務先電話",
  work_mobile: "勤務先直通携帯",
  work_postal: "勤務先郵便番号",
  work_address: "勤務先住所",
  work_note: "勤務先補足",
  // pickup
  drop_person: "通常の送り担当",
  pickup_person: "通常の迎え担当",
  method: "通園方法",
  duration: "所要時間",
  phone: "電話番号",
  id_note: "本人確認情報",
  // family
  occupation_school: "職業・学校等",
  sibling_facility: "在籍施設",
  // birth_growth
  gestational_weeks: "在胎週数",
  birth_order: "第何子",
  birth_height: "出生時身長",
  birth_weight: "出生時体重",
  newborn_notes: "新生児期の特記",
  feeding_method: "授乳方法",
  weaning_age: "断乳・離乳時期",
  baby_food_start: "離乳食開始",
  milestones: "発達の時期",
  care_history: "養育者・生育環境",
  // health
  doctor_name: "かかりつけ医",
  doctor_phone: "かかりつけ医電話",
  doctor_address: "かかりつけ医住所",
  medical_history: "既往歴",
  episode_notes: "けいれん・脱臼等",
  has_allergy: "アレルギーあり",
  allergy_foods: "原因食材・物質",
  allergy_diagnosed: "医師の診断あり",
  allergy_doc_state: "診断書の提出状況",
  care_notes: "園生活上の注意",
  normal_temp: "平熱(℃)",
  high_temp_acknowledged: "高体温注意の確認",
  condition: "使用条件・時期",
  note: "配慮・参照情報",
  // lifestyle
  feeding: "授乳",
  meal: "食事",
  self_feeding: "自分で食べる状況",
  likes_dislikes: "好き嫌い・間食",
  sleep: "睡眠",
  excretion: "排泄",
  hygiene: "清潔習慣",
  clothing: "着脱",
  language: "言葉",
  social: "人との関わり",
  play: "遊び",
  // thoughts
  good_points: "良いところ",
  worries: "心配・気になる癖",
  hopes: "育ってほしい姿",
  values: "大切にしていること",
  requests: "園への希望",
  health_notes: "健康上の特記",
  other: "その他",
  // checkups
  checkup_3_4m: "3〜4か月児健診",
  checkup_6_7m: "6〜7か月児健診",
  checkup_9_10m: "9〜10か月児健診",
  checkup_18m: "1歳6か月児健診",
  checkup_3y: "3歳児健診",
  vac_hib: "ヒブ",
  vac_pneumo: "小児用肺炎球菌",
  vac_hepb: "B型肝炎",
  vac_rota: "ロタウイルス",
  vac_dpt: "四種混合(五種混合)",
  vac_bcg: "BCG",
  vac_mr: "麻しん風しん(MR)",
  vac_varicella: "水痘",
  vac_je: "日本脳炎",
  vac_notes: "補足",
  // pickup内配列
  emergency: "緊急連絡先",
  proxies: "代理送迎者",
  medication: "服薬情報",
};

export const ENROLLMENT_STATUS_LABELS: Record<string, string> = {
  draft: "入力中",
  submitted: "提出済み(確認待ち)",
  sent_back: "差し戻し中",
  approved: "承認済み",
  cancelled: "取消",
};

export function enrollmentFieldLabel(key: string): string {
  return ENROLLMENT_FIELD_LABELS[key] ?? key;
}
