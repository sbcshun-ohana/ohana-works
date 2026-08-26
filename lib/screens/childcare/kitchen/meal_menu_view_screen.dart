import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';

/// 献立閲覧(一般職員/担任・厨房共通・読み取り専用)。今日の献立と、その月に読み込まれた献立の月間一覧。
/// admin の日別ビュー/月間一覧と同じ内容を Kids でも見られるようにする(表記も統一)。
class MealMenuViewScreen extends StatefulWidget {
  const MealMenuViewScreen({super.key, required this.service, required this.officeId, required this.businessDate});
  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<MealMenuViewScreen> createState() => _MealMenuViewScreenState();
}

// 食数ボードの給食段階と統一: 上から 後期 / 完了期 / 幼児食。幼児食は1種類(over3/under3統合)。
const _foodTypes = [
  (label: '後期', srcs: ['weaning_late'], color: Color(0xFF6D28D9)),
  (label: '完了期', srcs: ['weaning_final'], color: Color(0xFF4338CA)),
  (label: '幼児食', srcs: ['regular_over3', 'regular_under3'], color: Color(0xFF0369A1)),
];
const _slots = [
  (key: 'am_snack', label: '午前おやつ'),
  (key: 'lunch', label: '昼食'),
  (key: 'pm_snack', label: '午後おやつ'),
];

class _MealMenuViewScreenState extends State<MealMenuViewScreen> {
  int _tab = 0; // 0=今日 / 1=月間一覧
  DateTime _date = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<Map<String, dynamic>> _today = const [];
  List<Map<String, dynamic>> _days = const []; // 月間
  String? _usedLabel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _date = widget.businessDate;
    _month = DateTime(widget.businessDate.year, widget.businessDate.month, 1);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_tab == 0) {
        final rows = await widget.service.fetchPublishedMenuDay(widget.officeId, _date);
        if (!mounted) return;
        setState(() { _today = rows; _loading = false; });
      } else {
        final imports = await widget.service.fetchMenuImports(widget.officeId, _month);
        Map<String, dynamic>? chosen;
        for (final i in imports) {
          if (i['status'] == 'published') { chosen = i; break; }
        }
        chosen ??= imports.isNotEmpty ? imports.first : null;
        List<Map<String, dynamic>> days = const [];
        if (chosen != null) days = await widget.service.fetchMenuDaysForImport(chosen['id'] as String);
        if (!mounted) return;
        setState(() {
          _days = days;
          _usedLabel = chosen == null ? null : 'v${chosen['version']}・${chosen['source_filename'] ?? ''}${chosen['status'] == 'published' ? '(公開中)' : '(未公開)'}';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('献立'),
        actions: [
          if (_tab == 0) BusinessDateAction(date: _date, onChanged: (d) { setState(() => _date = d); _load(); }),
        ],
      ),
      body: Column(
        children: [
          _tabs(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tab == 0
                    ? _todayView()
                    : _monthView(),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget btn(int i, String label) => Expanded(
          child: GestureDetector(
            onTap: () { if (_tab != i) { setState(() => _tab = i); _load(); } },
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _tab == i ? AppColors.warmOrange : Colors.transparent, width: 3)),
              ),
              child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _tab == i ? AppColors.warmOrange : AppColors.textSecondary)),
            ),
          ),
        );
    return Container(
      color: Colors.white,
      child: Row(children: [btn(0, '今日の献立'), btn(1, '月間一覧')]),
    );
  }

  // 今日の献立: 食種×区分。
  Widget _todayView() {
    String cell(List<String> srcs, String slot) {
      for (final ft in srcs) {
        final m = _today.where((x) => x['food_type'] == ft && x['meal_slot'] == slot && x['removal_kind'] == null).firstOrNull;
        final t = (m?['menu_text'] as String?)?.trim();
        if (t != null && t.isNotEmpty) return t;
      }
      return '';
    }
    final removals = _today.where((x) => x['food_type'] == 'allergy_removed' && x['removal_kind'] != null).toList();
    final hasAny = _today.any((x) => (x['menu_text'] as String?)?.trim().isNotEmpty == true);
    if (!hasAny) {
      return const Center(child: Text('この日の公開済み献立はありません', style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final ft in _foodTypes)
          if (_slots.any((s) => cell(ft.srcs, s.key).isNotEmpty))
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ftChip(ft.label, ft.color),
                    const SizedBox(height: 8),
                    for (final s in _slots)
                      if (cell(ft.srcs, s.key).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 90, child: Text(s.label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                              Expanded(child: Text(cell(ft.srcs, s.key), style: const TextStyle(fontSize: 14))),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
        if (removals.isNotEmpty)
          Card(
            color: const Color(0xFFFFFBEB),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('除去食(アレルゲン別)', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF92400E))),
                  const SizedBox(height: 6),
                  for (final r in removals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${r['removal_kind']} 除去 / ${_slots.firstWhere((s) => s.key == r['meal_slot'], orElse: () => _slots[1]).label}: ${r['menu_text'] ?? ''}${(r['removal_note'] as String?)?.isNotEmpty == true ? '(${r['removal_note']})' : ''}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // 月間一覧: 日付ごとに食種×区分をカード表示(1日おき縞々)。
  Widget _monthView() {
    final dates = (_days.map((d) => d['menu_date'] as String).toSet().toList())..sort();
    if (dates.isEmpty) {
      return const Center(child: Text('この月に読み込まれた献立はありません', style: TextStyle(color: AppColors.textSecondary)));
    }
    String cell(String date, List<String> srcs, String slot) {
      for (final ft in srcs) {
        final m = _days.where((x) => x['menu_date'] == date && x['food_type'] == ft && x['meal_slot'] == slot && x['removal_kind'] == null).firstOrNull;
        final t = (m?['menu_text'] as String?)?.trim();
        if (t != null && t.isNotEmpty) return t;
      }
      return '';
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Text('${_month.year}年${_month.month}月', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              if (_usedLabel != null) Expanded(child: Text('使用中: $_usedLabel', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () { setState(() => _month = DateTime(_month.year, _month.month - 1, 1)); _load(); }),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () { setState(() => _month = DateTime(_month.year, _month.month + 1, 1)); _load(); }),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: dates.length,
            itemBuilder: (_, di) {
              final date = dates[di];
              final d = DateTime.parse(date);
              final wd = '日月火水木金土'[d.weekday % 7];
              final removals = _days.where((x) => x['menu_date'] == date && x['food_type'] == 'allergy_removed' && x['removal_kind'] != null).toList();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: di.isOdd ? const Color(0xFFF1F5F9) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${d.month}/${d.day}（$wd）', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 6),
                    for (final ft in _foodTypes)
                      if (_slots.any((s) => cell(date, ft.srcs, s.key).isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ftChip(ft.label, ft.color),
                              const SizedBox(height: 2),
                              for (final s in _slots)
                                if (cell(date, ft.srcs, s.key).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4, top: 2),
                                    child: Text('${s.label}: ${cell(date, ft.srcs, s.key)}', style: const TextStyle(fontSize: 13)),
                                  ),
                            ],
                          ),
                        ),
                    for (final r in removals)
                      Text('${r['removal_kind']} 除去 / ${_slots.firstWhere((s) => s.key == r['meal_slot'], orElse: () => _slots[1]).label}: ${r['menu_text'] ?? ''}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF92400E))),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _ftChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      );
}
