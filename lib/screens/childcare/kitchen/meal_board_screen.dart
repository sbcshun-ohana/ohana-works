import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';

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
  (key: 'am_snack', label: '午前おやつ'),
  (key: 'lunch', label: '昼食'),
  (key: 'pm_snack', label: '午後おやつ'),
];

class _MealBoardScreenState extends State<MealBoardScreen> {
  late DateTime _date = widget.businessDate;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _board = const [];
  List<Map<String, dynamic>> _suspended = const [];
  ({bool isStation, int? milkBottles, int nextDaySnack})? _station; // Mahalo Station固有(340)

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
      List<Map<String, dynamic>> suspended = const [];
      try {
        suspended = await widget.service.fetchMealSuspendedChildren(widget.officeId);
      } catch (_) {}
      ({bool isStation, int? milkBottles, int nextDaySnack})? station;
      try {
        station = await widget.service.fetchMealStationExtras(widget.officeId, _date);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _board = board;
        _suspended = suspended;
        _station = station;
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
        title: const Text('給食発注数'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : () => _run(() => widget.service.computeMealCounts(widget.officeId, _date), '再算出しました'),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('再算出'),
          ),
          // 一般職員/担任は給食写真・厨房ビューなし(俊指示 2026-08-26)。給食発注数(食数確定)+ Station牛乳のみ。
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
            'key': b['row_key'],
            'label': b['row_label'],
            'type': b['row_type'],
            'sort': (b['sort_order'] as num?)?.toInt() ?? 0,
            'plating': b['requires_plating'] == true, // 盛り付け配膳クラス(大和はな/そら/かぜ)
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
        if (_suspended.isNotEmpty) _suspendedBanner(),
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
        // Mahalo Station固有(340): 食数確認の流れの中で「明日のおやつ+今日の牛乳本数」を入力。
        if (_station?.isStation ?? false) _stationCard(),
      ],
    );
  }

  /// Mahalo Station固有: 明日のおやつ(翌日登園予定)と今日の牛乳本数(手入力・前日申告)。
  Widget _stationCard() {
    final s = _station!;
    final ctrl = TextEditingController(text: s.milkBottles?.toString() ?? '');
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    return Card(
      color: AppColors.skyBlue.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('明日のおやつ(登園予定)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text('${s.nextDaySnack} 名', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
              ],
            ),
            const SizedBox(width: 24),
            const Text('今日の牛乳', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixText: '本'),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : () => _run(() => widget.service.setMilkBottles(widget.officeId, _date, int.tryParse(ctrl.text.trim())), '牛乳本数を保存しました'),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suspendedBanner() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF3B4B4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🍱 給食停止中(弁当持参・アレルギー確認中) ${_suspended.length}名',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFC0392B))),
            const SizedBox(height: 4),
            const Text('この園児には給食を提供しないでください。', style: TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _suspended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '${s['child_name'] ?? ''}${(s['note'] != null && (s['note'] as String).isNotEmpty) ? ' (${s['note']})' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFC0392B)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _header() => Row(
        children: [
          const SizedBox(width: 132, child: Text('区分', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final s in _slots)
            Expanded(child: Center(child: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w800)))),
          const SizedBox(width: 96, child: Center(child: Text('確定', style: TextStyle(fontWeight: FontWeight.w800)))),
        ],
      );

  Widget _tapNum(String text, VoidCallback onTap, {Color? color}) => InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ),
      );

  // 1区分のセル。事務室=職のみ / 児職両方可(昼食・午後おやつのクラス)=児 X / 職 Y / それ以外=児のみ。
  Widget _slotCell(Map<String, dynamic> r, String slot, bool isStaff) {
    final cells = r['cells'] as Map<String, ({int child, int staff})>;
    final cell = cells[slot];
    if (cell == null) return const Text('—', style: TextStyle(color: AppColors.textSecondary));
    if (isStaff) {
      return _tapNum('${cell.staff}', () => _changeCell(r, slot, 'staff'));
    }
    if (_staffAllowed(r, slot)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _tapNum('児${cell.child}', () => _changeCell(r, slot, 'child')),
          const Text('/', style: TextStyle(color: AppColors.textSecondary)),
          _tapNum('職${cell.staff}', () => _changeCell(r, slot, 'staff'), color: AppColors.textSecondary),
        ],
      );
    }
    return _tapNum('${cell.child}', () => _changeCell(r, slot, 'child'));
  }

  Widget _row(Map<String, dynamic> r, int index) {
    final isStaff = r['type'] == 'staff';
    final confirmed = r['confirmed'] == true;
    return Container(
      color: index.isOdd ? const Color(0xFFF3F6FA) : null,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          SizedBox(width: 132, child: Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w600))),
          for (final s in _slots)
            Expanded(child: Center(child: _slotCell(r, s.key, isStaff))),
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

  // 職員給食をクラスに入力できる区分か。盛り付け配膳クラス(大和はな/そら/かぜ)の昼食/午後おやつのみ。
  // 後期/完了期は職員なし(=幼児食に含める)。それ以外(自分で盛り付け)は職員クラス入力なし。
  bool _staffAllowed(Map<String, dynamic> r, String slot) {
    if (slot == 'am_snack') return false;
    if (r['type'] != 'children') return false;
    if (r['plating'] != true) return false;
    final key = r['key'] as String? ?? '';
    if (key.endsWith('_late') || key.endsWith('_complete')) return false;
    return true;
  }

  Future<void> _changeCell(Map<String, dynamic> r, String slot, String field) async {
    final cells = r['cells'] as Map<String, ({int child, int staff})>;
    final cur = field == 'staff' ? cells[slot]!.staff : cells[slot]!.child;
    int selected = cur;
    const maxCount = 60; // 発注数の選択上限(必要なら拡張)
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${r['label']} / ${_slots.firstWhere((s) => s.key == slot).label} の${field == 'staff' ? '職員' : '園児'}数を変更'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('人数を選んでください', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 34,
                    onPressed: selected > 0 ? () => setLocal(() => selected--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  DropdownButton<int>(
                    value: selected,
                    itemHeight: 52,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                    items: [for (var i = 0; i <= maxCount; i++) DropdownMenuItem(value: i, child: Text('$i 名'))],
                    onChanged: (v) { if (v != null) setLocal(() => selected = v); },
                  ),
                  IconButton(
                    iconSize: 34,
                    onPressed: selected < maxCount ? () => setLocal(() => selected++) : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('変更')),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _run(
      () => widget.service.changeMealRow(widget.officeId, _date, _rowKeyOf(r), slot, field, result),
      '変更しました',
    );
  }
}
