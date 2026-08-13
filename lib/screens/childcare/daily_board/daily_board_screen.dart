import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/childcare.dart';
import '../../../models/guardian_app.dart';
import '../../../models/nap.dart';
import '../../../widgets/time_dropdown_picker.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import '../children/child_detail_screen.dart';
import '../contacts/daily_contact_detail_screen.dart';
import '../family_report/family_report_list_screen.dart';

/// 保護者アプリ・後続保育機能 Phase A: デイリーボード(iPad中心)。
/// 登降園は保護者アプリ・キオスク端末など複数端末から記録されるため、Realtimeで即時反映する。
/// Phase 2 §2.1/§2.2: クラス絞り込み(年齢区分順)と在籍登園状況サマリーを追加。
class DailyBoardScreen extends StatefulWidget {
  const DailyBoardScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
    this.isManager = false,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;
  final bool isManager;

  @override
  State<DailyBoardScreen> createState() => _DailyBoardScreenState();
}

class _DailyBoardScreenState extends State<DailyBoardScreen> {
  late DateTime _businessDate = widget.businessDate;
  late Future<List<DailyBoardRow>> _rowsFuture;
  RealtimeChannel? _channel;

  List<ChildcareClass> _classes = const [];
  // null = 全クラス。クラスの並び順は fetch_childcare_classes の返却順(年齢区分順)を正とする。
  String? _selectedClassId;
  DailyBoardSummary? _summary;
  WeatherRecord? _weather;
  bool _weatherLoaded = false;
  List<DailyBoardRow> _allRows = const [];
  List<NapMissing> _napMissing = const [];
  // 198: 承認済み欠席(期間)を行内に表示するための childId→(start,end,kind)。付加情報。
  Map<String, ({DateTime start, DateTime end, String kind})> _absenceByChild = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadClasses();
    _loadSummary();
    _loadWeather();
    _loadNapMissing();
    _loadAbsencePeriods();
    _channel = widget.service.watchDailyChildStatus(widget.officeId, () {
      if (!mounted) return;
      setState(_load);
      _loadSummary();
      _loadAbsencePeriods();
    });
  }

  @override
  void dispose() {
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  void _load() {
    _rowsFuture = widget.service.fetchDailyBoardForOffice(widget.officeId, _businessDate).then((rows) {
      _allRows = rows; // 一括操作の対象抽出用に保持
      return rows;
    });
  }

  // 一括対象: 表示中(絞り込み後)の approved かつ未公開の contact_id。
  List<String> _bulkEligibleContactIds() => _allRows
      .where((r) =>
          (_selectedClassId == null || r.classId == _selectedClassId) &&
          r.contactStatus == 'approved' &&
          r.contactPublishedAt == null &&
          r.contactId != null)
      .map((r) => r.contactId!)
      .toList();

  // 対象日 + 時刻(JST壁時計)を UTC 実時刻へ変換(端末TZ非依存)。
  DateTime _businessDateAt(int hour, int minute) => DateTime.utc(
        _businessDate.year,
        _businessDate.month,
        _businessDate.day,
        hour,
        minute,
      ).subtract(const Duration(hours: 9));

  Future<void> _afterContactChange() async {
    if (!mounted) return;
    setState(_load);
    _loadSummary();
    await _rowsFuture;
  }

  Future<void> _scheduleContacts(List<String> ids, {required int hour, required int minute}) async {
    await widget.service.scheduleDailyContacts(ids, _businessDateAt(hour, minute));
    await _afterContactChange();
  }

  Future<void> _publishContactsNow(List<String> ids) async {
    await widget.service.publishDailyContactsNow(ids);
    await _afterContactChange();
  }

  Future<void> _cancelContacts(List<String> ids) async {
    await widget.service.cancelDailyContactsSchedule(ids);
    await _afterContactChange();
  }

  Future<void> _pickAndSchedule(List<String> ids) async {
    final picked = await showTimeDropdownPicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
    if (picked != null) await _scheduleContacts(ids, hour: picked.hour, minute: picked.minute);
  }

  Future<void> _loadClasses() async {
    final classes = await widget.service.fetchChildcareClasses(widget.officeId);
    if (mounted) setState(() => _classes = classes);
  }

  Future<void> _loadSummary() async {
    final summary = await widget.service.fetchDailyBoardSummary(
      widget.officeId,
      _businessDate,
      classId: _selectedClassId,
    );
    if (mounted) setState(() => _summary = summary);
  }

  Future<void> _loadWeather() async {
    final weather = await widget.service.fetchDailyWeather(widget.officeId, _businessDate);
    if (mounted) {
      setState(() {
        _weather = weather;
        _weatherLoaded = true;
      });
    }
  }

  // §3.4: 午睡チェックの記入漏れ警告バナー用。
  Future<void> _loadNapMissing() async {
    try {
      final missing = await widget.service.fetchNapMissingSlots(widget.officeId, _businessDate);
      if (mounted) setState(() => _napMissing = missing);
    } catch (_) {
      // 取得失敗時はバナー非表示(安全側)。
    }
  }

  // 198: 承認済み欠席(期間)を取得。付加情報のため失敗は握りつぶし(バッジ非表示=安全側)。
  Future<void> _loadAbsencePeriods() async {
    try {
      final m = await widget.service.fetchBoardAbsencePeriodsForOffice(widget.officeId, _businessDate);
      if (mounted) setState(() => _absenceByChild = m);
    } catch (_) {
      // 取得失敗時は前回値のまま/非表示。
    }
  }

  Future<void> _reload() async {
    setState(_load);
    _loadSummary();
    _loadWeather();
    _loadAbsencePeriods();
    await _rowsFuture;
  }

  // 198: 承認済み欠席(期間)の行内バッジ。期間「MM/DD〜MM/DD 欠席予定(病欠/都合欠)」・単日「MM/DD 欠席予定(...)」。
  Widget _absencePeriodBadge(({DateTime start, DateTime end, String kind}) p) {
    String md(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final kindLabel = p.kind == 'sick_absence' ? '病欠' : p.kind == 'personal_absence' ? '都合欠' : '欠席';
    final sameDay = p.start.year == p.end.year && p.start.month == p.end.month && p.start.day == p.end.day;
    final range = sameDay ? md(p.start) : '${md(p.start)}〜${md(p.end)}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.punchClockOut.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_busy_rounded, size: 18, color: AppColors.punchClockOut),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$range 欠席予定($kindLabel)',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.punchClockOut),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // K5(i): デイリーボード行から欠席登録/取消(簡易)。種別/メモ付きの本格編集は後続の出欠モーダル(K7)で。
  Future<void> _toggleAbsence(DailyBoardRow row) async {
    final makeAbsent = row.status != 'absent';
    if (makeAbsent) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('${row.nameLabel} を欠席にしますか?'),
          content: const Text('欠席にすると当日の連絡帳作成対象から外れます(出席に戻せます)。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('欠席にする')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await widget.service.setChildDailyAttendance(
        childId: row.childId,
        businessDate: _businessDate,
        isAbsent: makeAbsent,
        absenceReason: null,
      );
      if (mounted) {
        setState(_load);
        _loadSummary();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(makeAbsent ? '欠席にしました' : '出席に戻しました')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('操作に失敗しました')));
      }
    }
  }

  Future<void> _editWeather() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WeatherEditSheet(
        service: widget.service,
        officeId: widget.officeId,
        businessDate: _businessDate,
        initial: _weather,
      ),
    );
    if (saved == true) _loadWeather();
  }

  void _onClassChanged(String? classId) {
    setState(() => _selectedClassId = classId);
    _loadSummary();
  }

  void _onDateChanged(DateTime d) {
    setState(() {
      _businessDate = d;
      _load();
    });
    _loadSummary();
    _loadWeather();
    _loadNapMissing();
    _loadAbsencePeriods();
  }

  // K5(iii)/Phase A: 園児行から当日の連絡帳(園側 日誌・連絡帳)へ。既存詳細画面を再利用。
  Future<void> _openContact(DailyBoardRow row) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DailyContactDetailScreen(
        service: widget.service,
        officeId: widget.officeId,
        childId: row.childId,
        childNameLabel: row.nameLabel,
        businessDate: _businessDate,
        isManager: widget.isManager,
      ),
    ));
    if (mounted) {
      setState(_load);
      _loadSummary();
    }
  }

  // K7: 出欠編集モーダル。種別/予定override(185) + 実績 入/外/戻/退(187・主任のみ・全置換)を1画面で。
  Future<void> _openAttendanceEdit(DailyBoardRow row) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AttendanceEditSheet(
        service: widget.service,
        row: row,
        businessDate: _businessDate,
        isManager: widget.isManager,
      ),
    );
    if (saved == true && mounted) {
      setState(_load);
      _loadSummary();
    }
  }

  // 家庭での様子 一覧(Phase A)。デイリーボードからの導線。
  void _openFamilyReports() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FamilyReportListScreen(
        service: widget.service,
        officeId: widget.officeId,
        businessDate: _businessDate,
      ),
    ));
  }

  void _openChildDetail(DailyBoardRow row) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChildDetailScreen(
          service: widget.service,
          childId: row.childId,
          childName: row.nameLabel,
          officeId: widget.officeId,
          businessDate: _businessDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        toolbarHeight: 48,
        titleSpacing: 0,
        title: const Text('デイリーボード', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [
          const _NowClock(),
          TextButton.icon(
            onPressed: _openFamilyReports,
            icon: const Icon(Icons.family_restroom_rounded, size: 16),
            label: const Text('家庭での様子', style: TextStyle(fontSize: 13)),
          ),
          // 「本日」ボタン: 対象日を本日に戻す。
          TextButton(
            onPressed: () => _onDateChanged(DateTime.now()),
            child: const Text('本日', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          BusinessDateAction(date: _businessDate, onChanged: _onDateChanged),
        ],
      ),
      body: Column(
        children: [
          // クラス絞り込みと天気を1行に集約(縦の占有を減らし園児リスト領域を広げる)。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 200,
                  child: _ClassFilterBar(
                    classes: _classes,
                    selectedClassId: _selectedClassId,
                    onChanged: _onClassChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _WeatherBar(weather: _weather, loaded: _weatherLoaded, onTap: _editWeather)),
              ],
            ),
          ),
          if (_napMissing.isNotEmpty) _NapMissingBanner(missing: _napMissing),
          _SummaryBar(summary: _summary),
          _ContactBulkBar(
            scopeLabel: _selectedClassId == null ? '施設一括' : 'クラス一括',
            onSchedule17: () => _scheduleContacts(_bulkEligibleContactIds(), hour: 17, minute: 0),
            onPublishNow: () => _publishContactsNow(_bulkEligibleContactIds()),
            onCancel: () => _cancelContacts(_bulkEligibleContactIds()),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: FutureBuilder<List<DailyBoardRow>>(
                future: _rowsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data ?? const <DailyBoardRow>[];
                  final rows = _selectedClassId == null
                      ? all
                      : all.where((r) => r.classId == _selectedClassId).toList();
                  if (rows.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [SizedBox(height: 120), Center(child: Text('在籍園児がいません'))],
                    );
                  }
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Card(
                        child: Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              onTap: () => _openChildDetail(row),
                              title: Text(row.nameLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(row.className, style: const TextStyle(color: AppColors.textSecondary)),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 14,
                                    runSpacing: 2,
                                    children: [
                                      InkWell(
                                        onTap: () => _openContact(row),
                                        borderRadius: BorderRadius.circular(6),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.menu_book_rounded, size: 15, color: AppColors.skyBlue),
                                              SizedBox(width: 4),
                                              Text('日誌・連絡帳',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.skyBlue)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => _openAttendanceEdit(row),
                                        borderRadius: BorderRadius.circular(6),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(vertical: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.edit_calendar_rounded, size: 15, color: AppColors.warmOrange),
                                              SizedBox(width: 4),
                                              Text('出欠編集',
                                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warmOrange)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                    onTap: () => _toggleAbsence(row),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            row.status == 'absent' ? Icons.undo_rounded : Icons.event_busy_rounded,
                                            size: 15,
                                            color: row.status == 'absent' ? AppColors.leafGreen : AppColors.punchClockOut,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            row.status == 'absent' ? '出席に戻す' : '欠席にする',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: row.status == 'absent' ? AppColors.leafGreen : AppColors.punchClockOut,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _StatusChip(status: effectiveBoardStatus(row)),
                                ],
                              ),
                            ),
                            _AttendanceTimeBar(row: row),
                            if (row.hasPickupChange)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.warmOrange.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person_pin_circle_rounded, size: 18, color: AppColors.warmOrange),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'お迎え変更あり: ${row.pickupPersonName}'
                                        '${row.pickupTimeFrom != null ? '(${row.pickupTimeFrom}〜${row.pickupTimeTo})' : ''}',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (row.onTherapyOuting)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF9B7EDE).withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.directions_walk_rounded, size: 18, color: Color(0xFF7A5FC0)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '療育外出中'
                                        '${row.therapyOutAt != null ? '(${row.therapyOutAt!.toLocal().hour.toString().padLeft(2, '0')}:${row.therapyOutAt!.toLocal().minute.toString().padLeft(2, '0')})' : ''}'
                                        '${row.therapyProviderName != null ? ' ${row.therapyProviderName}' : ''}',
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF7A5FC0)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_absenceByChild[row.childId] != null)
                              _absencePeriodBadge(_absenceByChild[row.childId]!),
                            _ContactPublishRow(
                              row: row,
                              onSchedule17: () => _scheduleContacts([row.contactId!], hour: 17, minute: 0),
                              onPickTime: () => _pickAndSchedule([row.contactId!]),
                              onPublishNow: () => _publishContactsNow([row.contactId!]),
                              onCancel: () => _cancelContacts([row.contactId!]),
                            ),
                          ],
                        ),
                      );
                    },
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

/// §3.4 午睡チェック記入漏れの警告バナー(園児・漏れ件数)。
class _NapMissingBanner extends StatelessWidget {
  const _NapMissingBanner({required this.missing});

  final List<NapMissing> missing;

  @override
  Widget build(BuildContext context) {
    final names = missing
        .map((m) => '${m.displayName}(${m.className}・${m.missingCount})')
        .take(6)
        .join('、');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.punchClockOut.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.punchClockOut.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.punchClockOut),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '午睡チェックの記入漏れがあります: $names',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.punchClockOut),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 連絡帳公開の一括バー(表示中=クラス選択中ならクラス一括、全クラスなら施設一括)。
class _ContactBulkBar extends StatelessWidget {
  const _ContactBulkBar({
    required this.scopeLabel,
    required this.onSchedule17,
    required this.onPublishNow,
    required this.onCancel,
  });

  final String scopeLabel;
  final VoidCallback onSchedule17;
  final VoidCallback onPublishNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Text('連絡帳 $scopeLabel',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
          const Spacer(),
          TextButton(onPressed: onSchedule17, child: const Text('17時予約')),
          TextButton(onPressed: onPublishNow, child: const Text('今すぐ公開')),
          TextButton(onPressed: onCancel, child: const Text('取消')),
        ],
      ),
    );
  }
}

/// カード内の連絡帳公開状態バッジ+操作(承認済み・未公開のみ操作可)。
class _ContactPublishRow extends StatelessWidget {
  const _ContactPublishRow({
    required this.row,
    required this.onSchedule17,
    required this.onPickTime,
    required this.onPublishNow,
    required this.onCancel,
  });

  final DailyBoardRow row;
  final VoidCallback onSchedule17;
  final VoidCallback onPickTime;
  final VoidCallback onPublishNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final badge = row.contactBadge;
    if (badge == 'none') return const SizedBox.shrink();

    Widget chip(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        );

    final List<Widget> children;
    switch (badge) {
      case 'draft':
        children = [chip('連絡帳: 下書き', AppColors.textSecondary)];
      case 'published':
        children = [chip('連絡帳: 公開済', AppColors.leafGreen)];
      case 'scheduled':
        final at = row.contactScheduledPublishAt!.toLocal();
        final t = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
        children = [
          chip('公開予約済 $t', AppColors.warmOrange),
          TextButton(onPressed: onPickTime, child: const Text('時刻変更')),
          TextButton(onPressed: onPublishNow, child: const Text('今すぐ公開')),
          TextButton(onPressed: onCancel, child: const Text('取消')),
        ];
      default: // unscheduled(承認済み・予約なし=取消後)
        children = [
          chip('連絡帳: 非公開', AppColors.textSecondary),
          TextButton(onPressed: onSchedule17, child: const Text('17時予約')),
          TextButton(onPressed: onPickTime, child: const Text('時刻指定')),
          TextButton(onPressed: onPublishNow, child: const Text('今すぐ公開')),
        ];
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: children),
    );
  }
}

/// 画面端(AppBar右)に現在の日付・時刻をリアルタイム表示する時計(1秒更新)。
class _NowClock extends StatefulWidget {
  const _NowClock();

  @override
  State<_NowClock> createState() => _NowClockState();
}

class _NowClockState extends State<_NowClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;
  static const _wd = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _now;
    String two(int v) => v.toString().padLeft(2, '0');
    final text = '${n.year}/${two(n.month)}/${two(n.day)}(${_wd[n.weekday - 1]}) '
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      ),
    );
  }
}

/// クラス絞り込み(全クラス既定→クラス単位)。並び順は fetch_childcare_classes の返却順に従う。
class _ClassFilterBar extends StatelessWidget {
  const _ClassFilterBar({
    required this.classes,
    required this.selectedClassId,
    required this.onChanged,
  });

  final List<ChildcareClass> classes;
  final String? selectedClassId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: selectedClassId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'クラス',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全クラス')),
        for (final c in classes)
          DropdownMenuItem<String?>(value: c.classId, child: Text(c.className)),
      ],
      onChanged: onChanged,
    );
  }
}

/// 天気バー。未入力なら「未入力」を軽く表示(強アラート無し)。タップで編集シートを開く。
class _WeatherBar extends StatelessWidget {
  const _WeatherBar({required this.weather, required this.loaded, required this.onTap});

  final WeatherRecord? weather;
  final bool loaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = weather;
    final label = !loaded
        ? '天気'
        : w == null
            ? '天気: 未入力'
            : '天気: ${w.weather}'
                '${w.temperature != null ? ' / ${w.temperature}℃' : ''}'
                '${w.humidity != null ? ' / ${w.humidity}%' : ''}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.skyBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.wb_sunny_rounded, size: 18, color: AppColors.warmOrange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: w == null ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.edit_rounded, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// 天気の編集シート。当日は誰でも、過去日/未来日は主任以上(RPC側でガード・失敗時はSnackBar)。
class _WeatherEditSheet extends StatefulWidget {
  const _WeatherEditSheet({
    required this.service,
    required this.officeId,
    required this.businessDate,
    required this.initial,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;
  final WeatherRecord? initial;

  @override
  State<_WeatherEditSheet> createState() => _WeatherEditSheetState();
}

class _WeatherEditSheetState extends State<_WeatherEditSheet> {
  late String _weather = widget.initial?.weather ?? weatherOptions.first;
  late final TextEditingController _temp =
      TextEditingController(text: widget.initial?.temperature?.toString() ?? '');
  late final TextEditingController _humidity =
      TextEditingController(text: widget.initial?.humidity?.toString() ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _temp.dispose();
    _humidity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.upsertDailyWeather(
        widget.officeId,
        widget.businessDate,
        weather: _weather,
        temperature: _temp.text.trim().isEmpty ? null : double.tryParse(_temp.text.trim()),
        humidity: _humidity.text.trim().isEmpty ? null : double.tryParse(_humidity.text.trim()),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('天気の保存に失敗しました(過去日/未来日の修正は主任以上のみ)')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('天気の記録', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _weather,
            decoration: const InputDecoration(labelText: '天気', border: OutlineInputBorder(), isDense: true),
            items: [for (final o in weatherOptions) DropdownMenuItem(value: o, child: Text(o))],
            onChanged: (v) => setState(() => _weather = v ?? _weather),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _temp,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '気温(℃)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _humidity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '湿度(%)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 在籍登園状況サマリー(在籍/登園予定/出席/登園中/欠席)。数字はRPC集計を表示するのみ。
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.summary});

  final DailyBoardSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final items = <_SummaryItem>[
      _SummaryItem('在籍', s?.enrolled, AppColors.textPrimary),
      _SummaryItem('登園予定', s?.expected, AppColors.skyBlue),
      _SummaryItem('出席', s?.attended, AppColors.leafGreen),
      _SummaryItem('登園中', s?.presentNow, AppColors.leafGreen),
      _SummaryItem('欠席', s?.absent, AppColors.punchClockOut),
    ];
    // 園児一覧の表示領域を最大化するため、5枚の大カード→1本の細いバーに圧縮。
    // 縦向きでも溢れないよう Wrap で折り返す。ラベル・色・数字・Realtime更新は不変。
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in items)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(width: 4),
                    Text(
                      item.value?.toString() ?? '—',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: item.color),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.value, this.color);
  final String label;
  final int? value;
  final Color color;
}

// K7で出欠種別=病欠/都合欠(is_absent同期対象)の園児は状態を「欠席」表示にする
// (daily_child_status は代理打刻由来のため未登園のまま。サマリーの欠席数と整合させる)。
String effectiveBoardStatus(DailyBoardRow row) {
  if (row.attendanceKind == 'sick_absence' || row.attendanceKind == 'personal_absence') {
    return 'absent';
  }
  return row.status;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case 'present':
        color = AppColors.leafGreen;
      case 'picked_up':
        color = AppColors.textSecondary;
      case 'absent':
        color = AppColors.punchClockOut;
      default:
        color = AppColors.warmOrange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        dailyBoardStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

/// K6: 登降園タイムバー(行内)。予定=薄バー(186の二層解決値)、実績=濃バー(登園〜降園、中抜けは切れ目)。
/// 上に実績時刻、下に予定時刻を小さく表示。予定も実績も無ければ非表示。
class _AttendanceTimeBar extends StatelessWidget {
  const _AttendanceTimeBar({required this.row});

  final DailyBoardRow row;

  int? _minFromDbTime(String? s) {
    if (s == null || s.length < 5) return null;
    final p = s.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int? _minFromDt(DateTime? d) {
    if (d == null) return null;
    final l = d.toLocal();
    return l.hour * 60 + l.minute;
  }

  String _hm(int? m) => m == null ? '--:--' : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final schedS = _minFromDbTime(row.scheduledStartAt);
    final schedE = _minFromDbTime(row.scheduledEndAt);
    final arr = _minFromDt(row.arrivalAt);
    final dep = _minFromDt(row.departureAt);
    final out = _minFromDt(row.outAt);
    final ret = _minFromDt(row.returnAt);
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final actEnd = dep ?? (arr != null ? nowMin : null);

    if (schedS == null && arr == null) return const SizedBox.shrink();

    // K6再設計(俊確定): 行ごとの相対スケールをやめ、1日固定の絶対時間軸(07:00-19:00)に統一。
    // 全園児が同一スケールになり「早く来た子はバー開始が左」「早く帰った子はバーが短い」と
    // 誰がどの時間帯に在園したかを縦並びで比較できる。予定(薄)も実績(濃)も同じ軸に乗る。
    // 窓外(早朝・夜間)はクランプ。admin_web の AttendanceTimeBar と同一レンジ。
    const winStart = 7 * 60; // 07:00
    const winEnd = 19 * 60; // 19:00
    const span = winEnd - winStart;
    double frac(int m) => ((m.clamp(winStart, winEnd) - winStart) / span).toDouble();

    final actualLabel = arr == null
        ? ''
        : '登園 ${_hm(arr)}'
            '${dep != null ? ' / 降園 ${_hm(dep)}' : ' / 在園中'}'
            '${(out != null && ret != null) ? ' ・中抜け ${_hm(out)}〜${_hm(ret)}' : ''}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (actualLabel.isNotEmpty)
            Text(actualLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.skyBlue)),
          const SizedBox(height: 2),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            Widget seg(int a, int b, Color col, double top, double h) {
              final l = frac(a) * w;
              final r = frac(b) * w;
              return Positioned(
                left: l,
                width: (r - l).clamp(2.0, w),
                top: top,
                height: h,
                child: Container(decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(4))),
              );
            }

            final children = <Widget>[
              Positioned(
                left: 0, right: 0, top: 7, height: 6,
                child: Container(decoration: BoxDecoration(color: AppColors.textSecondary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(4))),
              ),
            ];
            if (schedS != null && schedE != null) {
              children.add(seg(schedS, schedE, AppColors.skyBlue.withValues(alpha: 0.28), 5, 10));
            }
            if (arr != null && actEnd != null) {
              if (out != null && ret != null && out < ret) {
                children.add(seg(arr, out, AppColors.skyBlue, 5, 10));
                children.add(seg(ret, actEnd, AppColors.skyBlue, 5, 10));
              } else {
                children.add(seg(arr, actEnd, AppColors.skyBlue, 5, 10));
              }
            }
            return SizedBox(height: 20, width: w, child: Stack(children: children));
          }),
          if (schedS != null || schedE != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('予定 ${_hm(schedS)}〜${_hm(schedE)}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }
}

/// K7: 出欠編集モーダル。出欠種別/予定override(185) + 実績 入/外/戻/退(187・主任のみ・全置換)。
/// 実績は現在値を全4値プリフィルして187へ渡す(187の全置換セマンティクス厳守)。
class _AttendanceEditSheet extends StatefulWidget {
  const _AttendanceEditSheet({required this.service, required this.row, required this.businessDate, required this.isManager});

  final ChildcareService service;
  final DailyBoardRow row;
  final DateTime businessDate;
  final bool isManager;

  @override
  State<_AttendanceEditSheet> createState() => _AttendanceEditSheetState();
}

class _AttendanceEditSheetState extends State<_AttendanceEditSheet> {
  static const _kinds = [
    ('none', '-'),
    ('late', '遅刻'),
    ('early_leave', '早退'),
    ('sick_absence', '病欠'),
    ('personal_absence', '都合欠'),
  ];

  late String _kind = widget.row.attendanceKind ?? 'none';
  late TimeOfDay? _schedStart = _fromDbTime(widget.row.scheduledStartAt);
  late TimeOfDay? _schedEnd = _fromDbTime(widget.row.scheduledEndAt);
  late TimeOfDay? _in = _fromDt(widget.row.arrivalAt);
  late TimeOfDay? _out = _fromDt(widget.row.outAt);
  late TimeOfDay? _return = _fromDt(widget.row.returnAt);
  late TimeOfDay? _depart = _fromDt(widget.row.departureAt);
  late final TextEditingController _note = TextEditingController(text: widget.row.attendanceNote ?? '');
  bool _saving = false;

  static TimeOfDay? _fromDbTime(String? s) {
    if (s == null || s.length < 5) return null;
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static TimeOfDay? _fromDt(DateTime? d) => d == null ? null : TimeOfDay.fromDateTime(d.toLocal());

  static String? _hhmm(TimeOfDay? t) => t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pick(TimeOfDay? init) => showTimeDropdownPicker(context: context, initialTime: init ?? TimeOfDay.now());

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.service.setChildAttendanceStatus(
        widget.row.childId,
        widget.businessDate,
        _kind,
        scheduledStart: _hhmm(_schedStart),
        scheduledEnd: _hhmm(_schedEnd),
        attendanceNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      // 実績は主任のみ。全4値をプリフィルのまま渡す(187=全置換・NULL=クリア)。
      if (widget.isManager) {
        await widget.service.setChildAttendanceActuals(
          widget.row.childId,
          widget.businessDate,
          inAt: _hhmm(_in),
          outAt: _hhmm(_out),
          returnAt: _hhmm(_return),
          departAt: _hhmm(_depart),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存に失敗しました(過去日・実績修正は主任以上)')),
        );
      }
    }
  }

  Widget _timeField(String label, TimeOfDay? value, ValueChanged<TimeOfDay?> onChanged, {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: !enabled ? null : () async { final t = await _pick(value); if (t != null) onChanged(t); },
              child: Text(_hhmm(value) ?? '--:--'),
            ),
            if (value != null && enabled)
              IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => onChanged(null), tooltip: 'クリア'),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.businessDate;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.row.nameLabel} の出欠状況  ${d.year}/${d.month}/${d.day}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 14),
            const Text('出欠', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final k in _kinds)
                ChoiceChip(label: Text(k.$2), selected: _kind == k.$1, onSelected: (_) => setState(() => _kind = k.$1)),
            ]),
            const SizedBox(height: 14),
            const Text('登降園(予定)', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Row(children: [
              _timeField('登園予定', _schedStart, (t) => setState(() => _schedStart = t)),
              const SizedBox(width: 16),
              _timeField('降園予定', _schedEnd, (t) => setState(() => _schedEnd = t)),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              const Text('登降園(実績)', style: TextStyle(color: AppColors.textSecondary)),
              if (!widget.isManager)
                const Padding(padding: EdgeInsets.only(left: 8), child: Text('※修正は主任以上', style: TextStyle(fontSize: 11, color: AppColors.punchClockOut))),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 8, children: [
              _timeField('入', _in, (t) => setState(() => _in = t), enabled: widget.isManager),
              _timeField('外', _out, (t) => setState(() => _out = t), enabled: widget.isManager),
              _timeField('戻', _return, (t) => setState(() => _return = t), enabled: widget.isManager),
              _timeField('退', _depart, (t) => setState(() => _depart = t), enabled: widget.isManager),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '出欠メモ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('キャンセル'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? '保存中…' : '保存'))),
            ]),
          ],
        ),
      ),
    );
  }
}
