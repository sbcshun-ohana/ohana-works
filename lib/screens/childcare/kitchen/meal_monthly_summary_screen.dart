import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';

/// 月別集計(304)。施設×暦月の日別食数(食事区分すべて分けて園児/職員)+残量(g)。月合計を自動算出。
/// Excel出力は管理者web側(SheetJS)。厨房アプリでは閲覧。
class MealMonthlySummaryScreen extends StatefulWidget {
  const MealMonthlySummaryScreen({
    super.key,
    required this.service,
    required this.offices,
    required this.initialOfficeId,
  });
  final ChildcareService service;
  final List<Map<String, dynamic>> offices;
  final String initialOfficeId;

  @override
  State<MealMonthlySummaryScreen> createState() => _MealMonthlySummaryScreenState();
}

class _MealMonthlySummaryScreenState extends State<MealMonthlySummaryScreen> {
  late String _officeId = widget.initialOfficeId;
  late int _year = DateTime.now().year;
  late int _month = DateTime.now().month;
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
      final rows = await widget.service.fetchMealMonthlySummary(_officeId, _year, _month);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _sum(String key) => _rows.fold(0, (a, r) => a + ((r[key] as num?)?.toInt() ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('月別集計')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.offices.length > 1)
                  DropdownButton<String>(
                    value: _officeId,
                    items: [
                      for (final o in widget.offices)
                        DropdownMenuItem(value: o['office_id'] as String, child: Text(o['office_name'] as String)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _officeId = v);
                      _load();
                    },
                  ),
                DropdownButton<int>(
                  value: _year,
                  items: [for (final y in [_year - 1, _year, _year + 1]) DropdownMenuItem(value: y, child: Text('$y年'))],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _year = v);
                    _load();
                  },
                ),
                DropdownButton<int>(
                  value: _month,
                  items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('$m月'))],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _month = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('各セル「児(園児)/職(職員)」。Excel出力は管理者Webから。', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('この月の食数データはありません', style: TextStyle(color: AppColors.textSecondary)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Table(
                          border: TableBorder(horizontalInside: BorderSide(color: Colors.grey.shade200)),
                          columnWidths: const {
                            0: FlexColumnWidth(0.9),
                            1: FlexColumnWidth(1.4),
                            2: FlexColumnWidth(1.4),
                            3: FlexColumnWidth(1.4),
                            4: FlexColumnWidth(1.0),
                          },
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          children: [
                            _headerRow(),
                            for (final r in _rows) _dataRow(r),
                            _totalRow(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String s, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(s, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w400, color: color)),
      );

  TableRow _headerRow() => TableRow(
        decoration: const BoxDecoration(color: Color(0xFFEEF2F0)),
        children: [
          for (final t in ['日', '午前おやつ(食種別)', '昼食(食種別)', '午後おやつ(食種別)', '残量(g)'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
            ),
        ],
      );

  // 区分セル: 後期食/完了食/幼児食(児童・段階別)+ 職。全区分共通。
  Widget _stageCell(int late, int complete, int toddler, int staff, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('後期$late ・ 完了$complete ・ 幼児$toddler',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            Text('職$staff', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      );

  int _i(Map<String, dynamic> r, String k) => (r[k] as num?)?.toInt() ?? 0;

  TableRow _dataRow(Map<String, dynamic> r) {
    final d = DateTime.parse(r['business_date'] as String);
    return TableRow(children: [
      _cell('${d.month}/${d.day}'),
      _stageCell(_i(r, 'am_late'), _i(r, 'am_complete'), _i(r, 'am_toddler'), _i(r, 'am_staff')),
      _stageCell(_i(r, 'lunch_late'), _i(r, 'lunch_complete'), _i(r, 'lunch_toddler'), _i(r, 'lunch_staff')),
      _stageCell(_i(r, 'pm_late'), _i(r, 'pm_complete'), _i(r, 'pm_toddler'), _i(r, 'pm_staff')),
      _cell(r['leftover_grams'] == null ? '—' : '${r['leftover_grams']}'),
    ]);
  }

  TableRow _totalRow() {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFF6F8F7)),
      children: [
        _cell('月合計', bold: true),
        _stageCell(_sum('am_late'), _sum('am_complete'), _sum('am_toddler'), _sum('am_staff'), bold: true),
        _stageCell(_sum('lunch_late'), _sum('lunch_complete'), _sum('lunch_toddler'), _sum('lunch_staff'), bold: true),
        _stageCell(_sum('pm_late'), _sum('pm_complete'), _sum('pm_toddler'), _sum('pm_staff'), bold: true),
        _cell('${_sum('leftover_grams')}', bold: true),
      ],
    );
  }
}
