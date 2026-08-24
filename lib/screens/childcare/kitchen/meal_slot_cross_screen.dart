import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';

/// 食事区分ごとの横断集計(304)。指定日について、食事区分(朝おやつ/昼食/午後おやつ)ごとに
/// 各施設の必要数を1画面で一覧。委託(安田物産)が複数園分をまとめて把握する用。
class MealSlotCrossScreen extends StatefulWidget {
  const MealSlotCrossScreen({super.key, required this.service, required this.offices});
  final ChildcareService service;
  final List<Map<String, dynamic>> offices;

  @override
  State<MealSlotCrossScreen> createState() => _MealSlotCrossScreenState();
}

const _slots = [
  (key: 'am_snack', label: '朝おやつ'),
  (key: 'lunch', label: '昼食'),
  (key: 'pm_snack', label: '午後おやつ'),
];

class _MealSlotCrossScreenState extends State<MealSlotCrossScreen> {
  DateTime _date = DateTime.now();
  List<Map<String, dynamic>> _rows = const [];
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
      final rows = await widget.service.fetchMealSlotCrossoffice(ids, _date);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('食事区分ごと(全施設)'),
        actions: [BusinessDateAction(date: _date, onChanged: (d) { setState(() => _date = d); _load(); })],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final slot in _slots) _slotCard(slot.key, slot.label),
              ],
            ),
    );
  }

  Widget _slotCard(String slotKey, String slotLabel) {
    final rows = _rows.where((r) => r['meal_slot'] == slotKey).toList();
    var total = 0;
    for (final r in rows) {
      total += ((r['child_total'] as num?)?.toInt() ?? 0) + ((r['staff_total'] as num?)?.toInt() ?? 0);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(slotLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.warmOrange)),
                const Spacer(),
                Text('計 $total 食', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const Divider(),
            if (rows.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('データなし', style: TextStyle(color: AppColors.textSecondary)))
            else
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(r['office_name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text('児${r['child_total'] ?? 0} / 職${r['staff_total'] ?? 0}',
                          style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                      Text('${((r['child_total'] as num?)?.toInt() ?? 0) + ((r['staff_total'] as num?)?.toInt() ?? 0)} 食',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
