import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import 'kitchen_screen.dart';

/// 食数ボード(担任用・給食管理 Phase 2)。行区分×食事区分の食数を表示し、自クラスの承認・期限内変更を行う。
/// 厨房向けの表示(大型アラート等)は「厨房表示」から KitchenScreen へ。
class MealBoardScreen extends StatefulWidget {
  const MealBoardScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
    required this.isManager,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;
  final bool isManager;

  @override
  State<MealBoardScreen> createState() => _MealBoardScreenState();
}

const _slots = [
  (key: 'am_snack', label: '朝おやつ'),
  (key: 'lunch', label: '昼食'),
  (key: 'pm_snack', label: '午後おやつ'),
];

class _MealBoardScreenState extends State<MealBoardScreen> {
  late DateTime _date = widget.businessDate;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _board = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await widget.service.fetchMealBoard(widget.officeId, _date);
      if (!mounted) return;
      setState(() {
        _board = board;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _error = '食数の取得に失敗しました'; _loading = false; });
    }
  }

  void _onDateChanged(DateTime d) {
    setState(() => _date = d);
    _load();
  }

  Future<void> _run(Future<void> Function() action, String ok) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && ok.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作できません: ${_clean(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clean(Object e) {
    final s = e.toString();
    if (s.contains('not authorized')) return '権限がありません';
    final i = s.indexOf('変更期限');
    if (i >= 0) return s.substring(i);
    if (s.contains('当日のみ')) return '変更は当日のみ可能です';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        title: const Text('食数ボード'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : () => _run(() => widget.service.computeMealCounts(widget.officeId, _date), '再算出しました'),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('再算出'),
          ),
          IconButton(
            tooltip: '厨房表示',
            icon: const Icon(Icons.restaurant_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => KitchenScreen(service: widget.service, officeId: widget.officeId, businessDate: _date),
            )),
          ),
          BusinessDateAction(date: _date, onChanged: _onDateChanged),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    // ピボット
    final map = <String, Map<String, dynamic>>{};
    for (final b in _board) {
      final key = b['row_key'] as String;
      final row = map.putIfAbsent(key, () => {
            'label': b['row_label'],
            'type': b['row_type'],
            'sort': (b['sort_order'] as num?)?.toInt() ?? 0,
            'confirmed': false,
            'cells': <String, ({int child, int staff})>{},
          });
      (row['cells'] as Map<String, ({int child, int staff})>)[b['meal_slot'] as String] =
          (child: (b['child_count'] as num?)?.toInt() ?? 0, staff: (b['staff_count'] as num?)?.toInt() ?? 0);
      if (b['is_confirmed'] == true) row['confirmed'] = true;
    }
    final rows = map.values.toList()..sort((a, b) => (a['sort'] as int).compareTo(b['sort'] as int));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8, left: 4),
          child: Text('9:31に自動算出された暫定値です。数字をタップで期限内変更(昼食10:00/午後14:00/朝9:30)、「承認」で確定。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _header(),
                const Divider(height: 8),
                for (var i = 0; i < rows.length; i++) _row(rows[i], i),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() => Row(
        children: [
          const SizedBox(width: 132, child: Text('区分', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final s in _slots)
            Expanded(child: Center(child: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w800)))),
          const SizedBox(width: 96, child: Center(child: Text('確定', style: TextStyle(fontWeight: FontWeight.w800)))),
        ],
      );

  Widget _row(Map<String, dynamic> r, int index) {
    final cells = r['cells'] as Map<String, ({int child, int staff})>;
    final isStaff = r['type'] == 'staff';
    final confirmed = r['confirmed'] == true;
    return Container(
      color: index.isOdd ? const Color(0xFFF3F6FA) : null,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          SizedBox(width: 132, child: Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w600))),
          for (final s in _slots)
            Expanded(
              child: Center(
                child: cells[s.key] == null
                    ? const Text('—', style: TextStyle(color: AppColors.textSecondary))
                    : InkWell(
                        onTap: _busy ? null : () => _changeCell(r, s.key),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Text('${isStaff ? cells[s.key]!.staff : cells[s.key]!.child}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                      ),
              ),
            ),
          SizedBox(
            width: 96,
            child: Center(
              child: confirmed
                  ? const Icon(Icons.check_circle, color: AppColors.leafGreen, size: 22)
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.leafGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _busy ? null : () => _confirm(r['label'] as String, _rowKeyOf(r)),
                      child: const Text('承認'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _rowKeyOf(Map<String, dynamic> r) {
    // ピボットでは row_key を保持していないため _board から逆引き。
    return _board.firstWhere((b) => b['row_label'] == r['label'])['row_key'] as String;
  }

  Future<void> _confirm(String label, String rowKey) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label を承認'),
        content: const Text('この区分の食数を確定します。よろしいですか?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('承認')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => widget.service.confirmMealRow(widget.officeId, _date, rowKey), '承認しました');
  }

  Future<void> _changeCell(Map<String, dynamic> r, String slot) async {
    final cells = r['cells'] as Map<String, ({int child, int staff})>;
    final isStaff = r['type'] == 'staff';
    final field = isStaff ? 'staff' : 'child';
    final cur = isStaff ? cells[slot]!.staff : cells[slot]!.child;
    final controller = TextEditingController(text: '$cur');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r['label']} / ${_slots.firstWhere((s) => s.key == slot).label} の人数を変更'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: '人数'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              if (n == null || n < 0) return;
              Navigator.pop(ctx, n);
            },
            child: const Text('変更'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _run(
      () => widget.service.changeMealRow(widget.officeId, _date, _rowKeyOf(r), slot, field, result),
      '変更しました',
    );
  }
}
