import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import 'meal_photo_screen.dart';

/// 厨房ページ(給食管理 Phase 2・設計指示書v1.0 §5)。給食情報のみを表示し、他の保育業務へは遷移しない。
/// 行区分×食事区分の食数(暫定/確定)・共通除去食の対象児・弁当/保留・変更の大型アラート(§5.2)。
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

const _slots = [
  (key: 'am_snack', label: '朝おやつ'),
  (key: 'lunch', label: '昼食'),
  (key: 'pm_snack', label: '午後おやつ'),
];

class _KitchenScreenState extends State<KitchenScreen> with SingleTickerProviderStateMixin {
  late DateTime _date = widget.businessDate;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _board = const [];
  List<Map<String, dynamic>> _changes = const [];
  List<({String childId, String childName, String? className, String? handling, List<String> targets, String? consentStatus})> _special =
      const [];
  List<Map<String, dynamic>> _suspended = const [];
  int? _leftover; // その日の残量(g)
  ({bool isStation, int? milkBottles, int nextDaySnack})? _station; // Station固有(340)
  List<Map<String, dynamic>> _menu = const []; // 本日の献立(342・献立管理AC-06)
  late final AnimationController _flash;

  @override
  void initState() {
    super.initState();
    // 変更アラート用の点滅アニメーション(厨房が見落とさないよう全画面で点滅)。
    _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await widget.service.fetchMealBoard(widget.officeId, _date);
      final special = await widget.service.fetchDailyEliminationForOffice(widget.officeId, _date);
      final changes = await widget.service.fetchMealChanges(widget.officeId, _date);
      List<Map<String, dynamic>> suspended = const [];
      try {
        suspended = await widget.service.fetchMealSuspendedChildren(widget.officeId);
      } catch (_) {}
      int? leftover;
      try {
        final sum = await widget.service.fetchMealMonthlySummary(widget.officeId, _date.year, _date.month);
        final ds = _date.toIso8601String().substring(0, 10);
        final row = sum.where((r) => (r['business_date'] as String?) == ds).firstOrNull;
        leftover = (row?['leftover_grams'] as num?)?.toInt();
      } catch (_) {}
      ({bool isStation, int? milkBottles, int nextDaySnack})? station;
      try {
        station = await widget.service.fetchMealStationExtras(widget.officeId, _date);
      } catch (_) {}
      List<Map<String, dynamic>> menu = const [];
      try {
        menu = await widget.service.fetchPublishedMenuDay(widget.officeId, _date);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _board = board;
        _special = special;
        _changes = changes;
        _suspended = suspended;
        _leftover = leftover;
        _station = station;
        _menu = menu;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '食数情報の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  void _onDateChanged(DateTime d) {
    setState(() => _date = d);
    _load();
  }

  List<Map<String, dynamic>> get _unacked =>
      _changes.where((c) => c['acknowledged_at'] == null).toList();

  Future<void> _acknowledge() async {
    // 変更前→後を確認するダイアログ → 確認で通常表示へ。
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('食数の変更を確認'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in _unacked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${c['row_label'] ?? ''}  ${_slotLabel(c['meal_slot'] as String?)}  '
                    '${c['field'] == 'staff' ? '職員' : '園児'} ${c['old_count']} → ${c['new_count']}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
          FilledButton(
            onPressed: () async {
              await widget.service.acknowledgeMealChanges(widget.officeId, _date);
              if (ctx.mounted) Navigator.pop(ctx);
              await _load();
            },
            child: const Text('確認しました'),
          ),
        ],
      ),
    );
  }

  String _slotLabel(String? key) => _slots.firstWhere((s) => s.key == key, orElse: () => _slots[1]).label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        title: const Text('給食管理'),
        actions: [
          IconButton(
            tooltip: '給食写真',
            icon: const Icon(Icons.photo_camera_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MealPhotoScreen(
                service: widget.service,
                officeId: widget.officeId,
                businessDate: _date,
                isManager: false, // 厨房は撮影・自分の未公開削除まで(承認は食数ボード/adminで)
              ),
            )),
          ),
          BusinessDateAction(date: _date, onChanged: _onDateChanged),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Stack(
                  children: [
                    RefreshIndicator(onRefresh: _load, child: _body()),
                    // §5.2 厨房が見落とさないよう、確定後の変更は全画面点滅オーバーレイで通知。
                    if (_unacked.isNotEmpty) _fullScreenAlert(),
                  ],
                ),
    );
  }

  /// §5.2 全画面・点滅アラート(確定後に変更があったとき)。タップで変更点→確認。
  Widget _fullScreenAlert() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _flash,
        builder: (context, child) {
          final t = _flash.value; // 0..1
          return Material(
            color: Color.lerp(const Color(0xE6D7263D), const Color(0xF2B00020), t),
            child: child,
          );
        },
        child: InkWell(
          onTap: _acknowledge,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notification_important_rounded, color: Colors.white, size: 88),
                  const SizedBox(height: 16),
                  const Text('食数の変更があります', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('${_unacked.length}件の変更が未確認です', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: const Text('タップして変更点を確認', style: TextStyle(color: Color(0xFFB00020), fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    // ピボット: row_key → {label, type, sort, slots}
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

    // 合計
    final total = {for (final s in _slots) s.key: (child: 0, staff: 0)};
    for (final r in rows) {
      final cells = r['cells'] as Map<String, ({int child, int staff})>;
      for (final s in _slots) {
        final c = cells[s.key];
        if (c == null) continue;
        final t = total[s.key]!;
        total[s.key] = r['type'] == 'staff'
            ? (child: t.child, staff: t.staff + c.staff)
            : (child: t.child + c.child, staff: t.staff);
      }
    }

    final elimination = _special.where((s) => s.handling == 'elimination').toList();
    final bento = _special.where((s) => s.handling == 'bento').toList();
    final hold = _special.where((s) => s.handling == 'hold').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 給食停止中(弁当持参・アレルギー確認中)。誤提供防止のため最上部に大きく表示(271)。
        if (_suspended.isNotEmpty) ...[
          _sectionTitle('給食停止中(弁当持参・アレルギー確認中)', AppColors.punchClockOut, _suspended.length),
          ..._suspended.map((s) => Card(
                color: AppColors.punchClockOut.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Text('🍱  ', style: TextStyle(fontSize: 18)),
                      Expanded(
                        child: Text(
                          '${s['child_name'] ?? ''}${(s['note'] != null && (s['note'] as String).isNotEmpty) ? '  (${s['note']})' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                      const Text('給食提供なし', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.punchClockOut)),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 16),
        ],
        // 食数表
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _boardHeader(),
                const Divider(height: 12),
                for (var i = 0; i < rows.length; i++) _boardRow(rows[i], i),
                const Divider(height: 12),
                _totalRow(total),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 共通除去食(誤配膳防止・大きく)
        _sectionTitle('共通除去食の対象児', AppColors.punchClockOut, elimination.length),
        if (elimination.isEmpty)
          _emptyLine('対象児はいません')
        else
          ...elimination.map((s) => Card(
                color: AppColors.punchClockOut.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${s.childName}${s.className != null ? '  (${s.className})' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          for (final t in s.targets)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                  color: AppColors.punchClockOut, borderRadius: BorderRadius.circular(10)),
                              child: Text(t,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 12),

        _sectionTitle('弁当持参', AppColors.textSecondary, bento.length),
        if (bento.isEmpty) _emptyLine('対象児はいません') else _chips(bento),
        const SizedBox(height: 12),
        _sectionTitle('給食開始保留', AppColors.warmOrange, hold.length),
        if (hold.isEmpty) _emptyLine('対象児はいません') else _chips(hold),
        const SizedBox(height: 16),
        if (_menu.isNotEmpty) ...[
          _menuCard(),
          const SizedBox(height: 16),
        ],
        if (_station?.isStation ?? false) ...[
          _stationCard(),
          const SizedBox(height: 16),
        ],
        _leftoverCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  /// 本日の献立(342・献立管理AC-06)。公開済みの通常食種を食種×区分で表示。
  Widget _menuCard() {
    const foodLabels = {
      'regular_over3': '以上児', 'regular_under3': '未満児',
      'weaning_late': '離乳食後期', 'weaning_final': '完了期',
    };
    const slotLabels = {'am_snack': '午前おやつ', 'lunch': '昼食', 'pm_snack': '午後おやつ'};
    final rows = _menu.where((m) => m['removal_kind'] == null).toList();
    final foodTypes = <String>[];
    for (final r in rows) {
      final ft = r['food_type'] as String? ?? '';
      if (ft.isNotEmpty && !foodTypes.contains(ft)) foodTypes.add(ft);
    }
    return Card(
      color: AppColors.leafGreen.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本日の献立', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            for (final ft in foodTypes) ...[
              Text(foodLabels[ft] ?? ft, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.skyBlue)),
              for (final slot in ['am_snack', 'lunch', 'pm_snack'])
                ...rows
                    .where((m) => m['food_type'] == ft && m['meal_slot'] == slot && (m['menu_text'] as String?)?.trim().isNotEmpty == true)
                    .map((m) => Padding(
                          padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                          child: Text('${slotLabels[slot] ?? slot}: ${(m['menu_text'] as String).trim()}', style: const TextStyle(fontSize: 13)),
                        )),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// Mahalo Station固有(340): 明日のおやつ(翌日登園予定数)と今日の牛乳本数(手入力)。
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
              onPressed: () async {
                final n = int.tryParse(ctrl.text.trim());
                try {
                  await widget.service.setMilkBottles(widget.officeId, _date, n);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('牛乳本数を保存しました')));
                  await _load();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存できません: $e')));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// その日の残量(g)入力(304)。施設×日×1項目。
  Widget _leftoverCard() {
    final ctrl = TextEditingController(text: _leftover?.toString() ?? '');
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Text('本日の残量', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(width: 16),
            SizedBox(
              width: 140,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, suffixText: 'g'),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () async {
                final g = int.tryParse(ctrl.text.trim());
                try {
                  await widget.service.setMealLeftover(widget.officeId, _date, g);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('残量を保存しました')));
                  await _load();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存できません: $e')));
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardHeader() => Row(
        children: [
          const SizedBox(width: 140, child: Text('区分', style: TextStyle(fontWeight: FontWeight.w800))),
          for (final s in _slots)
            Expanded(child: Center(child: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w800)))),
          const SizedBox(width: 64, child: Center(child: Text('確定', style: TextStyle(fontWeight: FontWeight.w800)))),
        ],
      );

  Widget _boardRow(Map<String, dynamic> r, int index) {
    final cells = r['cells'] as Map<String, ({int child, int staff})>;
    final isStaff = r['type'] == 'staff';
    return Container(
      color: index.isOdd ? const Color(0xFFF3F6FA) : null,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w600))),
          for (final s in _slots)
            Expanded(
              child: Center(
                child: cells[s.key] == null
                    ? const Text('—', style: TextStyle(color: AppColors.textSecondary))
                    : Text('${isStaff ? cells[s.key]!.staff : cells[s.key]!.child}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ),
          SizedBox(
            width: 64,
            child: Center(
              child: r['confirmed'] == true
                  ? const Icon(Icons.check_circle, color: AppColors.leafGreen, size: 20)
                  : const Text('確認中', style: TextStyle(fontSize: 11, color: AppColors.warmOrange)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(Map<String, ({int child, int staff})> total) => Row(
        children: [
          const SizedBox(width: 140, child: Text('合計(提供/職員)', style: TextStyle(fontWeight: FontWeight.w900))),
          for (final s in _slots)
            Expanded(
              child: Center(
                child: Text(
                  '${total[s.key]!.child}${total[s.key]!.staff > 0 ? ' / 職員${total[s.key]!.staff}' : ''}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.leafGreen),
                ),
              ),
            ),
          const SizedBox(width: 64),
        ],
      );

  Widget _chips(List<({String childId, String childName, String? className, String? handling, List<String> targets, String? consentStatus})> list) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in list)
            Chip(
              label: Text('${s.childName}${s.className != null ? '(${s.className})' : ''}'
                  '${s.consentStatus == 'pending' ? ' ・同意待ち' : ''}'),
              backgroundColor: s.consentStatus == 'pending' ? AppColors.warmOrange.withValues(alpha: 0.12) : null,
            ),
        ],
      );

  Widget _sectionTitle(String title, Color color, int count) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
            const SizedBox(width: 8),
            Text('$count名', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _emptyLine(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );
}
