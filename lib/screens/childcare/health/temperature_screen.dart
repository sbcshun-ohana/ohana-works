import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../widgets/time_dropdown_picker.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// 健康チェック(検温)。園児ごとに日中の検温を複数回 記録/削除する(188)。
/// 過去日はサーバー側で主任以上に限定(record/delete)。UIでも当日以外・非主任は操作不可を明示。
class TemperatureScreen extends StatefulWidget {
  const TemperatureScreen({
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
  State<TemperatureScreen> createState() => _TemperatureScreenState();
}

class _TemperatureScreenState extends State<TemperatureScreen> {
  late DateTime _businessDate = widget.businessDate;
  List<ChildcareClass> _classes = const [];
  String? _selectedClassId;
  bool _loading = true;
  List<({String childId, String nameLabel, String className})> _roster = const [];
  Map<String, List<ChildTemperatureRecord>> _byChild = const {};

  bool get _canEdit {
    final today = DateTime.now();
    final isToday = _businessDate.year == today.year && _businessDate.month == today.month && _businessDate.day == today.day;
    return isToday || widget.isManager; // 過去日は主任以上(サーバーと一致)
  }

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

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final records = await widget.service.fetchChildTemperaturesForOffice(widget.officeId, _businessDate);
      final List<({String childId, String nameLabel, String className})> roster;
      if (_selectedClassId != null) {
        final className = _classes
            .firstWhere((c) => c.classId == _selectedClassId,
                orElse: () => const ChildcareClass(classId: '', className: '', ageGroup: '', schoolYear: 0))
            .className;
        final children = await widget.service.fetchClassChildren(_selectedClassId!, _businessDate);
        roster = children
            .map((c) => (childId: c.childId, nameLabel: '${c.displayName}${c.honorificSuffix ?? ''}', className: className))
            .toList();
      } else {
        final children = await widget.service.fetchChildrenForOffice(widget.officeId);
        roster = children
            .map((c) => (childId: c.childId, nameLabel: '${c.displayName}${c.honorificSuffix ?? ''}', className: c.className ?? ''))
            .toList();
      }
      final byChild = <String, List<ChildTemperatureRecord>>{};
      for (final r in records) {
        byChild.putIfAbsent(r.childId, () => []).add(r);
      }
      if (mounted) {
        setState(() {
          _roster = roster;
          _byChild = byChild;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('検温情報の取得に失敗しました');
      }
    }
  }

  void _onDateChanged(DateTime d) {
    setState(() => _businessDate = d);
    _reload();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _hm(String dbTime) => dbTime.length >= 5 ? dbTime.substring(0, 5) : dbTime;

  Future<void> _addRecord(({String childId, String nameLabel, String className}) child) async {
    final t = await showTimeDropdownPicker(context: context, initialTime: TimeOfDay.now());
    if (t == null || !mounted) return;
    final temp = await _pickTemperature();
    if (temp == null) return;
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    try {
      await widget.service.recordChildTemperature(child.childId, _businessDate, hhmm, temp);
      await _reload();
    } catch (_) {
      _snack('記録に失敗しました(過去日は主任以上)');
    }
  }

  Future<double?> _pickTemperature() async {
    // 体温は 34.0〜42.0℃ を 0.1 刻みのプルダウンで選択(188のレンジに合わせる。俊確定)。
    final options = <double>[for (var i = 0; i <= 80; i++) double.parse((34.0 + i * 0.1).toStringAsFixed(1))];
    double selected = 36.5;
    return showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('体温(℃)'),
          content: DropdownButton<double>(
            value: selected,
            isExpanded: true,
            items: [
              for (final v in options)
                DropdownMenuItem(value: v, child: Text('${v.toStringAsFixed(1)} ℃')),
            ],
            onChanged: (v) => setState(() => selected = v ?? selected),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('記録')),
          ],
        ),
      ),
    );
  }

  // 排便(排泄)記録の性状。連絡帳の排泄欄(admin_web TOILETING_TYPES)と同一。
  static const List<String> _toiletingTypes = ['普通', '軟便', '硬便', '下痢便'];

  // 排便記録シート: 当日の記録を fetch し、時/分+性状プルダウンで追記・削除(194 RPC)。
  // データは連絡帳の toileting_records と同一実体(二重管理なし)。
  Future<void> _openToiletingSheet(({String childId, String nameLabel, String className}) child) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ToiletingSheet(
        service: widget.service,
        childId: child.childId,
        nameLabel: child.nameLabel,
        businessDate: _businessDate,
        canEdit: _canEdit,
        toiletingTypes: _toiletingTypes,
      ),
    );
  }

  Future<void> _deleteRecord(String childId, ChildTemperatureRecord rec) async {
    if (!await _confirm('${_hm(rec.measuredAt)} ${rec.temperature}℃ を削除しますか?')) return;
    try {
      await widget.service.deleteChildTemperature(childId, _businessDate, _hm(rec.measuredAt));
      await _reload();
    } catch (_) {
      _snack('削除に失敗しました(過去日は主任以上)');
    }
  }

  Future<bool> _confirm(String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        toolbarHeight: 48,
        titleSpacing: 0,
        title: const Text('健康チェック(検温)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [BusinessDateAction(date: _businessDate, onChanged: _onDateChanged)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedClassId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'クラス', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('全クラス')),
                      for (final c in _classes) DropdownMenuItem<String?>(value: c.classId, child: Text(c.className)),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedClassId = v);
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if (!_canEdit)
                  const Expanded(
                    child: Text('過去日の記録・削除は主任以上のみ可能です', style: TextStyle(fontSize: 12, color: AppColors.punchClockOut)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _roster.isEmpty
                    ? const Center(child: Text('対象の園児がいません'))
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: _roster.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final child = _roster[i];
                            final recs = _byChild[child.childId] ?? const [];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 140,
                                      child: Text(child.nameLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    ),
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          for (final r in recs)
                                            Chip(
                                              label: Text('${_hm(r.measuredAt)} ${r.temperature}℃'),
                                              onDeleted: _canEdit ? () => _deleteRecord(child.childId, r) : null,
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          if (recs.isEmpty)
                                            const Text('検温 未記録', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_canEdit)
                                          OutlinedButton.icon(
                                            onPressed: () => _addRecord(child),
                                            icon: const Icon(Icons.add, size: 16),
                                            label: const Text('検温'),
                                          ),
                                        const SizedBox(height: 4),
                                        OutlinedButton.icon(
                                          onPressed: () => _openToiletingSheet(child),
                                          icon: const Icon(Icons.wc_rounded, size: 16),
                                          label: const Text('排便'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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

/// 排便記録シート(194 RPC)。当日の記録を一覧・時/分+性状プルダウンで追記・削除。
/// データは連絡帳の child_daily_contacts.toileting_records と同一実体。
class _ToiletingSheet extends StatefulWidget {
  const _ToiletingSheet({
    required this.service,
    required this.childId,
    required this.nameLabel,
    required this.businessDate,
    required this.canEdit,
    required this.toiletingTypes,
  });

  final ChildcareService service;
  final String childId;
  final String nameLabel;
  final DateTime businessDate;
  final bool canEdit;
  final List<String> toiletingTypes;

  @override
  State<_ToiletingSheet> createState() => _ToiletingSheetState();
}

class _ToiletingSheetState extends State<_ToiletingSheet> {
  List<({String time, String type})> _records = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await widget.service.fetchToiletingRecords(widget.childId, widget.businessDate);
      if (mounted) setState(() { _records = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _add() async {
    final t = await showTimeDropdownPicker(context: context, initialTime: TimeOfDay.now());
    if (t == null || !mounted) return;
    final type = await _pickType();
    if (type == null) return;
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => _busy = true);
    try {
      await widget.service.addToiletingRecord(widget.childId, widget.businessDate, hhmm, type);
      await _load();
    } catch (_) {
      _snack('記録に失敗しました(過去日・公開後は主任以上)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickType() {
    String selected = widget.toiletingTypes.first;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('便の性状'),
          content: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            items: [for (final t in widget.toiletingTypes) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => selected = v ?? selected),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('記録')),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(int index) async {
    setState(() => _busy = true);
    try {
      await widget.service.deleteToiletingRecord(widget.childId, widget.businessDate, index);
      await _load();
    } catch (_) {
      _snack('削除に失敗しました(過去日・公開後は主任以上)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('排便記録 — ${widget.nameLabel}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                if (widget.canEdit)
                  FilledButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('追加'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_records.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('記録はありません', style: TextStyle(color: AppColors.textSecondary)))
            else
              ..._records.asMap().entries.map((e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.wc_rounded, color: AppColors.skyBlue),
                    title: Text('${e.value.time}  ${e.value.type}'),
                    trailing: widget.canEdit
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 20),
                            onPressed: _busy ? null : () => _delete(e.key),
                          )
                        : null,
                  )),
          ],
        ),
      ),
    );
  }
}
