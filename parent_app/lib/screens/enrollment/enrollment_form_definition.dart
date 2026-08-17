/// 入園時基本情報フォームの宣言的定義(草案§8-9)。
/// 10ステップ×フィールド定義から画面を機械的に描画する。
/// key はセクションJSONB内のキー(サーバの submit_enrollment_form / approve_enrollment_form と契約)。
library;

enum FieldType { text, kana, multiline, phone, email, number, date, select, toggle, postal }

class FieldDef {
  const FieldDef(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.options,
    this.hint,
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final List<String>? options;
  final String? hint;
}

/// 繰り返しグループ(保護者・緊急連絡先・代理送迎者・家族など)。
class ListGroupDef {
  const ListGroupDef({
    required this.listKey,
    required this.itemLabel,
    required this.itemFields,
    this.minItems = 0,
    this.note,
  });

  /// セクション内の配列キー(例: guardians は section 直下が配列)。
  final String listKey;
  final String itemLabel;
  final List<FieldDef> itemFields;
  final int minItems;
  final String? note;
}

class StepDef {
  const StepDef({
    required this.title,
    required this.sectionKey,
    this.note,
    this.fields = const [],
    this.listGroups = const [],
    this.isConfirmStep = false,
  });

  final String title;

  /// form_data 直下のセクションキー。listGroups だけのステップでも必要。
  final String sectionKey;
  final String? note;
  final List<FieldDef> fields;
  final List<ListGroupDef> listGroups;
  final bool isConfirmStep;
}

const enrollmentSteps = <StepDef>[
  StepDef(
    title: '園児基本情報',
    sectionKey: 'basic',
    fields: [
      FieldDef('full_name', '園児氏名', required: true, hint: '園が仮登録した氏名が初期表示されます'),
      FieldDef('name_kana', 'ふりがな', type: FieldType.kana, required: true, hint: '全角ひらがな'),
      FieldDef('nickname', '愛称(日常保育での呼び名)'),
      FieldDef('gender', '性別', type: FieldType.select, required: true, options: ['男', '女', 'その他']),
      FieldDef('birth_date', '生年月日', type: FieldType.date, required: true),
    ],
  ),
  StepDef(
    title: '住所・世帯情報',
    sectionKey: 'address',
    note: '郵便番号を入力して「住所検索」を押すと都道府県・市区町村・町域が自動入力されます',
    fields: [
      FieldDef('postal_code', '世帯郵便番号', type: FieldType.postal, required: true, hint: '例: 2420001(ハイフン不要)'),
      FieldDef('prefecture', '都道府県'),
      FieldDef('city', '市区町村'),
      FieldDef('town', '町域'),
      FieldDef('address_line', '番地'),
      FieldDef('building', '建物名・部屋番号'),
      FieldDef('child_same', '園児の住所は世帯住所と同じ', type: FieldType.toggle),
      FieldDef('child_address', '園児住所(別居等で異なる場合)', type: FieldType.multiline),
    ],
  ),
  StepDef(
    title: '保護者・勤務先・連絡先',
    sectionKey: 'guardians',
    listGroups: [
      ListGroupDef(
        listKey: '',
        itemLabel: '保護者',
        minItems: 1,
        note: '保護者は複数人登録できます。園児台帳から電話をかけられるよう、番号の種別ごとにご入力ください',
        itemFields: [
          FieldDef('name', '氏名', required: true),
          FieldDef('name_kana', 'ふりがな', type: FieldType.kana),
          FieldDef('relationship', '園児との続柄', hint: '例: 母・父・祖母'),
          FieldDef('living', '同居・別居', type: FieldType.select, options: ['同居', '別居']),
          FieldDef('is_representative', '代表保護者', type: FieldType.toggle),
          FieldDef('priority', '連絡優先順位', type: FieldType.number, hint: '1が最優先'),
          FieldDef('phone_mobile', '携帯電話番号', type: FieldType.phone),
          FieldDef('phone_home', '自宅電話番号', type: FieldType.phone),
          FieldDef('email', 'メールアドレス', type: FieldType.email),
          FieldDef('work_name', '勤務先名'),
          FieldDef('work_phone', '勤務先電話番号', type: FieldType.phone),
          FieldDef('work_mobile', '勤務先の直通携帯', type: FieldType.phone),
          FieldDef('work_postal', '勤務先郵便番号'),
          FieldDef('work_address', '勤務先住所', type: FieldType.multiline),
          FieldDef('work_note', '勤務先部署名等の補足'),
        ],
      ),
    ],
  ),
  StepDef(
    title: '緊急連絡先・送迎・引き渡し',
    sectionKey: 'pickup',
    fields: [
      FieldDef('drop_person', '通常の送り担当者'),
      FieldDef('pickup_person', '通常の迎え担当者'),
      FieldDef('method', '通園方法', hint: '例: 徒歩・自転車・車'),
      FieldDef('duration', '所要時間', hint: '例: 10分'),
    ],
    listGroups: [
      ListGroupDef(
        listKey: 'emergency',
        itemLabel: '緊急連絡先',
        note: '保護者に連絡がつかない場合の連絡先です',
        itemFields: [
          FieldDef('name', '氏名', required: true),
          FieldDef('relationship', '続柄'),
          FieldDef('phone', '電話番号', type: FieldType.phone),
          FieldDef('priority', '連絡優先順位', type: FieldType.number),
        ],
      ),
      ListGroupDef(
        listKey: 'proxies',
        itemLabel: '代理送迎者・引き渡し可能者',
        note: '保護者以外でお迎えの可能性がある方を登録してください(承認後、お迎え者名簿に反映されます)',
        itemFields: [
          FieldDef('name', '氏名', required: true),
          FieldDef('relationship', '続柄'),
          FieldDef('phone', '電話番号', type: FieldType.phone),
          FieldDef('id_note', '本人確認に使う情報', hint: '例: 運転免許証'),
        ],
      ),
    ],
  ),
  StepDef(
    title: '家族・兄弟姉妹',
    sectionKey: 'family',
    listGroups: [
      ListGroupDef(
        listKey: '',
        itemLabel: '同居家族・兄弟姉妹',
        itemFields: [
          FieldDef('name', '氏名', required: true),
          FieldDef('name_kana', 'ふりがな', type: FieldType.kana),
          FieldDef('relationship', '続柄'),
          FieldDef('birth_date', '生年月日', type: FieldType.date),
          FieldDef('occupation_school', '職業または学校等'),
          FieldDef('sibling_facility', '在籍施設(兄弟姉妹の場合)'),
        ],
      ),
    ],
  ),
  StepDef(
    title: '出生・生育歴',
    sectionKey: 'birth_growth',
    fields: [
      FieldDef('gestational_weeks', '在胎週数', type: FieldType.number, hint: '例: 39'),
      FieldDef('birth_order', '第何子か', type: FieldType.number),
      FieldDef('birth_height', '出生時身長(cm)', type: FieldType.number),
      FieldDef('birth_weight', '出生時体重(g)', type: FieldType.number),
      FieldDef('newborn_notes', '出生時・新生児期の特記事項', type: FieldType.multiline),
      FieldDef('feeding_method', '授乳方法', type: FieldType.select, options: ['母乳', '混合', '人工']),
      FieldDef('weaning_age', '断乳・離乳時期', hint: '例: 1歳2か月'),
      FieldDef('baby_food_start', '離乳食開始時期', hint: '例: 6か月'),
      FieldDef('milestones', '首すわり・おすわり・はいはい・初歯・初語等の時期', type: FieldType.multiline),
      FieldDef('care_history', 'これまでの養育者・生育環境', type: FieldType.multiline),
    ],
  ),
  StepDef(
    title: '健康・医療・アレルギー',
    sectionKey: 'health',
    fields: [
      FieldDef('doctor_name', 'かかりつけ医(医療機関名)'),
      FieldDef('doctor_phone', 'かかりつけ医 電話番号', type: FieldType.phone),
      FieldDef('doctor_address', 'かかりつけ医 住所', type: FieldType.multiline),
      FieldDef('medical_history', '既往歴・発症時期・現在の状態', type: FieldType.multiline),
      FieldDef('episode_notes', 'けいれん・脱臼・繰り返しやすい疾病等', type: FieldType.multiline),
      FieldDef('has_allergy', 'アレルギーあり', type: FieldType.toggle),
      FieldDef('allergy_foods', '疑われる原因食材または物質', type: FieldType.multiline),
      FieldDef('allergy_diagnosed', '医師の診断あり', type: FieldType.toggle),
      FieldDef('allergy_doc_state', '診断書の提出状況', type: FieldType.select, options: ['未提出', '提出予定', '提出済み']),
      FieldDef('care_notes', '園生活上の注意事項', type: FieldType.multiline),
      FieldDef('normal_temp', '平熱(℃)', type: FieldType.number, hint: '例: 36.5(小数第1位まで)'),
    ],
    listGroups: [
      ListGroupDef(
        listKey: 'medication',
        itemLabel: '服薬情報',
        note: '緊急時や保育上の配慮のための参照情報です(園職員は医療行為を行いません)',
        itemFields: [
          FieldDef('name', '薬品名', required: true),
          FieldDef('condition', '使用条件・使用時期'),
          FieldDef('note', '園で必要となる配慮・参照情報', type: FieldType.multiline),
        ],
      ),
    ],
  ),
  StepDef(
    title: '食事・睡眠・排泄・生活習慣',
    sectionKey: 'lifestyle',
    note: '現在のご家庭での様子をお書きください',
    fields: [
      FieldDef('feeding', '授乳(回数・量・夜間授乳・使用ミルク)', type: FieldType.multiline),
      FieldDef('meal', '離乳食・食事(回数・量・食べ方)', type: FieldType.multiline),
      FieldDef('self_feeding', '自分で食べる状況・使用器具・食事中の様子', type: FieldType.multiline),
      FieldDef('likes_dislikes', '好きな食べ物・苦手な食べ物・間食', type: FieldType.multiline),
      FieldDef('sleep', '起床・就寝・昼寝・寝る姿勢・添い寝等', type: FieldType.multiline),
      FieldDef('excretion', '排尿・排便・おむつ・排泄の自立状況', type: FieldType.multiline),
      FieldDef('hygiene', '手洗い・洗顔・うがい・歯磨き等', type: FieldType.multiline),
      FieldDef('clothing', '着脱できる衣類・援助が必要な衣類', type: FieldType.multiline),
      FieldDef('language', '言葉の発達や伝わり方', type: FieldType.multiline),
      FieldDef('social', '人見知り・他児との遊び・大人との関わり', type: FieldType.multiline),
      FieldDef('play', '好きな遊び・玩具・興味', type: FieldType.multiline),
    ],
  ),
  StepDef(
    title: '性格・遊び・家庭の希望',
    sectionKey: 'thoughts',
    fields: [
      FieldDef('good_points', '保護者から見た園児の良いところ', type: FieldType.multiline),
      FieldDef('worries', '心配していること・気になる癖', type: FieldType.multiline),
      FieldDef('hopes', 'どのように育ってほしいか', type: FieldType.multiline),
      FieldDef('values', '子育てで大切にしていること', type: FieldType.multiline),
      FieldDef('requests', '園への希望', type: FieldType.multiline),
      FieldDef('health_notes', '健康・身体上の特記事項', type: FieldType.multiline),
      FieldDef('other', 'その他伝えておきたいこと', type: FieldType.multiline),
    ],
  ),
  StepDef(
    title: '健診・予防接種',
    sectionKey: 'checkups',
    note: '各健診・予防接種を「受けた」場合はオンにしてください(接種日等の詳細は不要です)',
    fields: [
      FieldDef('checkup_3_4m', '3〜4か月児健診', type: FieldType.toggle),
      FieldDef('checkup_6_7m', '6〜7か月児健診', type: FieldType.toggle),
      FieldDef('checkup_9_10m', '9〜10か月児健診', type: FieldType.toggle),
      FieldDef('checkup_18m', '1歳6か月児健診', type: FieldType.toggle),
      FieldDef('checkup_3y', '3歳児健診', type: FieldType.toggle),
      FieldDef('vac_hib', 'ヒブ', type: FieldType.toggle),
      FieldDef('vac_pneumo', '小児用肺炎球菌', type: FieldType.toggle),
      FieldDef('vac_hepb', 'B型肝炎', type: FieldType.toggle),
      FieldDef('vac_rota', 'ロタウイルス', type: FieldType.toggle),
      FieldDef('vac_dpt', '四種混合(五種混合)', type: FieldType.toggle),
      FieldDef('vac_bcg', 'BCG', type: FieldType.toggle),
      FieldDef('vac_mr', '麻しん風しん(MR)', type: FieldType.toggle),
      FieldDef('vac_varicella', '水痘', type: FieldType.toggle),
      FieldDef('vac_je', '日本脳炎', type: FieldType.toggle),
      FieldDef('vac_notes', '補足(その他の接種等)', type: FieldType.multiline),
    ],
  ),
  StepDef(
    title: '最終確認',
    sectionKey: '_confirm',
    isConfirmStep: true,
  ),
];
