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
  List<Map<String, dynamic>> _orderers = const []; // 職員給食の発注者(369)
  List<Map<String, dynamic>> _officeEmps = const []; // 追加候補
  ({bool am, bool lunch, bool pm}) _noSvc = (am: false, lunch: false, pm: false); // 提供なし(366)
  List<Map<String, dynamic>> _unconfirmed = const []; // 未承認確定日(370)

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
      var orderers = const <Map<String, dynamic>>[];
      var officeEmps = const <Map<String, dynamic>>[];
      var noSvc = (am: false, lunch: false, pm: false);
      var unconfirmed = const <Map<String, dynamic>>[];
      try { orderers = await widget.service.fetchStaffMealDayOrderers(widget.officeId, _date); } catch (_) {}
      try { officeEmps = await widget.service.fetchOfficeEmployees(widget.officeId); } catch (_) {}
      try { noSvc = await widget.service.fetchMealNoService(widget.officeId, _date); } catch (_) {}
      try { unconfirmed = await widget.service.fetchUnconfirmedFinalizedDays(); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _board = board;
        _suspended = suspended;
        _station = station;
        _orderers = orderers;
        _officeEmps = officeEmps;
        _noSvc = noSvc;
        _unconfirmed = unconfirmed;
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

    final allConfirmed = rows.isNotEmpty && rows.every((r) => r['confirmed'] == true);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_unconfirmed.isNotEmpty) _unconfirmedBanner(),
        const Padding(
          padding: EdgeInsets.only(bottom: 8, left: 4),
          child: Text('9:31に自動算出された暫定値です。数字をタップで期限内変更(昼食10:00/午後14:00/朝9:30)。「この日を承認」で一括確定。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
        // その日の一括承認(クラスごとの承認は不要)。承認前でも厨房ボードには表示される。
        Card(
          color: allConfirmed ? AppColors.leafGreen.withValues(alpha: 0.1) : AppColors.warmOrange.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              children: [
                Icon(allConfirmed ? Icons.check_circle : Icons.pending_actions, color: allConfirmed ? AppColors.leafGreen : AppColors.warmOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(allConfirmed ? 'この日の発注数は承認済みです' : 'この日の発注数は未承認(確認中)です',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                if (allConfirmed)
                  OutlinedButton(onPressed: _busy ? null : () => _confirmDay(false), child: const Text('承認を解除'))
                else
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.leafGreen),
                    onPressed: _busy ? null : () => _confirmDay(true),
                    child: const Text('この日を承認'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_suspended.isNotEmpty) _suspendedBanner(),
        _orderersCard(),
        _noServiceCard(),
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
        // 職員の配分バランス(盛り付けクラスがある施設のみ)。発注予定(参加職員) vs クラス配分の合計。
        if (rows.any((r) => r['plating'] == true)) _staffBalanceCard(rows),
        // Mahalo Station固有(340): 食数確認の流れの中で「明日のおやつ+今日の牛乳本数」を入力。
        if (_station?.isStation ?? false) _stationCard(),
      ],
    );
  }

  // 未承認確定日のアラート(承認忘れ)。
  Widget _unconfirmedBanner() => Card(
        color: AppColors.warmOrange.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('⚠ 一括承認がされていない確定日があります(${_unconfirmed.length}件)',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.warmOrange)),
              const SizedBox(height: 2),
              const Text('9:31に自動確定して厨房へ送信済みですが、朝礼での承認が押されていません。内容を確認して承認してください。',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );

  // 職員給食の発注者一覧(朝の確認・その場で追加/削除)。
  Widget _orderersCard() {
    final orderIds = _orderers.map((o) => o['employee_id']).toSet();
    final addable = _officeEmps.where((e) => !orderIds.contains(e['employee_id'])).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('職員給食の発注者(${_orderers.length}名)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                if (addable.isNotEmpty)
                  TextButton.icon(onPressed: _busy ? null : () => _showAddOrderer(addable), icon: const Icon(Icons.add, size: 18), label: const Text('追加')),
              ],
            ),
            const SizedBox(height: 4),
            if (_orderers.isEmpty)
              const Text('この日の発注者はいません。', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final o in _orderers)
                    Chip(
                      label: Text('${o['employee_name']}${o['source'] == 'manual' ? ' (手動)' : ''}', style: const TextStyle(fontSize: 13)),
                      onDeleted: _busy ? null : () => _run(() => widget.service.setStaffMealDay(widget.officeId, _date, o['employee_id'] as String, false), ''),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            const Text('来ていないのに発注が入っている場合は × で削除。追加は締切(8:55)まで。', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  void _showAddOrderer(List<Map<String, dynamic>> addable) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(padding: EdgeInsets.all(12), child: Text('発注に追加する職員', style: TextStyle(fontWeight: FontWeight.w800))),
            for (final e in addable)
              ListTile(
                title: Text(e['name'] as String),
                onTap: () {
                  Navigator.pop(ctx);
                  _run(() => widget.service.setStaffMealDay(widget.officeId, _date, e['employee_id'] as String, true), '');
                },
              ),
          ],
        ),
      ),
    );
  }

  // 給食「提供なし」トグル(区分別)。
  Widget _noServiceCard() {
    Widget btn(String slot, String label, bool on) => Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 4),
          child: on
              ? FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.warmOrange),
                  onPressed: _busy ? null : () => _run(() => widget.service.setMealNoService(widget.officeId, _date, slot, false), ''),
                  child: Text('✓ $label 提供なし'))
              : OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => widget.service.setMealNoService(widget.officeId, _date, slot, true), ''),
                  child: Text(label)),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('給食「提供なし」', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            Wrap(children: [btn('am_snack', '朝おやつ', _noSvc.am), btn('lunch', '昼食', _noSvc.lunch), btn('pm_snack', '午後おやつ', _noSvc.pm)]),
            const SizedBox(height: 2),
            const Text('昼食を提供なしにすると職員給食も全員キャンセルされます。一部クラスだけ弁当の場合は発注者から個別に削除してください。',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  int _cellStaff(Map<String, dynamic> r, String slot) =>
      (r['cells'] as Map<String, ({int child, int staff})>?)?[slot]?.staff ?? 0;

  // 職員給食の配分バランス。発注予定(職員)=事務室(職員)行の自動集計(参加職員)。クラス配分=各クラスの職員入力合計。
  Widget _staffBalanceCard(List<Map<String, dynamic>> rows) {
    final staffRow = rows.where((r) => r['type'] == 'staff').toList();
    Widget line(String slot, String label) {
      final planned = staffRow.isEmpty ? 0 : _cellStaff(staffRow.first, slot);
      final allocated = rows.where((r) => r['type'] == 'children' && r['plating'] == true).fold<int>(0, (a, r) => a + _cellStaff(r, slot));
      final rest = planned - allocated;
      final over = allocated > planned;
      if (planned == 0 && allocated == 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 88, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
            Text('発注予定 $planned', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Text(' ／ ', style: TextStyle(color: AppColors.textSecondary)),
            Text('クラス配分 $allocated', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: over ? AppColors.punchClockOut : AppColors.textPrimary)),
            const Text(' ／ ', style: TextStyle(color: AppColors.textSecondary)),
            Text(over ? '超過 ${-rest}' : '未配分 $rest',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: over ? AppColors.punchClockOut : (rest > 0 ? AppColors.warmOrange : AppColors.leafGreen))),
          ],
        ),
      );
    }
    return Card(
      color: AppColors.skyBlue.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('職員給食の配分(盛り付け)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const Text('発注予定=参加職員(シフト自動)。各クラスへ配分し、超過しないように調整。残りは事務室で喫食。', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            line('lunch', '昼食'),
            line('pm_snack', '午後おやつ'),
          ],
        ),
      ),
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
          const SizedBox(width: 72, child: Center(child: Text('確定', style: TextStyle(fontWeight: FontWeight.w800)))),
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
            width: 72,
            child: Center(
              child: confirmed
                  ? const Icon(Icons.check_circle, color: AppColors.leafGreen, size: 20)
                  : const Text('確認中', style: TextStyle(fontSize: 12, color: AppColors.warmOrange)),
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

  // その日の発注数を一括承認/解除(クラスごとの承認は不要)。
  Future<void> _confirmDay(bool confirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirm ? 'この日の発注数を承認' : '承認を解除'),
        content: Text(confirm ? 'この日の全区分の食数を一括で確定します。よろしいですか?' : 'この日の承認を解除して再修正できるようにします。よろしいですか?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm ? '承認' : '解除')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => confirm ? widget.service.confirmMealDay(widget.officeId, _date) : widget.service.unconfirmMealDay(widget.officeId, _date),
      confirm ? '承認しました' : '承認を解除しました',
    );
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
