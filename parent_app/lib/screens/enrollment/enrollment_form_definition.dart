/// 入園時基本情報フォームの宣言的定義(草案§8-9)。
/// 10ステップ×フィールド定義から画面を機械的に描画する。
/// key はセクションJSONB内のキー(サーバの submit_enrollment_form / approve_enrollment_form と契約)。
library;

enum FieldType { text, kana, multiline, phone, email, number, date, select, toggle, postal, notice }

class FieldDef {
  const FieldDef(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.options,
    this.hint,
    this.visibleWhenKey,
    this.visibleWhenEquals,
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final List<String>? options;
  final String? hint;

  /// 条件表示: 同一セクション内の visibleWhenKey の値が visibleWhenEquals のときだけ表示する
  /// (例: 通園方法=自動車のときの車両情報)。非表示のときは必須チェックの対象外。
  final String? visibleWhenKey;
  final String? visibleWhenEquals;

  bool isVisible(Map<String, dynamic> section) {
    if (visibleWhenKey == null) return true;
    return (section[visibleWhenKey!] ?? '').toString() == visibleWhenEquals;
  }
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
      FieldDef('prefecture', '都道府県', required: true),
      FieldDef('city', '市区町村', required: true),
      FieldDef('town', '町域'),
      FieldDef('address_line', '番地', required: true),
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
          FieldDef('name_kana', 'ふりがな', type: FieldType.kana, required: true),
          FieldDef('relationship', '園児との続柄', required: true, hint: '例: 母・父・祖母'),
          FieldDef('living', '同居・別居', type: FieldType.select, options: ['同居', '別居']),
          FieldDef('is_representative', '代表保護者', type: FieldType.toggle),
          FieldDef('priority', '連絡優先順位', type: FieldType.number, required: true, hint: '1が最優先'),
          FieldDef('phone_mobile', '携帯電話番号', type: FieldType.phone, required: true),
          FieldDef('phone_home', '自宅電話番号', type: FieldType.phone),
          FieldDef('email', 'メールアドレス', type: FieldType.email, required: true),
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
      FieldDef('drop_person', '通常の送り担当者', required: true),
      FieldDef('pickup_person', '通常の迎え担当者', required: true),
      FieldDef('method', '通園方法', type: FieldType.select, required: true,
          options: ['徒歩', '自転車', '自動車', '公共交通機関']),
      // 自動車: このフォームの車両情報入力をもって自動車利用の届出扱いとする(俊指示 2026-08-17・別紙書類は不要)
      // notice の required:true は「必須項目グループ内に表示する」ための指定(未入力チェック対象にはならない)
      FieldDef('car_notice',
          '自動車で通園される場合は、以下の車両情報の入力が必ず必要です(この入力をもって自動車利用の届出となります)。',
          type: FieldType.notice, required: true,
          visibleWhenKey: 'method', visibleWhenEquals: '自動車'),
      FieldDef('car_number', '車両ナンバー', required: true,
          hint: '例: 相模 300 あ 12-34', visibleWhenKey: 'method', visibleWhenEquals: '自動車'),
      FieldDef('car_model', '車種・色', required: true, hint: '例: 白のフリード',
          visibleWhenKey: 'method', visibleWhenEquals: '自動車'),
      FieldDef('car_driver', '主な運転者', required: true,
          visibleWhenKey: 'method', visibleWhenEquals: '自動車'),
      // 自動車: 駐車場利用の注意+同意チェック必須(俊指示 2026-08-17)
      FieldDef('car_parking_notice',
          '保育園の専用駐車場はありません。テナントビルの共同駐車場をご利用ください。'
          '登降園の時間に駐車場に空きがない場合でも、路上駐車は絶対にしないでください。'
          '駐車場の空き待ち等によりお迎えが遅れ、延長保育となった場合は延長保育料金がかかります。\n'
          '駐車場は他のご家庭も利用します。送迎時のみのご利用とし、速やかなご退出をお願いします。'
          'お買い物など保育園の利用に関係のない目的での駐車は禁止です。'
          '入出庫の際は、小さなお子様が車の周りを歩いている場合がありますので、十分にご注意ください。\n'
          'なお、路上駐車が確認され保育園への通報等があった場合、その後の通園手段として自動車のご利用を禁止する場合があります。',
          type: FieldType.notice, required: true,
          visibleWhenKey: 'method', visibleWhenEquals: '自動車'),
      FieldDef('car_parking_agreed', '上記の駐車場利用に関する注意事項に同意します',
          type: FieldType.toggle, required: true,
          visibleWhenKey: 'method', visibleWhenEquals: '自動車'),
      // 自転車: 保険加入・ヘルメット着用の要請+確認チェック必須(俊指示 2026-08-17)
      FieldDef('bicycle_notice',
          '自転車で送迎される場合は、自転車保険へのご加入と、お子様・保護者様のヘルメット着用をお願いしています。',
          type: FieldType.notice, required: true,
          visibleWhenKey: 'method', visibleWhenEquals: '自転車'),
      FieldDef('bicycle_acknowledged', '上記の注意事項(保険加入・ヘルメット着用)を確認しました',
          type: FieldType.toggle, required: true,
          visibleWhenKey: 'method', visibleWhenEquals: '自転車'),
      FieldDef('duration', '所要時間', required: true, hint: '例: 10分'),
    ],
    listGroups: [
      ListGroupDef(
        listKey: 'emergency',
        itemLabel: '緊急連絡先',
        minItems: 3,
        note: '保護者に連絡がつかない場合の連絡先です。3件のご登録をお願いします(勤務先等の場合は会社名でご記入ください)',
        itemFields: [
          FieldDef('name', '氏名(会社等の場合は会社名)', required: true),
          FieldDef('relationship', '続柄・園児との関係', required: true, hint: '例: 祖母・母の勤務先'),
          FieldDef('phone', '電話番号', type: FieldType.phone, required: true),
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
          FieldDef('name_kana', 'ふりがな', type: FieldType.kana, required: true),
          FieldDef('relationship', '続柄', required: true),
          FieldDef('birth_date', '生年月日', type: FieldType.date, required: true),
          FieldDef('occupation_school', '職業または学校等', required: true, hint: 'ない場合は「なし」'),
          FieldDef('sibling_facility', '在籍施設(保育園・学校等)', required: true, hint: 'ない場合は「なし」'),
        ],
      ),
    ],
  ),
  StepDef(
    title: '出生・生育歴',
    sectionKey: 'birth_growth',
    // 児童票に必要な情報のため必須ベース(俊指示 2026-08-17)
    note: '児童票の作成に必要な情報です。特記が無い項目は「なし」「特になし」とご記入ください',
    fields: [
      FieldDef('gestational_weeks', '在胎週数', type: FieldType.number, required: true, hint: '例: 39'),
      FieldDef('birth_order', '第何子か', type: FieldType.number, required: true),
      FieldDef('birth_height', '出生時身長(cm)', type: FieldType.number, required: true),
      FieldDef('birth_weight', '出生時体重(g)', type: FieldType.number, required: true),
      FieldDef('newborn_notes', '出生時・新生児期の特記事項', type: FieldType.multiline, required: true, hint: '無い場合は「なし」'),
      FieldDef('feeding_method', '授乳方法', type: FieldType.select, required: true, options: ['母乳', '混合', '人工']),
      FieldDef('weaning_age', '断乳・離乳時期', required: true, hint: '例: 1歳2か月(まだの場合は「未」)'),
      FieldDef('baby_food_start', '離乳食開始時期', required: true, hint: '例: 6か月(まだの場合は「未」)'),
      FieldDef('milestones', '首すわり・おすわり・はいはい・初歯・初語等の時期', type: FieldType.multiline, required: true),
      FieldDef('care_history', 'これまでの養育者・生育環境', type: FieldType.multiline, required: true),
    ],
  ),
  StepDef(
    title: '健康・医療・アレルギー',
    sectionKey: 'health',
    fields: [
      FieldDef('doctor_name', 'かかりつけ医(医療機関名)', required: true),
      FieldDef('doctor_phone', 'かかりつけ医 電話番号', type: FieldType.phone, required: true),
      FieldDef('doctor_address', 'かかりつけ医 住所', type: FieldType.multiline),
      FieldDef('medical_history', '既往歴・発症時期・現在の状態', type: FieldType.multiline),
      FieldDef('episode_notes', 'けいれん・脱臼・繰り返しやすい疾病等', type: FieldType.multiline),
      FieldDef('has_allergy', 'アレルギーあり', type: FieldType.toggle),
      FieldDef('allergy_foods', '疑われる原因食材または物質', type: FieldType.multiline),
      FieldDef('allergy_diagnosed', '医師の診断あり', type: FieldType.toggle),
      FieldDef('allergy_doc_state', '診断書の提出状況', type: FieldType.select, options: ['未提出', '提出予定', '提出済み']),
      FieldDef('care_notes', '園生活上の注意事項', type: FieldType.multiline),
      FieldDef('normal_temp', '平熱(℃)', type: FieldType.number, required: true, hint: '例: 36.5(小数第1位まで)'),
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
    // 児童票に必要な情報のため必須ベース(俊指示 2026-08-17)
    note: '児童票の作成に必要な情報です。現在のご家庭での様子をお書きください(該当しない項目は「なし」)',
    fields: [
      FieldDef('feeding', '授乳(回数・量・夜間授乳・使用ミルク)', type: FieldType.multiline, required: true, hint: '卒乳済みの場合は「なし」'),
      FieldDef('meal', '離乳食・食事(回数・量・食べ方)', type: FieldType.multiline, required: true),
      FieldDef('self_feeding', '自分で食べる状況・使用器具・食事中の様子', type: FieldType.multiline, required: true),
      FieldDef('likes_dislikes', '好きな食べ物・苦手な食べ物・間食', type: FieldType.multiline, required: true),
      FieldDef('sleep', '起床・就寝・昼寝・寝る姿勢・添い寝等', type: FieldType.multiline, required: true),
      FieldDef('excretion', '排尿・排便・おむつ・排泄の自立状況', type: FieldType.multiline, required: true),
      FieldDef('hygiene', '手洗い・洗顔・うがい・歯磨き等', type: FieldType.multiline, required: true),
      FieldDef('clothing', '着脱できる衣類・援助が必要な衣類', type: FieldType.multiline, required: true),
      FieldDef('language', '言葉の発達や伝わり方', type: FieldType.multiline, required: true),
      FieldDef('social', '人見知り・他児との遊び・大人との関わり', type: FieldType.multiline, required: true),
      FieldDef('play', '好きな遊び・玩具・興味', type: FieldType.multiline, required: true),
    ],
  ),
  StepDef(
    title: '性格・遊び・家庭の希望',
    sectionKey: 'thoughts',
    // 児童票に必要な情報のため必須ベース(俊指示 2026-08-17)
    note: '児童票の作成に必要な情報です(特に無い項目は「なし」「特になし」)',
    fields: [
      FieldDef('good_points', '保護者から見た園児の良いところ', type: FieldType.multiline, required: true),
      FieldDef('worries', '心配していること・気になる癖', type: FieldType.multiline, required: true),
      FieldDef('hopes', 'どのように育ってほしいか', type: FieldType.multiline, required: true),
      FieldDef('values', '子育てで大切にしていること', type: FieldType.multiline, required: true),
      FieldDef('requests', '園への希望', type: FieldType.multiline, required: true, hint: '特に無い場合は「なし」'),
      FieldDef('health_notes', '健康・身体上の特記事項', type: FieldType.multiline, required: true, hint: '無い場合は「なし」'),
      FieldDef('other', 'その他伝えておきたいこと', type: FieldType.multiline, required: true, hint: '無い場合は「なし」'),
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
