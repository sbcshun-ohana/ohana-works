import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// 指導計画・保育安全計画(287-297・iPad作成画面)。一般職員がiPadで作成する前提の、
/// タッチしやすく見やすいレイアウト。記入ヒント・例文ワンタップ挿入・自動保存・前回コピー・承認フロー・個人案。
class GuidancePlansScreen extends StatefulWidget {
  const GuidancePlansScreen({super.key, required this.service, required this.officeId, required this.isManager});
  final ChildcareService service;
  final String officeId;
  final bool isManager;

  @override
  State<GuidancePlansScreen> createState() => _GuidancePlansScreenState();
}

const _planTypes = [
  (value: 'overall', label: '全体的な計画', needsClass: false),
  (value: 'annual', label: '年間指導計画', needsClass: true),
  (value: 'monthly', label: '月案', needsClass: true),
  (value: 'weekly', label: '週案', needsClass: true),
  (value: 'safety', label: '保育安全計画', needsClass: false),
];
const _statusLabels = {
  'draft': '下書き',
  'submitted': '申請中',
  'chief_checked': '主任確認済',
  'approved': '承認済',
};
bool _isReflection(String sectionKey, String fieldKey) => sectionKey == 'reflection' || fieldKey == 'reflection';

class _GuidancePlansScreenState extends State<GuidancePlansScreen> {
  List<ChildcareClass> _classes = const [];
  final int _nowYear = DateTime.now().year;
  late int _fiscalYear = _nowYear;
  String _planType = 'monthly';
  String? _classId;
  int _month = DateTime.now().month;
  DateTime? _weekStart;
  List<Map<String, dynamic>> _plans = const [];
  String? _listTab; // 一覧のクラス別タブ選択(classId、または '__none__'=園全体)
  bool _showDashboard = true; // 管理者向け提出状況パネルの開閉
  List<Map<String, dynamic>> _tasks = const []; // 未完了タスク(主任以上・306)
  bool _canApproveOffice = false; // 承認可(統括園長・園長)。一括承認ボタン用(332/333)
  Map<String, dynamic>? _detail; // {plan, template, individual}
  List<Map<String, dynamic>> _targets = const [];
  bool _loading = true;
  bool _busy = false;
  String? _savedAt;
  Timer? _saveTimer;

  bool get _needsClass => _planTypes.firstWhere((p) => p.value == _planType).needsClass;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final classes = await widget.service.fetchChildcareClasses(widget.officeId);
      final plans = await widget.service.fetchGuidancePlansForOffice(widget.officeId, _fiscalYear);
      List<Map<String, dynamic>> tasks = const [];
      if (widget.isManager) {
        try {
          tasks = await widget.service.fetchGuidancePlanTasks(widget.officeId);
        } catch (_) {}
      }
      bool canApprove = false;
      try {
        canApprove = await widget.service.canApproveGuidancePlan(widget.officeId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _classes = classes;
        _plans = plans;
        _tasks = tasks;
        _canApproveOffice = canApprove;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openOrCreate() async {
    if (_needsClass && _classId == null) {
      _snack('クラスを選択してください');
      return;
    }
    if (_planType == 'weekly' && _weekStart == null) {
      _snack('週(月曜日)を選択してください');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await widget.service.ensureGuidancePlan(widget.officeId, _needsClass ? _classId : null, _planType, _fiscalYear,
          month: _planType == 'monthly' ? _month : null, weekStart: _planType == 'weekly' ? _weekStart : null);
      await _loadDetail(id);
      await _load();
    } catch (e) {
      _snack('開けません: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDetail(String id) async {
    final d = await widget.service.fetchGuidancePlan(id);
    (d['plan'] as Map)['content'] ??= <String, dynamic>{};
    (d['plan'] as Map)['evaluation'] ??= <String, dynamic>{};
    List<Map<String, dynamic>> targets = const [];
    if ((d['plan'] as Map)['plan_type'] == 'monthly') {
      try {
        targets = await widget.service.fetchGuidanceIndividualTargets(id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _detail = d;
      _targets = targets;
      _savedAt = null;
    });
  }

  Map<String, dynamic> get _plan => (_detail!['plan'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _content => (_plan['content'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _evaluation => (_plan['evaluation'] as Map).cast<String, dynamic>();

  void _setField(String sectionKey, String key, String value) {
    setState(() {
      if (_isReflection(sectionKey, key)) {
        _evaluation[key] = value;
      } else {
        _content[key] = value;
      }
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1200), () async {
      if (_detail == null) return;
      final id = _plan['id'] as String;
      try {
        if (_plan['status'] != 'approved') await widget.service.saveGuidancePlanContent(id, _content);
        await widget.service.saveGuidancePlanEvaluation(id, _evaluation);
        if (mounted) {
          final n = TimeOfDay.now();
          setState(() => _savedAt = '保存しました ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}');
        }
      } catch (_) {}
    });
  }

  Future<void> _runAction(Future<void> Function() fn, String ok) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (mounted) _snack(ok);
      await _loadDetail(_plan['id'] as String);
      await _load();
    } catch (e) {
      _snack('操作できません: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final inEditor = _detail != null;
    return Scaffold(
      appBar: AppBar(
        // 編集(作成)画面では ← で一覧へ一段戻す。一覧ではホームへ戻る(ロゴ+戻る)。
        leading: inEditor
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '一覧へ戻る',
                onPressed: () => setState(() => _detail = null),
              )
            : const OhanaBackHomeLeading(),
        leadingWidth: inEditor ? null : 200,
        title: const Text('指導計画・保育安全計画'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail != null
              ? _editor()
              : _listView(),
    );
  }

  // 一覧のクラス別タブ構成: クラス各組 + 園全体(全体的な計画・保育安全計画=クラスなし)。
  List<({String id, String label})> get _listTabs => [
        for (final c in _classes) (id: c.classId, label: c.className),
        (id: '__none__', label: '園全体'),
      ];

  Widget _listView() {
    final tabs = _listTabs;
    if (tabs.isNotEmpty && (_listTab == null || !tabs.any((t) => t.id == _listTab))) {
      _listTab = tabs.first.id;
    }
    // 選択タブのクラスに属する計画を、種別ごとにグルーピング(_planTypes の並び順)。
    final inTab = _plans.where((p) => (p['class_id'] as String? ?? '__none__') == _listTab).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _selectorCard(),
        if (widget.isManager && _tasks.isNotEmpty) ...[
          const SizedBox(height: 16),
          _taskAlertPanel(),
        ],
        if (widget.isManager) ...[
          const SizedBox(height: 16),
          _dashboardPanel(),
        ],
        if (_canApproveOffice && _pendingApprovalCount > 0) ...[
          const SizedBox(height: 16),
          _bulkApproveBar(),
        ],
        const SizedBox(height: 16),
        const Text('作成済みの計画', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        _classTabBar(tabs),
        const SizedBox(height: 12),
        if (inTab.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('このクラスの計画はまだありません', style: TextStyle(color: AppColors.textSecondary)))
        else
          for (final pt in _planTypes)
            if (inTab.any((p) => p['plan_type'] == pt.value)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Text(pt.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.skyBlue)),
              ),
              ...inTab.where((p) => p['plan_type'] == pt.value).map(_planTile),
              const SizedBox(height: 10),
            ],
      ],
    );
  }

  // 承認待ち件数(認可=主任確認済 / 企業主導型=申請済 の両方を「承認待ち」として数える)。
  int get _pendingApprovalCount =>
      _plans.where((p) => p['status'] == 'submitted' || p['status'] == 'chief_checked').length;

  // 一括承認バー(333)。承認可(統括園長・園長)で承認待ちがあるとき表示。
  Widget _bulkApproveBar() => Card(
        color: AppColors.leafGreen.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Text('承認待ちの指導計画が $_pendingApprovalCount 件あります',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              FilledButton(
                onPressed: _busy ? null : _bulkApprove,
                style: FilledButton.styleFrom(backgroundColor: AppColors.leafGreen),
                child: const Text('一括承認'),
              ),
            ],
          ),
        ),
      );

  Future<void> _bulkApprove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('一括承認'),
        content: Text('$_fiscalYear年度の承認待ちの指導計画をまとめて承認します。よろしいですか?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('承認する')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = await widget.service.bulkApproveGuidancePlans(widget.officeId, _fiscalYear);
      if (!mounted) return;
      _snack('$n件を承認しました');
      await _load();
    } catch (e) {
      if (mounted) _snack('承認できませんでした: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ===== 提出状況ダッシュボード(管理者向け) =====
  // クラス×[年間指導計画 / 今月の月案] の状態を一覧。未作成はその場で作成。園全体は全体的な計画/保育安全計画。
  Map<String, dynamic>? _planFor(String? classId, String type, {int? month}) {
    for (final p in _plans) {
      if (p['plan_type'] != type) continue;
      if ((p['class_id'] as String?) != classId) continue;
      if (month != null && p['month'] != month) continue;
      return p;
    }
    return null;
  }

  // 未完了タスクのアラート(主任以上・306)。未提出=赤(action)/承認待ち=青(info)。
  Widget _taskAlertPanel() {
    final action = _tasks.where((t) => t['level'] == 'action').toList();
    final info = _tasks.where((t) => t['level'] == 'info').toList();
    Widget line(Map<String, dynamic> t) {
      final isAction = t['level'] == 'action';
      final color = isAction ? AppColors.punchClockOut : AppColors.skyBlue;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(isAction ? Icons.error_outline : Icons.info_outline, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(t['message'] as String? ?? '', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600))),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (action.isNotEmpty ? AppColors.punchClockOut : AppColors.skyBlue).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (action.isNotEmpty ? AppColors.punchClockOut : AppColors.skyBlue).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_late_outlined, size: 20, color: action.isNotEmpty ? AppColors.punchClockOut : AppColors.skyBlue),
              const SizedBox(width: 8),
              Text('未完了タスク(${_tasks.length}件)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 8),
          ...action.map(line),
          ...info.map(line),
        ],
      ),
    );
  }

  Widget _dashboardPanel() {
    // 「月案」列は上部プルダウンで選択中の月(_month)に連動させる(俊指示 2026-08-24)。
    final selMonth = _month;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _showDashboard = !_showDashboard),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, size: 20, color: AppColors.skyBlue),
                    const SizedBox(width: 8),
                    Text('提出状況($_fiscalYear年度)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const Spacer(),
                    Icon(_showDashboard ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            if (_showDashboard) ...[
              // 見出し行
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: Text('クラス', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                    const Expanded(flex: 3, child: Text('年間指導計画', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                    Expanded(flex: 3, child: Text('$selMonth月の月案', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                  ],
                ),
              ),
              for (final c in _classes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(c.className, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                      Expanded(flex: 3, child: _statusCell(_planFor(c.classId, 'annual'), c.classId, 'annual', null)),
                      Expanded(flex: 3, child: _statusCell(_planFor(c.classId, 'monthly', month: selMonth), c.classId, 'monthly', selMonth)),
                    ],
                  ),
                ),
              const Divider(height: 16),
              Row(
                children: [
                  const Expanded(flex: 3, child: Text('園全体', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                  Expanded(flex: 3, child: _statusCell(_planFor(null, 'overall'), null, 'overall', null, label: '全体的な計画')),
                  Expanded(flex: 3, child: _statusCell(_planFor(null, 'safety'), null, 'safety', null, label: '保育安全計画')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusCell(Map<String, dynamic>? plan, String? classId, String type, int? month, {String? label}) {
    final status = plan?['status'] as String?;
    final (color, text) = switch (status) {
      'approved' => (AppColors.leafGreen, '承認済'),
      'chief_checked' => (AppColors.skyBlue, '主任確認'),
      'submitted' => (AppColors.skyBlue, '申請中'),
      'draft' => (AppColors.warmOrange, '下書き'),
      _ => (AppColors.textSecondary, '未作成'),
    };
    final display = label != null && status == null ? '＋ $label' : (label != null ? '$label:$text' : text);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _busy
            ? null
            : () {
                if (plan != null) {
                  _loadDetail(plan['id'] as String);
                } else {
                  _quickCreate(classId, type, month);
                }
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(display, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Future<void> _quickCreate(String? classId, String type, int? month) async {
    setState(() {
      _planType = type;
      _classId = classId;
      if (month != null) _month = month;
    });
    await _openOrCreate();
  }

  Widget _classTabBar(List<({String id, String label})> tabs) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  selected: _listTab == t.id,
                  onSelected: (_) => setState(() => _listTab = t.id),
                  selectedColor: AppColors.skyBlue.withValues(alpha: 0.18),
                  labelStyle: TextStyle(color: _listTab == t.id ? AppColors.skyBlue : AppColors.textSecondary),
                  showCheckmark: false,
                ),
              ),
          ],
        ),
      );

  Widget _selectorCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _dropdown<int>('年度', _fiscalYear, [
                    for (final y in [_nowYear - 1, _nowYear, _nowYear + 1]) DropdownMenuItem(value: y, child: Text('$y年度')),
                  ], (v) => setState(() => _fiscalYear = v!), onChangedExtra: _load),
                  _dropdown<String>('計画種別', _planType, [
                    for (final p in _planTypes) DropdownMenuItem(value: p.value, child: Text(p.label)),
                  ], (v) => setState(() => _planType = v!)),
                  if (_needsClass)
                    _dropdown<String?>('クラス', _classId, [
                      const DropdownMenuItem(value: null, child: Text('選択')),
                      for (final c in _classes) DropdownMenuItem(value: c.classId, child: Text(c.className)),
                    ], (v) => setState(() => _classId = v)),
                  if (_planType == 'monthly')
                    _dropdown<int>('月', _month, [
                      for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text('$m月')),
                    ], (v) => setState(() => _month = v!)),
                  if (_planType == 'weekly')
                    _weekPicker(),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _openOrCreate,
                  icon: const Icon(Icons.edit_document),
                  label: const Text('開く / 作成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _weekPicker() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('週(月曜)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, initialDate: _weekStart ?? now,
                  firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1));
              if (d != null) setState(() => _weekStart = d.subtract(Duration(days: (d.weekday - 1))));
            },
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(_weekStart != null ? '${_weekStart!.month}/${_weekStart!.day}〜' : '選択'),
          ),
        ],
      );

  Widget _dropdown<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged,
      {VoidCallback? onChangedExtra}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        DropdownButton<T>(
          value: value,
          items: items,
          onChanged: (v) {
            onChanged(v);
            onChangedExtra?.call();
          },
        ),
      ],
    );
  }

  Widget _planTile(Map<String, dynamic> p) {
    final type = _planTypes.where((x) => x.value == p['plan_type']).map((x) => x.label).firstOrNull ?? p['plan_type'];
    // 種別ごとにグルーピング済みなので、タイトルは期間を主に。期間の無い種別(年間/全体/安全)は種別名を表示。
    final title = p['month'] != null
        ? '${p['month']}月'
        : p['week_start_date'] != null
            ? '${p['week_start_date']}〜'
            : '$type';
    final status = p['status'] as String? ?? 'draft';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_statusLabels[status] ?? status),
        trailing: FilledButton(onPressed: () => _loadDetail(p['id'] as String), child: const Text('開く')),
      ),
    );
  }

  // エディタの題名。テンプレ名(「年間指導計画(1〜4歳児)」等の年齢表記)ではなく、
  // クラス名+種別で表示する(俊指示 2026-08-25・iPadで見やすく)。園全体の種別(全体的な計画/
  // 保育安全計画)はクラスが無いので種別名のみ。月案/週案は期間も付す。
  String _planTitle() {
    final planType = _plan['plan_type'] as String?;
    final typeLabel = _planTypes.where((x) => x.value == planType).map((x) => x.label).firstOrNull ?? (planType ?? '');
    final classId = _plan['class_id'] as String?;
    final className = classId == null
        ? null
        : _classes.where((c) => c.classId == classId).map((c) => c.className).firstOrNull;
    final month = _plan['month'];
    final weekStart = _plan['week_start_date'] as String?;
    if (className == null) return typeLabel; // 全体的な計画 / 保育安全計画
    if (planType == 'monthly' && month != null) return '$className $month月の$typeLabel';
    if (planType == 'weekly' && weekStart != null) return '$className $typeLabel($weekStart〜)';
    return '$className $typeLabel'; // 例: つき組 年間指導計画
  }

  // ===== エディタ =====
  Widget _editor() {
    final t = (_detail!['template'] as Map).cast<String, dynamic>();
    final sections = (t['sections'] as List).cast<dynamic>();
    final status = _plan['status'] as String? ?? 'draft';
    final approved = status == 'approved';
    return Column(
      children: [
        _editorBar(_planTitle(), status),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if ((_plan['rejected_reason'] as String?)?.isNotEmpty ?? false)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.punchClockOut.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                  child: Text('差し戻し/取消理由: ${_plan['rejected_reason']}', style: const TextStyle(color: AppColors.punchClockOut)),
                ),
              if (approved)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.leafGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Text('承認済みです。本文は編集できません(評価・反省欄は記入可能)。', style: TextStyle(fontSize: 12)),
                ),
              for (final s in sections) _section((s as Map).cast<String, dynamic>(), approved),
              if (_targets.isNotEmpty) _individualSection(approved),
              const SizedBox(height: 16),
              _workflowButtons(status),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editorBar(String title, String status) => Material(
        color: AppColors.skyBlue.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text('$title  (${_statusLabels[status] ?? status})',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              if (_savedAt != null) Padding(padding: const EdgeInsets.only(right: 12), child: Text(_savedAt!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              // AI下書き: 月案・週案・未承認時のみ。連絡帳等を素材に各欄の下書きを生成→確認して採用。
              if (status != 'approved' && (_plan['plan_type'] == 'monthly' || _plan['plan_type'] == 'weekly'))
                TextButton.icon(
                  onPressed: _busy ? null : _generateAiDraft,
                  icon: const Icon(Icons.auto_awesome, size: 18, color: Colors.purple),
                  label: const Text('AIで下書き', style: TextStyle(color: Colors.purple)),
                ),
              if (status != 'approved')
                TextButton(
                  onPressed: _busy ? null : () async {
                    final ok = await _confirm('前回(前月/前週/前年度)の内容をコピーします。現在の入力は上書きされます。よろしいですか?');
                    if (ok) _runAction(() => widget.service.copyPreviousGuidancePlan(_plan['id'] as String), '前回の内容をコピーしました');
                  },
                  child: const Text('前回コピー'),
                ),
              TextButton(onPressed: () => setState(() { _detail = null; }), child: const Text('閉じる')),
            ],
          ),
        ),
      );

  Widget _section(Map<String, dynamic> sec, bool approved) {
    final sectionKey = sec['key'] as String;
    final fields = (sec['fields'] as List).cast<dynamic>();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3E0)), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sec['label'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if ((sec['hint'] as String?)?.isNotEmpty ?? false)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text('💡 ${sec['hint']}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          const SizedBox(height: 10),
          for (final f in fields) _field(sectionKey, (f as Map).cast<String, dynamic>(), approved),
        ],
      ),
    );
  }

  Widget _field(String sectionKey, Map<String, dynamic> f, bool approved) {
    final key = f['key'] as String;
    final refl = _isReflection(sectionKey, key);
    final editable = refl || !approved;
    final value = (refl ? _evaluation[key] : _content[key]) as String? ?? '';
    final examples = ((f['examples'] as List?) ?? const []).map((e) => e.toString()).toList();
    final ctrl = TextEditingController(text: value);
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(f['label'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (f['required'] == true) const Text(' *', style: TextStyle(color: AppColors.punchClockOut)),
              if ((f['subject'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFDDE3E0), borderRadius: BorderRadius.circular(4)),
                  child: Text('${f['subject']}が主語', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ),
              ],
            ],
          ),
          if ((f['hint'] as String?)?.isNotEmpty ?? false)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text('💡 ${f['hint']}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            enabled: editable,
            maxLines: null,
            minLines: 2,
            keyboardType: TextInputType.multiline,
            onChanged: (v) => _setField(sectionKey, key, v),
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(10)),
          ),
          if (editable && examples.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('例文:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  for (final ex in examples)
                    ActionChip(
                      label: Text(ex.length > 22 ? '${ex.substring(0, 22)}…' : ex, style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.add, size: 16, color: AppColors.leafGreen),
                      onPressed: () {
                        final cur = (refl ? _evaluation[key] : _content[key]) as String? ?? '';
                        _setField(sectionKey, key, cur.trim().isEmpty ? '・$ex' : '$cur\n・$ex');
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _individualSection(bool approved) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.04),
          border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('個人案(このクラスの対象児)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.purple)),
            const SizedBox(height: 8),
            for (final c in _targets) _individualRow(c, approved),
          ],
        ),
      );

  Widget _individualRow(Map<String, dynamic> c, bool approved) {
    final childId = c['child_id'] as String;
    final existing = ((_detail!['individual'] as List).cast<dynamic>())
        .cast<Map>()
        .firstWhere((e) => e['child_id'] == childId, orElse: () => {'content': <String, dynamic>{}});
    final content = ((existing['content'] as Map?) ?? {}).cast<String, dynamic>();
    return _IndividualCard(
      key: ValueKey(childId),
      childName: c['display_name'] as String? ?? '',
      initial: content,
      disabled: approved,
      onSave: (m) async {
        try {
          await widget.service.upsertGuidancePlanIndividual(_plan['id'] as String, childId, m);
          if (mounted) setState(() => _savedAt = '個人案を保存しました');
        } catch (_) {}
      },
    );
  }

  // ワークフロー(332): 申請=全職員 / 主任確認=認可のみ主任以上 / 承認=統括園長・園長(can_approve)。
  Widget _workflowButtons(String status) {
    final btns = <Widget>[];
    final isCorporate = _plan['office_category'] == 'corporate_led';
    final canApprove = _plan['can_approve'] == true;
    OutlinedButton reject() => OutlinedButton(onPressed: _busy ? null : _reject, style: OutlinedButton.styleFrom(foregroundColor: AppColors.punchClockOut), child: const Text('差し戻し'));
    FilledButton approve() => FilledButton(onPressed: _busy ? null : () => _runAction(() => widget.service.approveGuidancePlan(_plan['id'] as String), '承認しました'), child: const Text('承認'));
    if (status == 'draft') {
      btns.add(FilledButton(onPressed: _busy ? null : () => _runAction(() => widget.service.submitGuidancePlan(_plan['id'] as String), '申請しました'), child: const Text('申請する')));
    } else if (status == 'submitted') {
      if (widget.isManager) btns.add(reject());
      // 認可のみ主任確認
      if (!isCorporate && widget.isManager) {
        btns.add(OutlinedButton(onPressed: _busy ? null : () => _runAction(() => widget.service.chiefCheckGuidancePlan(_plan['id'] as String), '主任確認しました'), child: const Text('主任確認')));
      }
      // 企業主導型は申請→承認
      if (isCorporate && canApprove) btns.add(approve());
    } else if (status == 'chief_checked' && canApprove) {
      btns.add(reject());
      btns.add(approve());
    }
    if (btns.isEmpty) return const SizedBox.shrink();
    return Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: btns);
  }

  // ===== AI下書き =====
  // テンプレから fieldKey → {sectionKey, sectionLabel, fieldLabel} の対応表を作る(プレビュー表示・差し込み用)。
  Map<String, ({String sectionKey, String label})> _fieldLookup() {
    final out = <String, ({String sectionKey, String label})>{};
    final t = (_detail!['template'] as Map).cast<String, dynamic>();
    for (final s in (t['sections'] as List).cast<dynamic>()) {
      final sec = (s as Map).cast<String, dynamic>();
      final sKey = sec['key'] as String? ?? '';
      final sLabel = sec['label'] as String? ?? '';
      for (final f in (sec['fields'] as List).cast<dynamic>()) {
        final fld = (f as Map).cast<String, dynamic>();
        final fKey = fld['key'] as String? ?? '';
        final fLabel = fld['label'] as String? ?? '';
        if (fKey.isEmpty) continue;
        out[fKey] = (sectionKey: sKey, label: sLabel == fLabel || fLabel.isEmpty ? sLabel : '$sLabel / $fLabel');
      }
    }
    return out;
  }

  Future<void> _generateAiDraft() async {
    setState(() => _busy = true);
    try {
      final res = await widget.service.generateGuidanceDraft(_plan['id'] as String);
      final sections = ((res['sections'] as Map?) ?? {}).cast<String, dynamic>();
      final mock = res['mock'] == true;
      final counts = ((res['source_counts'] as Map?) ?? {}).cast<String, dynamic>();
      if (!mounted) return;
      if (sections.isEmpty) {
        _snack('生成できる下書きがありませんでした');
        return;
      }
      await _showAiPreview(sections, mock, counts);
    } catch (e) {
      _snack('AI生成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAiPreview(Map<String, dynamic> sections, bool mock, Map<String, dynamic> counts) async {
    final lookup = _fieldLookup();
    // テンプレに存在する欄のみ、テンプレ順で並べる。
    final ordered = lookup.keys.where((k) => sections.containsKey(k)).toList();
    final selected = <String>{...ordered}; // 既定=全選択
    final applied = <String>{};
    void applySelected(bool append) {
      for (final key in ordered) {
        if (!selected.contains(key)) continue;
        final add = sections[key] as String? ?? '';
        if (append) {
          final cur = (_content[key] as String?) ?? '';
          _setField(lookup[key]!.sectionKey, key, cur.trim().isEmpty ? add : '$cur\n$add');
        } else {
          _setField(lookup[key]!.sectionKey, key, add);
        }
        applied.add(key);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx, scroll) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('AI下書きの確認', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                    Text('連絡帳${counts['contacts'] ?? 0}・活動${counts['activities'] ?? 0}・家庭${counts['home'] ?? 0}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (mock)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.warmOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Text('※ サンプル下書きです(AIキー未設定)。キー設定後に実際の記録から生成されます。', style: TextStyle(fontSize: 12)),
                ),
              // 全選択/全解除
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('採用する欄にチェックを入れ、下の「選択を採用/追記」でまとめて反映できます。',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                    TextButton(
                      onPressed: () => setSheet(() {
                        if (selected.length == ordered.length) {
                          selected.clear();
                        } else {
                          selected
                            ..clear()
                            ..addAll(ordered);
                        }
                      }),
                      child: Text(selected.length == ordered.length ? '全解除' : '全選択'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    for (final key in ordered)
                      _aiPreviewCard(
                        label: lookup[key]!.label,
                        current: (_content[key] as String?) ?? '',
                        proposal: sections[key] as String? ?? '',
                        applied: applied.contains(key),
                        checked: selected.contains(key),
                        onToggle: () => setSheet(() => selected.contains(key) ? selected.remove(key) : selected.add(key)),
                      ),
                  ],
                ),
              ),
              // 一括アクションバー
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFDDE3E0)))),
                  child: Row(
                    children: [
                      Text('${selected.length}件選択', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: selected.isEmpty ? null : () => setSheet(() => applySelected(true)),
                        icon: const Icon(Icons.playlist_add, size: 18),
                        label: const Text('選択を追記'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: selected.isEmpty ? null : () => setSheet(() => applySelected(false)),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('選択を採用(置換)'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aiPreviewCard({
    required String label,
    required String current,
    required String proposal,
    required bool applied,
    required bool checked,
    required VoidCallback onToggle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: applied ? AppColors.leafGreen : (checked ? Colors.purple.withValues(alpha: 0.4) : const Color(0xFFDDE3E0))),
        borderRadius: BorderRadius.circular(12),
        color: applied ? AppColors.leafGreen.withValues(alpha: 0.06) : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Icon(checked ? Icons.check_box : Icons.check_box_outline_blank,
                    color: checked ? Colors.purple : AppColors.textSecondary, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                if (applied) const Text('反映済', style: TextStyle(fontSize: 12, color: AppColors.leafGreen, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (current.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text('現在の入力', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            Text(current, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 6),
          const Text('AI提案', style: TextStyle(fontSize: 11, color: Colors.purple)),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
            child: Text(proposal, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Future<void> _reject() async {
    final reason = await _promptText('差し戻し理由(必須)');
    if (reason == null || reason.trim().isEmpty) return;
    _runAction(() => widget.service.rejectGuidancePlan(_plan['id'] as String, reason.trim()), '差し戻しました');
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _promptText(String title) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('決定')),
        ],
      ),
    );
  }
}

class _IndividualCard extends StatefulWidget {
  const _IndividualCard({super.key, required this.childName, required this.initial, required this.disabled, required this.onSave});
  final String childName;
  final Map<String, dynamic> initial;
  final bool disabled;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_IndividualCard> createState() => _IndividualCardState();
}

class _IndividualCardState extends State<_IndividualCard> {
  static const _fields = [
    (key: 'kidsstate', label: '子どもの姿'),
    (key: 'aim', label: 'ねらい'),
    (key: 'consideration', label: '配慮・環境構成'),
    (key: 'reflection', label: '評価・反省'),
  ];
  late final Map<String, dynamic> _c = Map<String, dynamic>.from(widget.initial);
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _set(String k, String v) {
    _c[k] = v;
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1200), () => widget.onSave(_c));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.childName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          for (final f in _fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  TextField(
                    controller: TextEditingController(text: _c[f.key] as String? ?? '')
                      ..selection = TextSelection.collapsed(offset: (_c[f.key] as String? ?? '').length),
                    enabled: !widget.disabled,
                    maxLines: null,
                    minLines: 1,
                    onChanged: (v) => _set(f.key, v),
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(8)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
