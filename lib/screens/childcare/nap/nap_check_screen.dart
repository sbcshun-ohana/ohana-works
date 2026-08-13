import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../models/nap.dart';
import '../../../services/childcare_service.dart';
import '../../../widgets/now_clock.dart';
import '../../../widgets/time_dropdown_picker.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// Phase 3 §3: 午睡チェック(iPad)。園児は常時一覧・操作は行内ボタン・時間軸は全園児共通。
/// 5分グリッドで身体の向き(4種)+呼吸/顔色/寝具の確認を記録。
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

/// 在籍名簿×午睡セッションのマージ行。セッションが無くても在籍児は行として表示する。
class _RosterRow {
  _RosterRow({
    required this.childId,
    required this.nameLabel,
    required this.className,
    required this.sessionId,
    required this.intervals,
    required this.checks,
  });

  final String childId;
  final String nameLabel;
  final String className;
  final String? sessionId; // null=セッション未生成
  final List<NapInterval> intervals; // sleep_start_at 昇順
  final List<NapCheck> checks;

  bool get notSlept => intervals.isEmpty;
  bool get isSleeping => intervals.any((i) => i.wakeUpAt == null);
  bool get isAllWoken => intervals.isNotEmpty && intervals.every((i) => i.wakeUpAt != null);
  NapInterval? get openInterval {
    NapInterval? open;
    for (final i in intervals) {
      if (i.wakeUpAt == null) open = i; // 昇順なので最後の未起床が最新
    }
    return open;
  }

  NapCheck? checkAt(DateTime slot) {
    for (final c in checks) {
      if (c.slotAt.isAtSameMomentAs(slot)) return c;
    }
    return null;
  }
}

class _NapCheckScreenState extends State<NapCheckScreen> {
  late DateTime _businessDate = widget.businessDate;
  int _selectedHour = DateTime.now().hour; // 表示中の時間帯(コドモン準拠の1時間グリッド)
  List<ChildcareClass> _classes = const [];
  String? _selectedClassId;
  bool _loading = true;
  List<NapSessionRow> _board = const [];
  List<({String childId, String nameLabel, String className})> _roster = const [];

  static const double _nameColWidth = 176;
  static const double _cellWidth = 46;

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

  void _onDateChanged(DateTime d) {
    setState(() => _businessDate = d);
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final board = await widget.service.fetchNapBoard(widget.officeId, _businessDate, classId: _selectedClassId);
      final List<({String childId, String nameLabel, String className})> roster;
      if (_selectedClassId != null) {
        final className = _classes.firstWhere(
          (c) => c.classId == _selectedClassId,
          orElse: () => const ChildcareClass(classId: '', className: '', ageGroup: '', schoolYear: 0),
        ).className;
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
      if (mounted) {
        setState(() {
          _board = board;
          _roster = roster;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('午睡情報の取得に失敗しました');
      }
    }
  }

  // 名簿×セッションのマージ。区間は sleep_start_at 昇順。名簿に無いがセッションを持つ児は末尾に補完。
  List<_RosterRow> _displayRows() {
    final byChild = {for (final r in _board) r.childId: r};
    List<NapInterval> sortIv(List<NapInterval> ivs) {
      final list = [...ivs]..sort((a, b) => a.sleepStartAt.compareTo(b.sleepStartAt));
      return list;
    }

    final rows = <_RosterRow>[];
    for (final c in _roster) {
      final b = byChild[c.childId];
      rows.add(_RosterRow(
        childId: c.childId,
        nameLabel: c.nameLabel,
        className: c.className,
        sessionId: b?.sessionId,
        intervals: b != null ? sortIv(b.intervals) : const [],
        checks: b?.checks ?? const [],
      ));
    }
    final rosterIds = {for (final c in _roster) c.childId};
    for (final b in _board) {
      if (!rosterIds.contains(b.childId)) {
        rows.add(_RosterRow(
          childId: b.childId,
          nameLabel: b.nameLabel,
          className: b.className,
          sessionId: b.sessionId,
          intervals: sortIv(b.intervals),
          checks: b.checks,
        ));
      }
    }
    return rows;
  }

  DateTime _combine(TimeOfDay t) => DateTime(
        _businessDate.year,
        _businessDate.month,
        _businessDate.day,
        t.hour,
        t.minute,
      );

  // ピッカー確定値の検証: 未来不可(+2分の猶予)、after 指定時はそれ以降のみ。無効は null を返しスナック表示。
  DateTime? _validated(TimeOfDay t, {DateTime? after, String afterLabel = '入眠'}) {
    final dt = _combine(t);
    final now = DateTime.now();
    if (dt.isAfter(now.add(const Duration(minutes: 2)))) {
      _snack('未来の時刻は指定できません');
      return null;
    }
    if (after != null && !dt.isAfter(after)) {
      _snack('$afterLabelより後の時刻を指定してください');
      return null;
    }
    return dt;
  }

  // 選択中の時間帯(1時間)の5分スロット12本(HH:00〜HH:55 JST)を UTC 実体で返す。
  List<DateTime> _hourSlots(int hour) {
    return List.generate(
      12,
      (i) => DateTime(_businessDate.year, _businessDate.month, _businessDate.day, hour, i * 5).toUtc(),
    );
  }

  // slot時点で就寝中か(いずれかの区間 [入眠,起床) に入る)。
  bool _isSleepingAt(_RosterRow r, DateTime slotUtc) {
    for (final iv in r.intervals) {
      final s = iv.sleepStartAt.toUtc();
      final w = iv.wakeUpAt?.toUtc();
      if (!slotUtc.isBefore(s) && (w == null || slotUtc.isBefore(w))) return true;
    }
    return false;
  }

  // slotより前で最も新しいチェック(列一括の「各児の直前チェック」)。
  NapCheck? _priorCheck(_RosterRow r, DateTime slotUtc) {
    NapCheck? best;
    for (final c in r.checks) {
      if (c.slotAt.toUtc().isBefore(slotUtc)) {
        if (best == null || c.slotAt.isAfter(best.slotAt)) best = c;
      }
    }
    return best;
  }

  // セルの編集可否(サーバー側 nap_check_authz を UI で先取り。サーバー側ゲートは現状維持)。
  // 未来=不可 / 主任=窓外も可・過去日可 / 一般当日: 未記入=その5分間のみ・記録済=30分以内 / 過去日=不可。
  bool _cellCanEdit(DateTime slotUtc, bool hasCheck) {
    final now = DateTime.now();
    if (now.isBefore(slotUtc)) return false;
    if (widget.isManager) return true;
    final isPastDay = DateTime(_businessDate.year, _businessDate.month, _businessDate.day)
        .isBefore(DateTime(now.year, now.month, now.day));
    if (isPastDay) return false;
    if (hasCheck) return now.difference(slotUtc).inSeconds / 60.0 <= 30;
    return now.isBefore(slotUtc.add(const Duration(minutes: 5))); // その5分間(now>=slot は上で保証)
  }

  bool _columnBulkEnabled(DateTime slotUtc) {
    final now = DateTime.now();
    if (now.isBefore(slotUtc)) return false;
    if (widget.isManager) return true;
    final isPastDay = DateTime(_businessDate.year, _businessDate.month, _businessDate.day)
        .isBefore(DateTime(now.year, now.month, now.day));
    if (isPastDay) return false;
    return now.isBefore(slotUtc.add(const Duration(minutes: 5)));
  }

  // ---- 行内操作 ----------------------------------------------------------

  Future<void> _sleep(_RosterRow r) async {
    final t = await showTimeDropdownPicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    final dt = _validated(t);
    if (dt == null) return;
    await _guard(() => widget.service.startNapSession(r.childId, dt));
  }

  Future<void> _wake(_RosterRow r) async {
    final open = r.openInterval;
    if (open == null || r.sessionId == null) return;
    final t = await showTimeDropdownPicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    final dt = _validated(t, after: open.sleepStartAt, afterLabel: '入眠');
    if (dt == null) return;
    await _guard(() => widget.service.endNapSession(r.sessionId!, dt));
  }

  Future<void> _reSleep(_RosterRow r) async {
    final lastWake = r.intervals.isNotEmpty ? r.intervals.last.wakeUpAt : null;
    final t = await showTimeDropdownPicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    final dt = _validated(t, after: lastWake, afterLabel: '前回起床');
    if (dt == null) return;
    await _guard(() => widget.service.startNapSession(r.childId, dt));
  }

  // ---- 一括操作(K3: 対象+件数を明示。0件は理由まで) --------------------

  String get _selectedClassName =>
      _classes.firstWhere((c) => c.classId == _selectedClassId, orElse: () => const ChildcareClass(classId: '', className: 'クラス', ageGroup: '', schoolYear: 0)).className;

  // 入眠(一括)= 未入眠(区間なし)の在籍児のみ入眠。就寝中/起床済みには追加しない(二重就寝中を防止)。
  Future<void> _classBulkStart() async {
    if (_selectedClassId == null) {
      _snack('クラスを選択してください');
      return;
    }
    final t = await showTimeDropdownPicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    final dt = _validated(t);
    if (dt == null) return;
    final targets = _displayRows().where((r) => r.notSlept).toList();
    if (targets.isEmpty) {
      _snack('入眠の対象がありません(全員すでに入眠/起床済みです)');
      return;
    }
    await _guard(() async {
      for (final r in targets) {
        await widget.service.startNapSession(r.childId, dt);
      }
      _snack('$_selectedClassName ${targets.length}名を入眠にしました');
    });
  }

  // 起床(一括)= 就寝中の児の開区間を現在時刻でまとめて閉じる(RPCが未起床区間のみ対象)。
  Future<void> _classBulkEnd() async {
    if (_selectedClassId == null) {
      _snack('クラスを選択してください');
      return;
    }
    await _guard(() async {
      final n = await widget.service.endNapSessionsForClass(_selectedClassId!, _businessDate, DateTime.now());
      _snack(n > 0 ? '$_selectedClassName $n名を起床にしました' : '起床の対象がありません(就寝中の園児がいません)');
    });
  }

  // 列一括: その時刻列(slot)に就寝中の全児へ「各児の直前チェックと同じ体位」で一括記録。
  // 直前チェックが無い児・当該スロットが既記入の児はスキップ(旧「5分前と同じ」の
  // “ちょうど5分前が必須”という不具合を避け、隣接に限らず各児の最新の直前記録を複製する)。
  Future<void> _columnBulk(DateTime slotUtc) async {
    final rows = _displayRows();
    await _guard(() async {
      var count = 0;
      for (final r in rows) {
        if (r.sessionId == null) continue;
        if (!_isSleepingAt(r, slotUtc)) continue;
        if (r.checkAt(slotUtc) != null) continue;
        final prior = _priorCheck(r, slotUtc);
        if (prior == null) continue;
        await widget.service.recordNapCheck(
          r.sessionId!,
          slotUtc,
          bodyPosition: prior.bodyPosition,
          breathing: prior.breathing,
          complexion: prior.complexion,
          bedding: prior.bedding,
        );
        count++;
      }
      _snack(count > 0
          ? '$count件を「直前と同じ」で登録しました'
          : '対象がありません(就寝中で直前チェックのある未記入セルなし)');
    });
  }

  Future<void> _openCell(String sessionId, DateTime slot, _RosterRow r) async {
    final existing = r.checkAt(slot);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NapCheckSheet(
        service: widget.service,
        sessionId: sessionId,
        childName: r.nameLabel,
        slotAt: slot,
        existing: existing,
        hasPrev: r.checkAt(slot.subtract(const Duration(minutes: 5))) != null,
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
      await _reload();
    } catch (_) {
      _snack('操作に失敗しました(権限をご確認ください: 30分超・過去日は主任以上)');
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _displayRows();
    final slots = _hourSlots(_selectedHour);
    final nowUtc = DateTime.now().toUtc();
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        titleSpacing: 0,
        toolbarHeight: 48,
        title: const Text('午睡チェック', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [const NowClock(), BusinessDateAction(date: _businessDate, onChanged: _onDateChanged)],
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
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedHour,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '時間帯', isDense: true, border: OutlineInputBorder()),
                    items: [
                      for (var h = 0; h < 24; h++)
                        DropdownMenuItem<int>(value: h, child: Text('${h.toString().padLeft(2, '0')}:00 台')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedHour = v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FilledButton.tonalIcon(
                          onPressed: _classBulkStart, icon: const Icon(Icons.bedtime_rounded, size: 16), label: const Text('入眠(一括)')),
                      FilledButton.tonalIcon(
                          onPressed: _classBulkEnd, icon: const Icon(Icons.wb_sunny_rounded, size: 16), label: const Text('起床(一括)')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 略記の凡例(セルは固定幅のため短縮表記。正式名はタップ時のシートにも表示)。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '凡例: 仰=仰向け / 右 / 左 / 伏直=うつ伏せ直し / 未=未記録',
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.9)),
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
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _headerRow(slots),
                                for (final r in rows) _childRow(r, slots, nowUtc),
                              ],
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(List<DateTime> slots) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(
        children: [
          const SizedBox(width: _nameColWidth, child: Text('園児 / 区間', style: TextStyle(fontSize: 11, color: AppColors.textSecondary))),
          for (final s in slots)
            SizedBox(
              width: _cellWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_hm(s), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  // 列一括: この時刻に就寝中の全児へ、各児の直前チェックと同じ体位で一括記録。
                  InkWell(
                    onTap: _columnBulkEnabled(s) ? () => _columnBulk(s) : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Opacity(
                      opacity: _columnBulkEnabled(s) ? 1 : 0.35,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.leafGreen.withValues(alpha: 0.6)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('一括', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.leafGreen)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _childRow(_RosterRow r, List<DateTime> slots, DateTime nowUtc) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x11000000)))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: _nameColWidth, child: _nameCell(r)),
          for (final slot in slots) _cell(r, slot, nowUtc),
        ],
      ),
    );
  }

  Widget _nameCell(_RosterRow r) {
    // 名前横の区間表示「10:05-10:19 / 10:19-就寝中」(就寝中は最大1つ)。
    final label = r.intervals.isEmpty
        ? '未入眠'
        : r.intervals.map((i) => '${_hm(i.sleepStartAt)}-${i.wakeUpAt != null ? _hm(i.wakeUpAt!) : '就寝中'}').join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(r.nameLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Wrap(
          spacing: 4,
          children: [
            if (r.notSlept)
              _rowBtn('入眠', AppColors.leafGreen, () => _sleep(r)),
            if (r.isSleeping)
              _rowBtn('起床', AppColors.punchClockOut, () => _wake(r)),
            if (r.isAllWoken)
              _rowBtn('再入眠', AppColors.leafGreen, () => _reSleep(r)),
          ],
        ),
      ],
    );
  }

  Widget _rowBtn(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }

  // 共通軸のセル: 就寝中=記録セル(緑/未/—・窓内タップ可)、就寝外=薄グレー(空欄)。
  Widget _cell(_RosterRow r, DateTime slot, DateTime nowUtc) {
    final sleeping = _isSleepingAt(r, slot);
    final check = r.checkAt(slot);
    // 就寝中でなく記録も無いセルは空欄(記録対象外)。
    if (!sleeping && check == null) {
      return Container(
        width: _cellWidth,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
        decoration: BoxDecoration(color: AppColors.textSecondary.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(6)),
      );
    }
    final Color bg;
    final String body;
    if (check != null) {
      bg = AppColors.leafGreen.withValues(alpha: 0.22);
      // セル内は短縮表記(格子を崩さない)。正式名はタップ時のシート・凡例で表示。
      body = napBodyPositionsShort[check.bodyPosition] ?? check.bodyPosition;
    } else if (slot.isBefore(nowUtc)) {
      bg = AppColors.punchClockOut.withValues(alpha: 0.20);
      body = '未';
    } else {
      bg = AppColors.textSecondary.withValues(alpha: 0.08);
      body = '—';
    }
    final editable = _cellCanEdit(slot, check != null);
    final cell = Container(
      width: _cellWidth,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Center(
        child: Text(
          body,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
    Widget result;
    if (!editable) {
      // 権限的に修正不可: タップ無効化 + グレーアウト表示。
      result = Opacity(opacity: 0.4, child: cell);
    } else {
      result = GestureDetector(
        onTap: r.sessionId != null ? () => _openCell(r.sessionId!, slot, r) : null,
        child: cell,
      );
    }
    // X4: 記録済セルは長押し/ホバーで記録者名をポップアップ(コドモン準拠)。
    if (check?.checkedByName != null) {
      result = Tooltip(
        message: '${napBodyPositions[check!.bodyPosition] ?? check.bodyPosition} / 記録者: ${check.checkedByName}',
        child: result,
      );
    }
    return result;
  }

  String _hm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
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
