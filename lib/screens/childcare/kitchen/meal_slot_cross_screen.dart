import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';

/// 厨房ビュー(304/344)。担当施設(委託=大和/ベイビーマハロ/マハロステーション、ハレレア=単独)の
/// 当日の食数を施設別に一覧(児/職を列で分割・施設ごとの縞模様)+アレルギー対応者リスト(作る/弁当持参)。
/// 各園で承認・確定された数を読み取るだけ(承認・変更は食数ボードで)。
class MealSlotCrossScreen extends StatefulWidget {
  const MealSlotCrossScreen({super.key, required this.service, required this.offices});
  final ChildcareService service;
  final List<Map<String, dynamic>> offices;

  @override
  State<MealSlotCrossScreen> createState() => _MealSlotCrossScreenState();
}

const _slots = [
  (key: 'am_snack', label: '午前おやつ'),
  (key: 'lunch', label: '昼食'),
  (key: 'pm_snack', label: '午後おやつ'),
];

class _MealSlotCrossScreenState extends State<MealSlotCrossScreen> {
  DateTime _date = DateTime.now();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('厨房ビュー'),
        actions: [BusinessDateAction(date: _date, onChanged: (d) { setState(() => _date = d); _load(); })],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _countsCard(),
                const SizedBox(height: 16),
                _allergyCard(),
              ],
            ),
    );
  }

  // 食数(施設 → クラス/給食段階の行 × 食事区分・児/職を列分割)。
  Widget _countsCard() {
    // 施設の順序
    final officeIds = <String>[];
    final officeNames = <String, String>{};
    for (final r in _rows) {
      final oid = r['office_id'] as String? ?? '';
      if (oid.isNotEmpty && !officeIds.contains(oid)) {
        officeIds.add(oid);
        officeNames[oid] = r['office_name'] as String? ?? '';
      }
    }
    // 施設内の行(row_key)をsort_order順に、各slotの[児,職]+アレルギー人数
    List<({String label, int allergy, Map<String, List<int>> slots})> rowsOf(String oid) {
      final m = <String, ({String label, int sort, int allergy, Map<String, List<int>> slots})>{};
      for (final r in _rows.where((x) => x['office_id'] == oid)) {
        final key = r['row_key'] as String? ?? '';
        m.putIfAbsent(key, () => (label: r['row_label'] as String? ?? '', sort: (r['sort_order'] as num?)?.toInt() ?? 0, allergy: _n(r, 'allergy_count'), slots: {}));
        m[key]!.slots[r['meal_slot'] as String? ?? ''] = [_n(r, 'child_count'), _n(r, 'staff_count')];
      }
      final list = m.values.toList()..sort((a, b) => a.sort.compareTo(b.sort));
      return [for (final e in list) (label: e.label, allergy: e.allergy, slots: e.slots)];
    }
    int grand(String slot, String key) => _rows.where((r) => r['meal_slot'] == slot).fold(0, (a, r) => a + _n(r, key));
    // 施設小計(その施設の全行合計)。idx: 0=児 1=職 2=内アレ。
    int offTot(String oid, String slot, int idx) => _rows
        .where((r) => r['office_id'] == oid && r['meal_slot'] == slot)
        .fold(0, (a, r) => a + _n(r, idx == 0 ? 'child_count' : idx == 1 ? 'staff_count' : 'allergy_count'));

    final tableRows = <TableRow>[
      // 見出し1段目
      TableRow(children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Text('クラス / 区分', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
        for (final s in _slots)
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(s.label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.warmOrange))),
      ]),
      // 見出し2段目(児/職)
      TableRow(children: [
        const SizedBox.shrink(),
        for (final _ in _slots)
          const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('児 / 職', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textSecondary))),
      ]),
    ];
    for (final oid in officeIds) {
      // 施設見出し行
      tableRows.add(TableRow(
        decoration: BoxDecoration(color: AppColors.skyBlue.withValues(alpha: 0.12)),
        children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Text(officeNames[oid] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          for (final _ in _slots) const SizedBox.shrink(),
        ],
      ));
      var i = 0;
      for (final row in rowsOf(oid)) {
        tableRows.add(TableRow(
          decoration: BoxDecoration(color: row.allergy > 0 ? AppColors.punchClockOut.withValues(alpha: 0.08) : (i.isOdd ? Colors.grey.shade50 : null)),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8, right: 4),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                Text(row.label, style: const TextStyle(fontSize: 13)),
                if (row.allergy > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.punchClockOut, borderRadius: BorderRadius.circular(4)),
                    child: const Text('アレルギー食', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
              ]),
            ),
            for (final s in _slots)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${row.slots[s.key]?[0] ?? 0} / ${row.slots[s.key]?[1] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                    // その食事のうち何食がアレルギー対応食か(赤字で明示)。提供区分のみ。
                    if (row.allergy > 0 && row.slots[s.key] != null)
                      Text('内アレ ${row.allergy}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.punchClockOut)),
                  ],
                ),
              ),
          ],
        ));
        i++;
      }
      // 施設ごとの小計
      tableRows.add(TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade100),
        children: [
          const Padding(padding: EdgeInsets.only(left: 16, top: 8, bottom: 8, right: 4), child: Text('小計', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          for (final s in _slots)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${offTot(oid, s.key, 0)} / ${offTot(oid, s.key, 1)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                if (offTot(oid, s.key, 2) > 0)
                  Text('内アレ ${offTot(oid, s.key, 2)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.punchClockOut)),
              ]),
            ),
        ],
      ));
    }
    if (officeIds.isNotEmpty) {
      tableRows.add(TableRow(
        decoration: BoxDecoration(color: AppColors.leafGreen.withValues(alpha: 0.12)),
        children: [
          const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4), child: Text('合計(参考)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          for (final s in _slots)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${grand(s.key, 'child_count')} / ${grand(s.key, 'staff_count')}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  if (grand(s.key, 'allergy_count') > 0)
                    Text('内アレ ${grand(s.key, 'allergy_count')}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.punchClockOut)),
                ],
              ),
            ),
        ],
      ));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本日の食数(施設・クラス別)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (officeIds.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('この日の食数データはありません(各園の食数ボードで承認してください)', style: TextStyle(color: AppColors.textSecondary)))
            else
              Table(
                border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade200)),
                columnWidths: const {0: FlexColumnWidth(2.6)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: tableRows,
              ),
          ],
        ),
      ),
    );
  }

  // アレルギー対応者リスト(除去食=作る / 弁当持参=作らない)。
  Widget _allergyCard() {
    final elim = _allergy.where((a) => a['handling'] == 'elimination').toList();
    final bento = _allergy.where((a) => a['handling'] == 'bento').toList();
    return Card(
      color: AppColors.punchClockOut.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('アレルギー対応食(作る)${elim.isEmpty ? '' : '・${elim.length}名'}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.punchClockOut)),
            const SizedBox(height: 8),
            if (elim.isEmpty)
              const Text('本日のアレルギー対応食はありません', style: TextStyle(color: AppColors.textSecondary))
            else
              for (final a in elim)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.punchClockOut.withValues(alpha: 0.25))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(a['child_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          const SizedBox(width: 8),
                          Text('${a['office_name'] ?? ''}・${a['class_name'] ?? '—'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          const Spacer(),
                          if (a['consent_status'] == 'pending')
                            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: AppColors.warmOrange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)), child: const Text('同意待ち', style: TextStyle(fontSize: 10))),
                          const SizedBox(width: 6),
                          const Text('1食', style: TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('アレルゲン: ${((a['allergens'] as List?)?.cast<String>() ?? const []).join('・')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.punchClockOut)),
                      Text('代替: ${(a['substitute'] as String?) ?? '（当日の除去食献立が未登録）'}', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
            if (bento.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('弁当持参(提供なし・作らない): ${bento.map((b) => '${b['child_name']}(${b['office_name']})').join('・')}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
