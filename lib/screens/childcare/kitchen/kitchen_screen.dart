import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';

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

class _KitchenScreenState extends State<KitchenScreen> {
  late DateTime _date = widget.businessDate;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _board = const [];
  List<Map<String, dynamic>> _changes = const [];
  List<({String childId, String childName, String? className, String? handling, List<String> targets})> _special =
      const [];
  List<Map<String, dynamic>> _suspended = const [];

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
      final special = await widget.service.fetchDailyEliminationForOffice(widget.officeId, _date);
      final changes = await widget.service.fetchMealChanges(widget.officeId, _date);
      List<Map<String, dynamic>> suspended = const [];
      try {
        suspended = await widget.service.fetchMealSuspendedChildren(widget.officeId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _board = board;
        _special = special;
        _changes = changes;
        _suspended = suspended;
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
        actions: [BusinessDateAction(date: _date, onChanged: _onDateChanged)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    if (_unacked.isNotEmpty) _alertBanner(),
                    Expanded(child: RefreshIndicator(onRefresh: _load, child: _body())),
                  ],
                ),
    );
  }

  /// §5.2 大型全面アラート(確定後に変更があったとき)。
  Widget _alertBanner() {
    return Material(
      color: AppColors.punchClockOut,
      child: InkWell(
        onTap: _acknowledge,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              const Icon(Icons.notification_important_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text('食数の更新があります(${_unacked.length}件) — タップで変更点を確認',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
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
        const SizedBox(height: 24),
      ],
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

  Widget _chips(List<({String childId, String childName, String? className, String? handling, List<String> targets})> list) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in list)
            Chip(label: Text('${s.childName}${s.className != null ? '(${s.className})' : ''}')),
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
