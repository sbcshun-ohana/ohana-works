import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';

/// 厨房ボード(閲覧用・iPad一画面)。厨房は朝おやつ/昼食/午後おやつを別々に管理するため、
/// 選んだ1区分について「全施設 × 全クラス」の食数を一画面で一覧できる。アレルギー対応食も同画面に含める。
/// できる限り操作せずに読めるよう、区分は上部の大きなタブで1タップ切替、その他はスクロール最小の固定レイアウト。
/// 各園で承認・確定された数を読み取るだけ(承認・変更は食数ボードで)。データは 344/352 の横断RPCを再利用。
class MealKitchenBoardScreen extends StatefulWidget {
  const MealKitchenBoardScreen({super.key, required this.service, required this.offices});
  final ChildcareService service;
  final List<Map<String, dynamic>> offices;

  @override
  State<MealKitchenBoardScreen> createState() => _MealKitchenBoardScreenState();
}

const _slots = [
  (key: 'am_snack', label: '午前おやつ'),
  (key: 'lunch', label: '昼食'),
  (key: 'pm_snack', label: '午後おやつ'),
];

class _MealKitchenBoardScreenState extends State<MealKitchenBoardScreen> {
  DateTime _date = DateTime.now();
  String _slot = 'lunch'; // 既定=昼食
  List<Map<String, dynamic>> _rows = const [];
  List<Map<String, dynamic>> _allergy = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ids = widget.offices.map((o) => o['office_id'] as String).toList();
      final rows = await widget.service.fetchMealBoardCrossoffice(ids, _date);
      List<Map<String, dynamic>> allergy = const [];
      try {
        allergy = await widget.service.fetchMealAllergyCrossoffice(ids, _date);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _allergy = allergy;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _n(Map<String, dynamic> r, String k) => (r[k] as num?)?.toInt() ?? 0;

  // 選択区分の当該行のみ(施設順=RPCの並びを保持)。
  Iterable<Map<String, dynamic>> get _slotRows => _rows.where((r) => r['meal_slot'] == _slot);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('厨房ボード'),
        actions: [BusinessDateAction(date: _date, onChanged: (d) { setState(() => _date = d); _load(); })],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _slotTabs(),
                  const SizedBox(height: 10),
                  _totalBanner(),
                  const SizedBox(height: 10),
                  Expanded(child: _facilityColumns()),
                  const SizedBox(height: 10),
                  _allergyStrip(),
                ],
              ),
            ),
    );
  }

  // 上部: 区分タブ(大きく・1タップ切替)。
  Widget _slotTabs() {
    return Row(
      children: [
        for (final s in _slots) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _slot = s.key),
              child: Container(
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _slot == s.key ? AppColors.warmOrange : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _slot == s.key ? AppColors.warmOrange : Colors.grey.shade300, width: 1.5),
                ),
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _slot == s.key ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          if (s.key != _slots.last.key) const SizedBox(width: 10),
        ],
      ],
    );
  }

  // 選択区分の合計(児/職/アレルギー)を大きく。
  Widget _totalBanner() {
    final child = _slotRows.fold(0, (a, r) => a + _n(r, 'child_count'));
    final staff = _slotRows.fold(0, (a, r) => a + _n(r, 'staff_count'));
    final allergy = _slotRows.fold(0, (a, r) => a + _n(r, 'allergy_count'));
    Widget stat(String label, String value, Color color) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color, height: 1.0)),
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          stat('合計(食)', '${child + staff}', AppColors.textPrimary),
          _divider(),
          stat('児', '$child', AppColors.textPrimary),
          _divider(),
          stat('職', '$staff', AppColors.textSecondary),
          _divider(),
          stat('アレルギー対応食', '$allergy', allergy > 0 ? AppColors.punchClockOut : AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 40, color: Colors.grey.shade200);

  // 施設を横に並べた列。各列=施設のクラス別食数(内アレを赤字)+施設小計。
  Widget _facilityColumns() {
    // 施設順(RPCの並び=大和→ベイビーマハロ→…)を保持。
    final officeIds = <String>[];
    final officeNames = <String, String>{};
    for (final r in _slotRows) {
      final oid = r['office_id'] as String? ?? '';
      if (oid.isNotEmpty && !officeIds.contains(oid)) {
        officeIds.add(oid);
        officeNames[oid] = r['office_name'] as String? ?? '';
      }
    }
    if (officeIds.isEmpty) {
      return const Center(child: Text('この日の食数データはありません(各園の食数ボードで承認してください)', style: TextStyle(color: AppColors.textSecondary)));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < officeIds.length; i++) ...[
          Expanded(child: _facilityCard(officeIds[i], officeNames[officeIds[i]] ?? '')),
          if (i != officeIds.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _facilityCard(String oid, String name) {
    // 当該施設・当該区分の行(sort_order順)。
    final rows = _slotRows.where((r) => r['office_id'] == oid).toList()
      ..sort((a, b) => _n(a, 'sort_order').compareTo(_n(b, 'sort_order')));
    final child = rows.fold(0, (a, r) => a + _n(r, 'child_count'));
    final staff = rows.fold(0, (a, r) => a + _n(r, 'staff_count'));
    final allergy = rows.fold(0, (a, r) => a + _n(r, 'allergy_count'));
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 施設見出し
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(color: AppColors.skyBlue.withValues(alpha: 0.14), borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
            child: Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          // クラス別(列の高さで行を均等配分=スクロールなしで全行表示。施設ごとに行高さが変わってOK)。
          Expanded(
            child: Column(
              children: [
                for (final r in rows)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r['row_label'] as String? ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (_n(r, 'allergy_count') > 0)
                                  Text('内アレ ${_n(r, 'allergy_count')}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.punchClockOut)),
                              ],
                            ),
                          ),
                          // 食数(職員行は職、児行は児を大きく)。狭くても収まるようスケールダウン。
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${(r['row_type'] as String?) == 'staff' ? _n(r, 'staff_count') : _n(r, 'child_count')}',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: (r['row_type'] as String?) == 'staff' ? AppColors.textSecondary : AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 施設小計
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(color: AppColors.leafGreen.withValues(alpha: 0.12), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('小計', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${child + staff}食', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    Text('(児$child/職$staff)', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    if (allergy > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('内アレ$allergy', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.punchClockOut)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 下部: アレルギー対応食(作る)。除去食対象児を横並びカードで(名前・施設クラス・アレルゲン・代替)。
  Widget _allergyStrip() {
    final elim = _allergy.where((a) => a['handling'] == 'elimination').toList();
    final bento = _allergy.where((a) => a['handling'] == 'bento').toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.punchClockOut.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.punchClockOut.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('アレルギー対応食(作る)${elim.isEmpty ? '' : '・${elim.length}名'}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.punchClockOut)),
              if (bento.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text('弁当持参(作らない): ${bento.map((b) => '${b['child_name']}(${b['office_name']})').join('・')}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (elim.isEmpty)
            const Text('本日のアレルギー対応食はありません', style: TextStyle(color: AppColors.textSecondary))
          else
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final a in elim)
                    Container(
                      width: 260,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.punchClockOut.withValues(alpha: 0.25))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(a['child_name'] as String? ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (a['consent_status'] == 'pending')
                                Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppColors.warmOrange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)), child: const Text('同意待ち', style: TextStyle(fontSize: 10))),
                            ],
                          ),
                          Text('${a['office_name'] ?? ''}・${a['class_name'] ?? '—'}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          const SizedBox(height: 2),
                          Text('アレルゲン: ${((a['allergens'] as List?)?.cast<String>() ?? const []).join('・')}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.punchClockOut), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Expanded(
                            child: Text('代替: ${(a['substitute'] as String?) ?? '（除去食献立が未登録）'}',
                                style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
