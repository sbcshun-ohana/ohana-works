import 'package:flutter/material.dart';

import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import '../../../widgets/time_dropdown_picker.dart';
import 'child_internal_notes_tab.dart';
import '../family_daily_report_summary_view.dart';

/// 園児詳細画面。「家庭連絡帳」タブは常時表示、「園内記録」タブは
/// 機能フラグ child_internal_notes_enabled がONの施設のみ表示する。
class ChildDetailScreen extends StatefulWidget {
  const ChildDetailScreen({
    super.key,
    required this.service,
    required this.childId,
    required this.childName,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String childId;
  final String childName;
  final String officeId;
  final DateTime businessDate;

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  late Future<bool> _internalNotesEnabledFuture;

  @override
  void initState() {
    super.initState();
    _internalNotesEnabledFuture =
        widget.service.isChildInternalNotesEnabledForOffice(widget.officeId);
  }

  Future<void> _openWeeklySchedule() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WeeklyScheduleSheet(
        service: widget.service,
        childId: widget.childId,
        childName: widget.childName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _internalNotesEnabledFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(
              leading: const OhanaBackHomeLeading(),
              leadingWidth: 200,
              title: Text(widget.childName),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final internalNotesEnabled = snapshot.data ?? false;
        final tabs = <Tab>[
          const Tab(text: '家庭連絡帳'),
          if (internalNotesEnabled) const Tab(text: '園内記録'),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              leading: const OhanaBackHomeLeading(),
              leadingWidth: 200,
              title: Text(widget.childName),
              actions: [
                IconButton(
                  icon: const Icon(Icons.event_repeat_rounded),
                  tooltip: '週次保育時間(標準)',
                  onPressed: _openWeeklySchedule,
                ),
              ],
              bottom: tabs.length > 1 ? TabBar(tabs: tabs) : null,
            ),
            body: TabBarView(
              children: [
                _FamilyDailyReportTab(
                  service: widget.service,
                  childId: widget.childId,
                  businessDate: widget.businessDate,
                ),
                if (internalNotesEnabled)
                  ChildInternalNotesTab(
                    service: widget.service,
                    childId: widget.childId,
                    officeId: widget.officeId,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FamilyDailyReportTab extends StatefulWidget {
  const _FamilyDailyReportTab({
    required this.service,
    required this.childId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String childId;
  final DateTime businessDate;

  @override
  State<_FamilyDailyReportTab> createState() => _FamilyDailyReportTabState();
}

class _FamilyDailyReportTabState extends State<_FamilyDailyReportTab> {
  late Future<FamilyDailyReportSummary?> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture =
        widget.service.fetchFamilyDailyReportForStaff(widget.childId, widget.businessDate);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FamilyDailyReportSummary?>(
      future: _reportFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: FamilyDailyReportSummaryView(report: snapshot.data),
        );
      },
    );
  }
}

/// 週次標準保育時間(184)の編集。曜日=1:月..7:日。設定/削除は主任以上(サーバー側ゲート)。
/// 予定の既定値。日別の変更はデイリーボードの出欠モーダル(登降園予定override)で行う。
class _WeeklyScheduleSheet extends StatefulWidget {
  const _WeeklyScheduleSheet({required this.service, required this.childId, required this.childName});

  final ChildcareService service;
  final String childId;
  final String childName;

  @override
  State<_WeeklyScheduleSheet> createState() => _WeeklyScheduleSheetState();
}

class _WeeklyScheduleSheetState extends State<_WeeklyScheduleSheet> {
  // 運営日=月〜土のため、UIは月〜土の6曜日のみ扱う(DBは1:月..7:日のまま。日曜=7 は読み書き対象外)。
  static const _labels = {1: '月', 2: '火', 3: '水', 4: '木', 5: '金', 6: '土'};
  bool _loading = true;
  final Map<int, ({TimeOfDay? start, TimeOfDay? end})> _sched = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  static TimeOfDay? _fromDb(String? s) {
    if (s == null || s.length < 5) return null;
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final m = await widget.service.fetchChildWeeklySchedule(widget.childId);
      _sched.clear();
      for (var wd = 1; wd <= 6; wd++) {
        final e = m[wd];
        _sched[wd] = (start: _fromDb(e?.start), end: _fromDb(e?.end));
      }
    } catch (_) {
      for (var wd = 1; wd <= 6; wd++) {
        _sched[wd] = (start: null, end: null);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _save(int wd) async {
    final s = _sched[wd];
    if (s?.start == null || s?.end == null) {
      _snack('登園・降園の両方を設定してください');
      return;
    }
    try {
      await widget.service.setChildWeeklySchedule(widget.childId, wd, _hhmm(s!.start!), _hhmm(s.end!));
      _snack('${_labels[wd]}曜日を保存しました');
    } catch (_) {
      _snack('保存に失敗しました(設定は主任以上)');
    }
  }

  Future<void> _clear(int wd) async {
    try {
      await widget.service.deleteChildWeeklySchedule(widget.childId, wd);
      setState(() => _sched[wd] = (start: null, end: null));
      _snack('${_labels[wd]}曜日を「通わない」にしました');
    } catch (_) {
      _snack('操作に失敗しました(設定は主任以上)');
    }
  }

  Future<void> _pick(int wd, bool isStart) async {
    final cur = isStart ? _sched[wd]!.start : _sched[wd]!.end;
    final t = await showTimeDropdownPicker(context: context, initialTime: cur ?? const TimeOfDay(hour: 9, minute: 0));
    if (t == null) return;
    setState(() {
      final s = _sched[wd]!;
      _sched[wd] = isStart ? (start: t, end: s.end) : (start: s.start, end: t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: _loading
          ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${widget.childName} の週次保育時間(標準)', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  const Text('曜日ごとの標準の登降園予定。設定/削除は主任以上。日別の変更はデイリーボードの出欠編集で。',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 12),
                  for (var wd = 1; wd <= 6; wd++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(width: 28, child: Text(_labels[wd]!, style: const TextStyle(fontWeight: FontWeight.w700))),
                          OutlinedButton(
                            onPressed: () => _pick(wd, true),
                            child: Text(_sched[wd]!.start == null ? '登園' : _hhmm(_sched[wd]!.start!)),
                          ),
                          const Text(' 〜 '),
                          OutlinedButton(
                            onPressed: () => _pick(wd, false),
                            child: Text(_sched[wd]!.end == null ? '降園' : _hhmm(_sched[wd]!.end!)),
                          ),
                          const Spacer(),
                          TextButton(onPressed: () => _save(wd), child: const Text('保存')),
                          TextButton(onPressed: () => _clear(wd), child: const Text('通わない', style: TextStyle(color: Colors.redAccent))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
                  ),
                ],
              ),
            ),
    );
  }
}
