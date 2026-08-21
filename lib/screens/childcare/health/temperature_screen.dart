import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../widgets/time_dropdown_picker.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// 健康チェック(188検温+194排便+199ミルク/食事)。6タブ構成(俊確定 2026-08-13):
/// 検温/排便/ミルク/午前おやつ/昼食/午後おやつ。縦=園児一覧、タブごとに一覧のまま連続入力できる。
/// 年齢絞り込み(UI側): ミルク=生後18ヶ月未満、おやつ/昼食=0・1・2歳児(実年齢3歳未満)。
/// 過去日はサーバー側で主任以上に限定。UIでも当日以外・非主任は操作不可を明示。
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

/// タブ定義。key はDBのスロット名/内部識別子。
const List<({String key, String label})> _healthTabs = [
  (key: 'temp', label: '検温'),
  (key: 'toileting', label: '排便'),
  (key: 'milk', label: 'ミルク'),
  (key: 'am_snack', label: '午前おやつ'),
  (key: 'lunch', label: '昼食'),
  (key: 'pm_snack', label: '午後おやつ'),
];

class _TemperatureScreenState extends State<TemperatureScreen> {
  late DateTime _businessDate = widget.businessDate;
  List<ChildcareClass> _classes = const [];
  String? _selectedClassId;
  String _tab = 'temp';
  bool _loading = true;
  List<({String childId, String nameLabel, String className})> _roster = const [];
  Map<String, List<ChildTemperatureRecord>> _byChild = const {};
  // 199一括取得: childId→(birthDate, 排便, ミルク, 食事)。
  Map<String,
          ({
            DateTime birthDate,
            List<({String time, String type})> toileting,
            List<({String time, int amountMl})> milk,
            Map<String, String> meals
          })>
      _healthByChild = const {};

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
      final health = await widget.service.fetchHealthCheckForOffice(widget.officeId, _businessDate);
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
          _healthByChild = health;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('健康チェック情報の取得に失敗しました');
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

  /// 対象日時点の月齢。ミルク=生後18ヶ月未満の絞り込みに使う(実月齢基準)。
  int? _ageMonths(String childId) {
    final b = _healthByChild[childId]?.birthDate;
    if (b == null) return null;
    var months = (_businessDate.year - b.year) * 12 + (_businessDate.month - b.month);
    if (_businessDate.day < b.day) months -= 1;
    return months;
  }

  /// クラスの年齢下限(age_groupの先頭の数字)。例: '0-1歳'→0, '2-3歳'→2, '3歳児'→3。数字なしはnull。
  /// 食事タブの対象判定は実年齢でなく「0・1・2歳児クラス」基準(俊指示 2026-08-14):
  /// 年度途中で3歳になった1・2歳児クラスの子も登録必須のため、クラスで判定する。
  int? _classMinAge(String className) {
    for (final c in _classes) {
      if (c.className == className) {
        final m = RegExp(r'\d+').firstMatch(c.ageGroup);
        return m == null ? null : int.parse(m.group(0)!);
      }
    }
    return null;
  }

  // ---------------- 検温 ----------------

  Future<void> _addTemperature(({String childId, String nameLabel, String className}) child) async {
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

  Future<void> _deleteTemperature(String childId, ChildTemperatureRecord rec) async {
    if (!await _confirm('${_hm(rec.measuredAt)} ${rec.temperature}℃ を削除しますか?')) return;
    try {
      await widget.service.deleteChildTemperature(childId, _businessDate, _hm(rec.measuredAt));
      await _reload();
    } catch (_) {
      _snack('削除に失敗しました(過去日は主任以上)');
    }
  }

  // ---------------- 排便 ----------------

  // 排便(排泄)記録の性状。連絡帳の排泄欄(admin_web TOILETING_TYPES)と同一。
  static const List<String> _toiletingTypes = ['普通', '軟便', '硬便', '下痢便'];

  Future<void> _addToileting(({String childId, String nameLabel, String className}) child) async {
    final t = await showTimeDropdownPicker(context: context, initialTime: TimeOfDay.now());
    if (t == null || !mounted) return;
    final type = await _pickChoice('便の性状', _toiletingTypes);
    if (type == null) return;
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    try {
      await widget.service.addToiletingRecord(child.childId, _businessDate, hhmm, type);
      await _reload();
    } catch (_) {
      _snack('記録に失敗しました(過去日・公開後は主任以上)');
    }
  }

  Future<void> _deleteToileting(String childId, int index, ({String time, String type}) rec) async {
    if (!await _confirm('${rec.time} ${rec.type} を削除しますか?')) return;
    try {
      await widget.service.deleteToiletingRecord(childId, _businessDate, index);
      await _reload();
    } catch (_) {
      _snack('削除に失敗しました(過去日・公開後は主任以上)');
    }
  }

  // ---------------- ミルク ----------------

  Future<void> _addMilk(({String childId, String nameLabel, String className}) child) async {
    final t = await showTimeDropdownPicker(context: context, initialTime: TimeOfDay.now());
    if (t == null || !mounted) return;
    final amount = await _pickMilkAmount();
    if (amount == null) return;
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    try {
      await widget.service.addMilkRecord(child.childId, _businessDate, hhmm, amount);
      await _reload();
    } catch (_) {
      _snack('記録に失敗しました(過去日・公開後は主任以上)');
    }
  }

  Future<int?> _pickMilkAmount() async {
    // 飲んだ量は 10〜300ml を 10ml 刻みのプルダウンで選択(サーバー上限は500)。
    final options = <int>[for (var v = 10; v <= 300; v += 10) v];
    int selected = 100;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('ミルクの量(ml)'),
          content: DropdownButton<int>(
            value: selected,
            isExpanded: true,
            items: [for (final v in options) DropdownMenuItem(value: v, child: Text('$v ml'))],
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

  Future<void> _deleteMilk(String childId, int index, ({String time, int amountMl}) rec) async {
    if (!await _confirm('${rec.time} ${rec.amountMl}ml を削除しますか?')) return;
    try {
      await widget.service.deleteMilkRecord(childId, _businessDate, index);
      await _reload();
    } catch (_) {
      _snack('削除に失敗しました(過去日・公開後は主任以上)');
    }
  }

  // ---------------- 食事(おやつ/昼食) ----------------

  // 食べた分量の選択肢(UI管理・DB非強制)。
  static const List<String> _mealAmounts = ['完食', 'ほとんど', '半分', '少量', '食べず'];

  Future<void> _setMeal(String childId, String slot, String? amount) async {
    try {
      await widget.service.setMealRecord(childId, _businessDate, slot, amount);
      await _reload();
    } catch (_) {
      _snack('記録に失敗しました(過去日・公開後は主任以上)');
    }
  }

  // ---------------- 共通 ----------------

  Future<String?> _pickChoice(String title, List<String> options) {
    String selected = options.first;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(title),
          content: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            items: [for (final t in options) DropdownMenuItem(value: t, child: Text(t))],
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

  /// タブごとの対象園児(年齢絞り込み)。birth_date 不明の児は安全側で表示する。
  List<({String childId, String nameLabel, String className})> _visibleRoster() {
    switch (_tab) {
      case 'milk':
        return _roster.where((c) {
          final m = _ageMonths(c.childId);
          return m == null || m < 18;
        }).toList();
      case 'am_snack':
      case 'lunch':
      case 'pm_snack':
        // 0・1・2歳児クラスの園児(クラス基準・実年齢は見ない)。判定不能クラスは安全側で表示。
        return _roster.where((c) {
          final minAge = _classMinAge(c.className);
          return minAge == null || minAge <= 2;
        }).toList();
      default:
        return _roster;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRoster();
    return Scaffold(
      appBar: AppBar(
        // 戻る(1つ前=デイリーボード等へ)+ ホーム(ロゴ)。デイリーボードから来ても戻れるように(俊指示 2026-08-21)。
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        toolbarHeight: 48,
        titleSpacing: 0,
        title: const Text('健康チェック', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [BusinessDateAction(date: _businessDate, onChanged: _onDateChanged)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
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
          // カテゴリ切替タブ(6タブ・横スクロール)。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final t in _healthTabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(t.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _tab == t.key ? Colors.white : AppColors.textPrimary,
                              )),
                          selected: _tab == t.key,
                          selectedColor: AppColors.skyBlue,
                          onSelected: (_) => setState(() => _tab = t.key),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? const Center(child: Text('対象の園児がいません'))
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(12),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, i) => _buildRow(rows[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// 園児1行。選択中タブに応じた記録列+追加操作を表示する。
  Widget _buildRow(({String childId, String nameLabel, String className}) child) {
    final Widget content;
    final Widget? action;
    switch (_tab) {
      case 'temp':
        final recs = _byChild[child.childId] ?? const [];
        content = Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final r in recs)
              Chip(
                label: Text('${_hm(r.measuredAt)} ${r.temperature}℃'),
                onDeleted: _canEdit ? () => _deleteTemperature(child.childId, r) : null,
                visualDensity: VisualDensity.compact,
              ),
            if (recs.isEmpty)
              const Text('検温 未記録', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        );
        action = _canEdit
            ? OutlinedButton.icon(
                onPressed: () => _addTemperature(child),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('検温'),
              )
            : null;
      case 'toileting':
        final recs = _healthByChild[child.childId]?.toileting ?? const [];
        content = Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final e in recs.asMap().entries)
              Chip(
                label: Text('${e.value.time} ${e.value.type}'),
                onDeleted: _canEdit ? () => _deleteToileting(child.childId, e.key, e.value) : null,
                visualDensity: VisualDensity.compact,
              ),
            if (recs.isEmpty)
              const Text('排便 未記録', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        );
        action = _canEdit
            ? OutlinedButton.icon(
                onPressed: () => _addToileting(child),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('排便'),
              )
            : null;
      case 'milk':
        final recs = _healthByChild[child.childId]?.milk ?? const [];
        content = Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final e in recs.asMap().entries)
              Chip(
                label: Text('${e.value.time} ${e.value.amountMl}ml'),
                onDeleted: _canEdit ? () => _deleteMilk(child.childId, e.key, e.value) : null,
                visualDensity: VisualDensity.compact,
              ),
            if (recs.isEmpty)
              const Text('ミルク 未記録', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        );
        action = _canEdit
            ? OutlinedButton.icon(
                onPressed: () => _addMilk(child),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('ミルク'),
              )
            : null;
      default: // am_snack / lunch / pm_snack
        final current = _healthByChild[child.childId]?.meals[_tab];
        content = Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final a in _mealAmounts)
              ChoiceChip(
                label: Text(a, style: TextStyle(fontSize: 12, color: current == a ? Colors.white : AppColors.textPrimary)),
                selected: current == a,
                selectedColor: AppColors.leafGreen,
                visualDensity: VisualDensity.compact,
                // 選択中を再タップで未記録に戻す(NULL)。
                onSelected: _canEdit ? (_) => _setMeal(child.childId, _tab, current == a ? null : a) : null,
              ),
          ],
        );
        action = null;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(child.nameLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(child.className, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Expanded(child: content),
            if (action != null) ...[const SizedBox(width: 8), action],
          ],
        ),
      ),
    );
  }
}
