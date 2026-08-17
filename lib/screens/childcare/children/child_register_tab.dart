import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/childcare_service.dart';

/// 園児台帳タブ(M6 Phase 3a・221)。閲覧専用。
/// children正本+世帯住所+承認済み入園フォームのスナップショット(=正本)を表示する。
/// 電話番号はタップで発信、住所はタップで地図を開く(草案§9.3)。
class ChildRegisterTab extends StatefulWidget {
  const ChildRegisterTab({super.key, required this.service, required this.childId});

  final ChildcareService service;
  final String childId;

  @override
  State<ChildRegisterTab> createState() => _ChildRegisterTabState();
}

// セクション・項目ラベル(parent_app enrollment_form_definition.dart / admin enrollmentFormLabels.ts と同じキー契約)
const _sectionLabels = <String, String>{
  'basic': '園児基本情報',
  'address': '住所・世帯情報',
  'guardians': '保護者・勤務先・連絡先',
  'pickup': '緊急連絡先・送迎・引き渡し',
  'family': '家族・兄弟姉妹',
  'birth_growth': '出生・生育歴',
  'health': '健康・医療・アレルギー',
  'lifestyle': '食事・睡眠・排泄・生活習慣',
  'thoughts': '性格・遊び・家庭の希望',
  'checkups': '健診・予防接種',
};

const _sectionOrder = [
  'basic', 'address', 'guardians', 'pickup', 'family',
  'birth_growth', 'health', 'lifestyle', 'thoughts', 'checkups',
];

const _fieldLabels = <String, String>{
  'full_name': '園児氏名', 'name_kana': 'ふりがな', 'nickname': '愛称', 'gender': '性別', 'birth_date': '生年月日',
  'postal_code': '郵便番号', 'prefecture': '都道府県', 'city': '市区町村', 'town': '町域',
  'address_line': '番地', 'building': '建物名', 'child_same': '園児住所は世帯と同じ', 'child_address': '園児住所',
  'name': '氏名', 'relationship': '続柄・関係', 'living': '同居・別居', 'is_representative': '代表保護者',
  'priority': '連絡優先順位', 'phone_mobile': '携帯電話', 'phone_home': '自宅電話', 'email': 'メール',
  'work_name': '勤務先名', 'work_phone': '勤務先電話', 'work_mobile': '勤務先直通携帯',
  'work_postal': '勤務先郵便番号', 'work_address': '勤務先住所', 'work_note': '勤務先補足',
  'drop_person': '通常の送り担当', 'pickup_person': '通常の迎え担当', 'method': '通園方法', 'duration': '所要時間',
  'car_number': '車両ナンバー', 'car_model': '車種・色', 'car_driver': '主な運転者',
  'car_parking_agreed': '駐車場注意事項に同意', 'bicycle_acknowledged': '自転車注意事項を確認',
  'phone': '電話番号', 'id_note': '本人確認情報',
  'occupation_school': '職業・学校等', 'sibling_facility': '在籍施設',
  'gestational_weeks': '在胎週数', 'birth_order': '第何子', 'birth_height': '出生時身長', 'birth_weight': '出生時体重',
  'newborn_notes': '新生児期の特記', 'feeding_method': '授乳方法', 'weaning_age': '断乳・離乳時期',
  'baby_food_start': '離乳食開始', 'milestones': '発達の時期', 'care_history': '養育者・生育環境',
  'doctor_name': 'かかりつけ医', 'doctor_phone': 'かかりつけ医電話', 'doctor_address': 'かかりつけ医住所',
  'medical_history': '既往歴', 'episode_notes': 'けいれん・脱臼等', 'has_allergy': 'アレルギーあり',
  'allergy_foods': '原因食材・物質', 'allergy_diagnosed': '医師の診断あり', 'allergy_doc_state': '診断書の提出状況',
  'care_notes': '園生活上の注意', 'normal_temp': '平熱(℃)', 'high_temp_acknowledged': '高体温注意の確認',
  'condition': '使用条件・時期', 'note': '配慮・参照情報',
  'feeding': '授乳', 'meal': '食事', 'self_feeding': '自分で食べる状況', 'likes_dislikes': '好き嫌い・間食',
  'sleep': '睡眠', 'excretion': '排泄', 'hygiene': '清潔習慣', 'clothing': '着脱', 'language': '言葉',
  'social': '人との関わり', 'play': '遊び',
  'good_points': '良いところ', 'worries': '心配・気になる癖', 'hopes': '育ってほしい姿',
  'values': '大切にしていること', 'requests': '園への希望', 'health_notes': '健康上の特記', 'other': 'その他',
  'checkup_3_4m': '3〜4か月児健診', 'checkup_6_7m': '6〜7か月児健診', 'checkup_9_10m': '9〜10か月児健診',
  'checkup_18m': '1歳6か月児健診', 'checkup_3y': '3歳児健診',
  'vac_hib': 'ヒブ', 'vac_pneumo': '小児用肺炎球菌', 'vac_hepb': 'B型肝炎', 'vac_rota': 'ロタウイルス',
  'vac_dpt': '四種混合(五種混合)', 'vac_bcg': 'BCG', 'vac_mr': '麻しん風しん(MR)', 'vac_varicella': '水痘',
  'vac_je': '日本脳炎', 'vac_notes': '補足',
  'emergency': '緊急連絡先', 'proxies': '代理送迎者', 'medication': '服薬情報',
};

String _label(String key) => _fieldLabels[key] ?? key;

bool _isPhoneKey(String key) => key.contains('phone') || key == 'work_mobile';

class _ChildRegisterTabState extends State<ChildRegisterTab> {
  Map<String, dynamic>? _register;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final register = await widget.service.fetchChildRegister(widget.childId);
      if (mounted) {
        setState(() {
          _register = register;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '台帳の読み込みに失敗しました: $e';
        });
      }
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
    await launchUrl(uri);
  }

  Future<void> _openMap(String address) async {
    final uri = Uri.parse('https://maps.apple.com/?q=${Uri.encodeComponent(address)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }
    final r = _register;
    if (r == null) return const Center(child: Text('園児が見つかりません'));

    final registerData = r['register_data'] as Map<String, dynamic>?;
    final household = r['household'] as Map<String, dynamic>?;
    final householdAddress = household == null
        ? null
        : ['prefecture', 'city', 'town', 'address_line', 'building']
            .map((k) => (household[k] ?? '') as String)
            .where((s) => s.isNotEmpty)
            .join(' ');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card('基本情報(園児マスタ)', [
            _row('氏名', '${r['full_name'] ?? ''}(${r['name_kana'] ?? '—'})'),
            _row('呼び名', '${r['display_name'] ?? ''}${r['honorific_suffix'] ?? ''}'),
            _row('性別', (r['gender'] as String?) ?? '—'),
            _row('生年月日', (r['birth_date'] as String?) ?? '—'),
            _row('クラス', (r['class_name'] as String?) ?? '—'),
            _row('入園日', (r['enrollment_date'] as String?) ?? '—'),
            _row('在籍状況',
                '${r['enrollment_status'] ?? ''}${r['child_kind'] == 'temporary' ? '(一時預かり)' : ''}'),
          ]),
          if (household != null)
            _card('世帯住所', [
              _row('郵便番号', (household['postal_code'] as String?) ?? '—'),
              if (householdAddress != null && householdAddress.isNotEmpty)
                InkWell(
                  onTap: () => _openMap(householdAddress),
                  child: _row('住所', '$householdAddress 🗺', valueColor: Colors.blue),
                ),
            ]),
          if (registerData == null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('入園時基本情報はまだ提出・承認されていません',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            )
          else ...[
            for (final sectionKey in _sectionOrder)
              if (registerData[sectionKey] != null) _sectionCard(sectionKey, registerData[sectionKey]),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: Text(
                '入園時基本情報 第${r['register_version']}版'
                '(承認: ${r['register_approved_at'] != null ? DateTime.parse(r['register_approved_at'] as String).toLocal().toString().substring(0, 16) : '—'})',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.teal)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(
              child: Text(value,
                  style: TextStyle(fontSize: 14, color: valueColor ?? Colors.black87))),
        ],
      ),
    );
  }

  /// 値の行(電話番号キーはタップで発信)
  Widget _valueRow(String key, dynamic value) {
    final text = value is bool ? (value ? 'はい' : 'いいえ') : value.toString();
    if (_isPhoneKey(key) && text.trim().isNotEmpty) {
      return InkWell(
        onTap: () => _callPhone(text),
        child: _row(_label(key), '$text 📞', valueColor: Colors.blue),
      );
    }
    return _row(_label(key), text);
  }

  Widget _sectionCard(String sectionKey, dynamic section) {
    final children = <Widget>[];
    if (section is Map<String, dynamic>) {
      section.forEach((k, v) {
        if (v == null || v == false || (v is String && v.trim().isEmpty)) return;
        if (v is List) {
          if (v.isEmpty) return;
          children.add(Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(_label(k),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ));
          for (var i = 0; i < v.length; i++) {
            children.add(_listItemCard('${_label(k)} ${i + 1}', v[i]));
          }
        } else {
          children.add(_valueRow(k, v));
        }
      });
    } else if (section is List) {
      for (var i = 0; i < section.length; i++) {
        children.add(_listItemCard('${_sectionLabels[sectionKey]} ${i + 1}', section[i]));
      }
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return _card(_sectionLabels[sectionKey] ?? sectionKey, children);
  }

  Widget _listItemCard(String title, dynamic item) {
    final map = (item as Map).cast<String, dynamic>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          for (final e in map.entries)
            if (e.value != null && e.value != false && !(e.value is String && (e.value as String).trim().isEmpty))
              _valueRow(e.key, e.value),
        ],
      ),
    );
  }
}
