import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../models/nap.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// Phase 3 §3: 午睡チェック(iPad)。5分グリッドで身体の向き(4種)+呼吸/顔色/寝具の確認を記録。
/// 権限(§3.5)はRPC側で判定(当日30分以内=一般職員可・30分超/過去日=主任以上)。
/// スロットは5分刻み(UTC整列=fetch_nap_missing_slots と同一の instant)で、表示はJST。
class NapCheckScreen extends StatefulWidget {
  const NapCheckScreen({
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
  State<NapCheckScreen> createState() => _NapCheckScreenState();
}

class _NapCheckScreenState extends State<NapCheckScreen> {
  List<ChildcareClass> _classes = const [];
  String? _selectedClassId;
  Future<List<NapSessionRow>>? _future;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _reload();
  }

  Future<void> _loadClasses() async {
    final c = await widget.service.fetchChildcareClasses(widget.officeId);
    if (mounted) setState(() => _classes = c);
  }

  void _reload() {
    _future = widget.service.fetchNapBoard(widget.officeId, widget.businessDate, classId: _selectedClassId);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  // 5分床(UTC整列)。
  static DateTime _floor5(DateTime t) {
    final u = t.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute - (u.minute % 5));
  }

  // 入眠〜min(起床, now) の5分スロット列(切り上げ初回)。
  List<DateTime> _slotsFor(NapSessionRow s) {
    final start = s.sleepStartAt;
    if (start == null) return const [];
    var first = _floor5(start);
    if (first.isBefore(start.toUtc())) first = first.add(const Duration(minutes: 5));
    final now = DateTime.now().toUtc();
    final upper = s.wakeUpAt != null && s.wakeUpAt!.toUtc().isBefore(now) ? s.wakeUpAt!.toUtc() : now;
    final slots = <DateTime>[];
    for (var t = first; !t.isAfter(upper); t = t.add(const Duration(minutes: 5))) {
      slots.add(t);
    }
    return slots;
  }

  DateTime _combine(TimeOfDay t) => DateTime(
        widget.businessDate.year,
        widget.businessDate.month,
        widget.businessDate.day,
        t.hour,
        t.minute,
      );

  Future<void> _classBulkStart() async {
    if (_selectedClassId == null) {
      _snack('クラスを選択してください');
      return;
    }
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    await _guard(() => widget.service.startNapSessionsForClass(_selectedClassId!, _combine(t)));
  }

  Future<void> _classBulkEnd() async {
    if (_selectedClassId == null) {
      _snack('クラスを選択してください');
      return;
    }
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    await _guard(() => widget.service.endNapSessionsForClass(_selectedClassId!, widget.businessDate, _combine(t)));
  }

  // 現在スロットをクラス一括で「変化なし」複製。
  Future<void> _classBulkCopy() async {
    if (_selectedClassId == null) {
      _snack('クラスを選択してください');
      return;
    }
    final slot = _floor5(DateTime.now());
    await _guard(() async {
      final n = await widget.service.copyPreviousNapChecksForClass(_selectedClassId!, widget.businessDate, slot);
      _snack('$n 件を複製しました');
    });
  }

  Future<void> _addChild() async {
    if (_selectedClassId == null) {
      _snack('クラスを選択してください');
      return;
    }
    final children = await widget.service.fetchClassChildren(_selectedClassId!, widget.businessDate);
    if (!mounted) return;
    final picked = await showModalBottomSheet<ClassChild>(
      context: context,
      builder: (_) => ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('入眠する園児を選択', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          for (final c in children)
            ListTile(
              title: Text('${c.displayName}${c.honorificSuffix ?? ''}'),
              onTap: () => Navigator.of(context).pop(c),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    await _guard(() => widget.service.startNapSession(picked.childId, _combine(t)));
  }

  Future<void> _endSession(NapSessionRow s) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    await _guard(() => widget.service.endNapSession(s.sessionId, _combine(t)));
  }

  Future<void> _openCell(NapSessionRow s, DateTime slot) async {
    final existing = s.checkAt(slot);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NapCheckSheet(
        service: widget.service,
        sessionId: s.sessionId,
        childName: s.nameLabel,
        slotAt: slot,
        existing: existing,
        hasPrev: s.checkAt(slot.subtract(const Duration(minutes: 5))) != null,
      ),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
      await _refresh();
    } catch (_) {
      _snack('操作に失敗しました(権限をご確認ください: 30分超・過去日は主任以上)');
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 180,
        title: const Text('午睡チェック'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedClassId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'クラス', isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('全クラス')),
                for (final c in _classes) DropdownMenuItem<String?>(value: c.classId, child: Text(c.className)),
              ],
              onChanged: (v) => setState(() {
                _selectedClassId = v;
                _reload();
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                    onPressed: _classBulkStart, icon: const Icon(Icons.bedtime_rounded, size: 18), label: const Text('入眠(一括)')),
                FilledButton.tonalIcon(
                    onPressed: _classBulkEnd, icon: const Icon(Icons.wb_sunny_rounded, size: 18), label: const Text('起床(一括)')),
                OutlinedButton.icon(
                    onPressed: _classBulkCopy, icon: const Icon(Icons.copy_all_rounded, size: 18), label: const Text('変化なし一括')),
                OutlinedButton.icon(
                    onPressed: _addChild, icon: const Icon(Icons.person_add_alt_rounded, size: 18), label: const Text('園児を追加')),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<NapSessionRow>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snap.data ?? const <NapSessionRow>[];
                  if (rows.isEmpty) {
                    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                      SizedBox(height: 120),
                      Center(child: Text('午睡セッションがありません(入眠で開始)')),
                    ]);
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _SessionCard(
                      row: rows[i],
                      slots: _slotsFor(rows[i]),
                      onCellTap: (slot) => _openCell(rows[i], slot),
                      onEnd: rows[i].wakeUpAt == null ? () => _endSession(rows[i]) : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.row, required this.slots, required this.onCellTap, this.onEnd});

  final NapSessionRow row;
  final List<DateTime> slots;
  final void Function(DateTime slot) onCellTap;
  final VoidCallback? onEnd;

  String _hm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${row.nameLabel}  ${row.className}'
                    '${row.sleepStartAt != null ? '  入眠 ${_hm(row.sleepStartAt!)}' : ''}'
                    '${row.wakeUpAt != null ? '  起床 ${_hm(row.wakeUpAt!)}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (onEnd != null)
                  TextButton(onPressed: onEnd, child: const Text('起床')),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final slot in slots)
                    _SlotCell(
                      timeLabel: _hm(slot),
                      check: row.checkAt(slot),
                      isPastMissing: row.checkAt(slot) == null && slot.isBefore(now),
                      onTap: () => onCellTap(slot),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotCell extends StatelessWidget {
  const _SlotCell({required this.timeLabel, required this.check, required this.isPastMissing, required this.onTap});

  final String timeLabel;
  final NapCheck? check;
  final bool isPastMissing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final String body;
    if (check != null) {
      bg = AppColors.leafGreen.withValues(alpha: 0.22);
      body = napBodyPositions[check!.bodyPosition] ?? check!.bodyPosition;
    } else if (isPastMissing) {
      bg = AppColors.punchClockOut.withValues(alpha: 0.20); // 未チェック警告
      body = '未';
    } else {
      bg = AppColors.textSecondary.withValues(alpha: 0.08);
      body = '—';
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Text(timeLabel, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(body, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// セルタップ時の入力シート。身体の向き(4種)+呼吸/顔色/寝具+「5分前と同じ」。
class _NapCheckSheet extends StatefulWidget {
  const _NapCheckSheet({
    required this.service,
    required this.sessionId,
    required this.childName,
    required this.slotAt,
    required this.existing,
    required this.hasPrev,
  });

  final ChildcareService service;
  final String sessionId;
  final String childName;
  final DateTime slotAt;
  final NapCheck? existing;
  final bool hasPrev;

  @override
  State<_NapCheckSheet> createState() => _NapCheckSheetState();
}

class _NapCheckSheetState extends State<_NapCheckSheet> {
  late String _body = widget.existing?.bodyPosition ?? 'supine';
  late bool _breathing = widget.existing?.breathing ?? true;
  late bool _complexion = widget.existing?.complexion ?? true;
  late bool _bedding = widget.existing?.bedding ?? true;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.recordNapCheck(
        widget.sessionId,
        widget.slotAt,
        bodyPosition: _body,
        breathing: _breathing,
        complexion: _complexion,
        bedding: _bedding,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('記録に失敗しました(30分超・過去日は主任以上)')),
        );
      }
    }
  }

  Future<void> _copyPrev() async {
    setState(() => _saving = true);
    try {
      await widget.service.copyPreviousNapCheck(widget.sessionId, widget.slotAt);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('複製に失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.slotAt.toLocal();
    final hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.childName}  $hm', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          const Text('身体の向き', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final e in napBodyPositions.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _body == e.key,
                  onSelected: (_) => setState(() => _body = e.key),
                ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('呼吸を確認'),
            value: _breathing,
            onChanged: (v) => setState(() => _breathing = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('顔色を確認'),
            value: _complexion,
            onChanged: (v) => setState(() => _complexion = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('寝具の状態を確認'),
            value: _bedding,
            onChanged: (v) => setState(() => _bedding = v ?? false),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.hasPrev)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : _copyPrev,
                    child: const Text('5分前と同じ'),
                  ),
                ),
              if (widget.hasPrev) const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
