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
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFEEF2F0)),
                            columns: const [
                              DataColumn(label: Text('日')),
                              DataColumn(label: Text('朝おやつ')),
                              DataColumn(label: Text('昼食')),
                              DataColumn(label: Text('午後おやつ')),
                              DataColumn(label: Text('残量(g)')),
                            ],
                            rows: [
                              for (final r in _rows) _dataRow(r),
                              _totalRow(),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  DataRow _dataRow(Map<String, dynamic> r) {
    final d = DateTime.parse(r['business_date'] as String);
    String cell(String c, String s) => '児${r[c] ?? 0} / 職${r[s] ?? 0}';
    return DataRow(cells: [
      DataCell(Text('${d.month}/${d.day}')),
      DataCell(Text(cell('am_child', 'am_staff'))),
      DataCell(Text(cell('lunch_child', 'lunch_staff'))),
      DataCell(Text(cell('pm_child', 'pm_staff'))),
      DataCell(Text(r['leftover_grams'] == null ? '—' : '${r['leftover_grams']}')),
    ]);
  }

  DataRow _totalRow() {
    String tot(String c, String s) => '児${_sum(c)} / 職${_sum(s)}';
    const b = TextStyle(fontWeight: FontWeight.w800);
    return DataRow(
      color: WidgetStateProperty.all(const Color(0xFFF6F8F7)),
      cells: [
        const DataCell(Text('月合計', style: b)),
        DataCell(Text(tot('am_child', 'am_staff'), style: b)),
        DataCell(Text(tot('lunch_child', 'lunch_staff'), style: b)),
        DataCell(Text(tot('pm_child', 'pm_staff'), style: b)),
        DataCell(Text('${_sum('leftover_grams')}', style: b)),
      ],
    );
  }
}
