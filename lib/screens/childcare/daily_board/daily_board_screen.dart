import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/childcare.dart';
import '../../../models/guardian_app.dart';
import '../../../models/nap.dart';
import '../../../widgets/time_dropdown_picker.dart';
import '../../../services/childcare_active_office.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import '../children/child_detail_screen.dart';
import '../contacts/daily_contact_detail_screen.dart';
import '../family_report/family_report_list_screen.dart';
import '../health/temperature_screen.dart';

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
  // 施設切替(俊要望): デイリーボード内で操作施設を変更できるようにする。widget値を初期値にする。
  late String _officeId = widget.officeId;
  late bool _isManager = widget.isManager;
  List<ChildcareOffice> _offices = const [];
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
  // 201: 承認済み服薬連絡の行内バッジ用。childId→(種類, 解熱剤フラグ, 様子)。
  Map<String, ({List<String> kinds, bool hasAntipyretic, String? symptom})> _medicationByChild = const {};
  // 欠席児童一覧の「保護者からの連絡」。childId→承認済み欠席申請の理由。
  Map<String, String> _absenceCommentByChild = const {};
  // 承認済み 遅刻/早退 のバッジ用。childId→リスト(種別/予定時刻/理由)。
  Map<String, List<({String type, String? time, String? reason})>> _timeChangeByChild = const {};
  // 感染症案件バッジ用(206)。childId→リスト(病名/必要書類/書類状態)。
  Map<String, List<({String caseId, String status, String? diseaseName, String requiredDocument, String documentState})>>
      _infectionByChild = const {};
  // 202: 承認済みお迎え変更の行内バッジ用。childId→リスト(氏名/時間/確認済み/書類有無)。
  Map<String, List<({String? name, String? relationship, String? arrive, String? leave, bool idVerified, bool hasDocument})>>
      _pickupChangeByChild = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadOffices();
    _loadClasses();
    _loadSummary();
    _loadWeather();
    _loadNapMissing();
    _loadAbsencePeriods();
    _loadMedication();
    _loadPickupChanges();
    _subscribe();
    childcareActiveOfficeId.addListener(_onSharedOfficeChanged);
  }

  void _subscribe() {
    _channel = widget.service.watchDailyChildStatus(_officeId, () {
      if (!mounted) return;
      setState(_load);
      _loadSummary();
      _loadAbsencePeriods();
    });
  }

  // 施設切替(俊指示): 切替UIは黒帯(SessionBanner)へ集約。ここでは一覧を共有状態へ供給し、
  // 黒帯での変更(childcareActiveOfficeId)を listen して追随する。
  Future<void> _loadOffices() async {
    try {
      final offices = await widget.service.fetchMyChildcareOffices();
      if (!mounted) return;
      setState(() => _offices = offices);
      childcareOfficeList.value = offices;
      childcareActiveOfficeId.value ??= _officeId;
    } catch (_) {
      // 取得失敗時は切替UIを出さない(現施設のまま)。
    }
  }

  // 黒帯の施設プルダウン変更に追随する。
  void _onSharedOfficeChanged() {
    final id = childcareActiveOfficeId.value;
    if (id == null || id == _officeId || !mounted) return;
    for (final o in _offices) {
      if (o.officeId == id) {
        _onOfficeChanged(o);
        return;
      }
    }
  }

  // 施設を切り替える。クラス選択をリセットし、Realtime購読を張り直し、全データを再取得。
  // 共通ヘッダー(黒帯)の施設名も追随させる。
  void _onOfficeChanged(ChildcareOffice office) {
    if (office.officeId == _officeId) return;
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    setState(() {
      _officeId = office.officeId;
      _isManager = office.isManager;
      _selectedClassId = null;
      _classes = const [];
      _load();
    });
    childcareActiveOfficeName.value = office.officeName;
    _loadClasses();
    _loadSummary();
    _loadWeather();
    _loadNapMissing();
    _loadAbsencePeriods();
    _loadMedication();
    _loadPickupChanges();
    _subscribe();
  }

  @override
  void dispose() {
    childcareActiveOfficeId.removeListener(_onSharedOfficeChanged);
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  void _load() {
    _rowsFuture = widget.service.fetchDailyBoardForOffice(_officeId, _businessDate).then((rows) {
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
    final classes = await widget.service.fetchChildcareClasses(_officeId);
    if (mounted) setState(() => _classes = classes);
  }

  Future<void> _loadSummary() async {
    final summary = await widget.service.fetchDailyBoardSummary(
      _officeId,
      _businessDate,
      classId: _selectedClassId,
    );
    if (mounted) setState(() => _summary = summary);
  }

  Future<void> _loadWeather() async {
    final weather = await widget.service.fetchDailyWeather(_officeId, _businessDate);
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
      final missing = await widget.service.fetchNapMissingSlots(_officeId, _businessDate);
      if (mounted) setState(() => _napMissing = missing);
    } catch (_) {
      // 取得失敗時はバナー非表示(安全側)。
    }
  }

  // 198: 承認済み欠席(期間)を取得。付加情報のため失敗は握りつぶし(バッジ非表示=安全側)。
  Future<void> _loadAbsencePeriods() async {
    try {
      final m = await widget.service.fetchBoardAbsencePeriodsForOffice(_officeId, _businessDate);
      if (mounted) setState(() => _absenceByChild = m);
      try {
      final c = await widget.service.fetchApprovedAbsenceCommentsForOffice(_officeId, _businessDate);
      if (mounted) setState(() => _absenceCommentByChild = c);
    } catch (_) {
      // 取得失敗時は前回値のまま/非表示。
    }
    try {
      final t = await widget.service.fetchApprovedTimeChangeRequestsForOffice(_officeId, _businessDate);
      if (mounted) setState(() => _timeChangeByChild = t);
    } catch (_) {
      // 取得失敗時は前回値のまま/非表示。
    }
    try {
      final ic = await widget.service.fetchBoardInfectionCasesForOffice(_officeId);
      if (mounted) setState(() => _infectionByChild = ic);
    } catch (_) {
      // 取得失敗時は前回値のまま/非表示。
    }
  } catch (_) {
      // 取得失敗時は前回値のまま/非表示。
    }
  }

  // 201: 承認済み服薬連絡を取得。付加情報のため失敗は握りつぶし(バッジ非表示=安全側)。
  Future<void> _loadMedication() async {
    try {
      final m = await widget.service.fetchBoardMedicationForOffice(_officeId, _businessDate);
      if (mounted) setState(() => _medicationByChild = m);
    } catch (_) {
      // 取得失敗時は前回値のまま/非表示。
    }
  }

  Future<void> _loadPickupChanges() async {
    try {
      final m = await widget.service.fetchBoardPickupChangesForOffice(_officeId, _businessDate);
      if (mounted) setState(() => _pickupChangeByChild = m);
    } catch (_) {
      // 取得失敗時は前回値のまま/非表示。
    }
  }

  Future<void> _reload() async {
    setState(_load);
    _loadSummary();
    _loadWeather();
    _loadAbsencePeriods();
    _loadMedication();
    _loadPickupChanges();
    await _rowsFuture;
  }

  // クイックリンクタイル(Web版のタイル思想)。current=この画面(枠線強調・タップなし)、preparing=準備中(disabled)。
  Widget _quickTile(IconData icon, String label, Color? color, {VoidCallback? onTap, bool current = false, bool preparing = false}) {
    final c = preparing ? AppColors.textSecondary : (color ?? AppColors.skyBlue);
    return InkWell(
      onTap: preparing ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withValues(alpha: preparing ? 0.08 : 0.12),
          borderRadius: BorderRadius.circular(10),
          border: current ? Border.all(color: c, width: 1.2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
            if (preparing) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('準備中', style: TextStyle(fontSize: 9, color: AppColors.textSecondary)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 連絡帳一括(施設/クラス)。色+アイコン付きの視覚的に分かりやすいボタン群(俊指示)。
  Widget _bulkGroup() {
    final scopeLabel = _selectedClassId == null ? '施設一括' : 'クラス一括';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('連絡帳 $scopeLabel', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        _bulkButton('17時公開予約', Icons.schedule_rounded, AppColors.skyBlue,
            () => _scheduleContacts(_bulkEligibleContactIds(), hour: 17, minute: 0)),
        const SizedBox(width: 4),
        _bulkButton('今すぐ公開', Icons.send_rounded, AppColors.leafGreen,
            () => _publishContactsNow(_bulkEligibleContactIds())),
        const SizedBox(width: 4),
        _bulkButton('予約取消', Icons.cancel_schedule_send_rounded, AppColors.punchClockOut,
            () => _cancelContacts(_bulkEligibleContactIds())),
      ],
    );
  }

  Widget _bulkButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  // 201: 服薬バッジ(タップで種類・様子のダイアログ)。解熱剤を含む日は赤の警告(登園不可の園ルール周知)。
  Widget _medicationBadge(DailyBoardRow row, ({List<String> kinds, bool hasAntipyretic, String? symptom}) med) {
    final color = med.hasAntipyretic ? AppColors.punchClockOut : AppColors.skyBlue;
    final label = med.hasAntipyretic ? '解熱剤服用: ${med.kinds.join('、')}' : '服薬: ${med.kinds.join('、')}';
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('服薬連絡 — ${row.nameLabel}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('薬の種類: ${med.kinds.join('、')}'),
              if (med.hasAntipyretic) ...[
                const SizedBox(height: 8),
                const Text('⚠ 解熱剤を服用しています(解熱剤服用日は登園不可の園ルール)',
                    style: TextStyle(color: AppColors.punchClockOut, fontWeight: FontWeight.w700)),
              ],
              if (med.symptom != null && med.symptom!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('様子・症状: ${med.symptom}'),
              ],
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      ),
      child: _miniBadge(Icons.medication_rounded, label, color),
    );
  }

  // 右40%カラムの操作アイコン(ツールチップ付きの小ボタン)。日誌・連絡帳/出欠編集/欠席トグル。
  Widget _actionIcon(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: color),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }

  // DBのtime文字列('HH:MM:SS')をHH:MMへ整形。
  String _hm5(String? s) => s == null ? '' : (s.length >= 5 ? s.substring(0, 5) : s);

  // 右40%カラムの小バッジ(お迎え変更/療育外出中 等)。列幅内に収め溢れは省略。
  // 202: 承認済みお迎え変更バッジ。タップで詳細+実物確認済みチェック(主任以上のみ操作可)。
  Widget _pickupChangeBadge(
      DailyBoardRow row,
      ({String? name, String? relationship, String? arrive, String? leave, bool idVerified, bool hasDocument}) pc) {
    final color = pc.idVerified ? AppColors.leafGreen : AppColors.warmOrange;
    final who = '${pc.name ?? ''}${pc.relationship != null && pc.relationship!.isNotEmpty ? '(${pc.relationship})' : ''}';
    final times = '${pc.arrive != null ? ' 登園${pc.arrive}' : ''}${pc.leave != null ? ' お迎え${pc.leave}' : ''}';
    final label = 'お迎え変更: $who ${pc.idVerified ? '身分証✓' : '要確認'}$times';
    return InkWell(
      onTap: () => _showPickupChangeDialog(row, pc),
      child: _miniBadge(Icons.person_pin_circle_rounded, label, color),
    );
  }

  Future<void> _showPickupChangeDialog(
      DailyBoardRow row,
      ({String? name, String? relationship, String? arrive, String? leave, bool idVerified, bool hasDocument}) pc) async {
    // 実物確認チェックの対象person_idを氏名で解決(お迎え者マスタは園児×氏名で一意)。
    ({String personId, String name, bool hasDocument, bool idVerified})? person;
    try {
      final persons = await widget.service.fetchPickupPersonsForChild(row.childId);
      for (final p in persons) {
        if (p.name == pc.name) person = p;
      }
    } catch (_) {}
    if (!mounted) return;
    var verified = person?.idVerified ?? pc.idVerified;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('お迎え変更 — ${row.nameLabel}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('お迎えの方: ${pc.name ?? '—'}'
                  '${pc.relationship != null && pc.relationship!.isNotEmpty ? '(${pc.relationship})' : ''}'),
              if (pc.arrive != null || pc.leave != null) ...[
                const SizedBox(height: 8),
                Text('${pc.arrive != null ? '登園 ${pc.arrive}' : ''}'
                    '${pc.arrive != null && pc.leave != null ? ' / ' : ''}'
                    '${pc.leave != null ? 'お迎え ${pc.leave}' : ''}'),
              ],
              const SizedBox(height: 8),
              Text(pc.hasDocument ? '身分証明書: 提出済み' : '身分証明書: 未提出',
                  style: TextStyle(color: pc.hasDocument ? AppColors.textPrimary : AppColors.punchClockOut)),
              const SizedBox(height: 8),
              if (person == null)
                const Text('お迎え者マスタ未登録(承認前)のため確認チェックはできません',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
              else
                Row(
                  children: [
                    const Expanded(
                        child: Text('身分証を実物確認済み', style: TextStyle(fontWeight: FontWeight.w700))),
                    Switch(
                      value: verified,
                      // 実物確認のチェックは主任以上(set_pickup_person_id_verified側でも拒否される)。
                      onChanged: (!_isManager || busy)
                          ? null
                          : (v) async {
                              setDialogState(() => busy = true);
                              try {
                                await widget.service.setPickupPersonIdVerified(person!.personId, v);
                                setDialogState(() {
                                  verified = v;
                                  busy = false;
                                });
                                _loadPickupChanges();
                              } catch (_) {
                                setDialogState(() => busy = false);
                              }
                            },
                    ),
                  ],
                ),
              if (person != null && !_isManager)
                const Text('チェックの変更は主任以上のみ行えます',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      ),
    );
  }

  Widget _miniBadge(IconData icon, String label, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // 198+俊指摘(2026-08-14): 承認済み欠席期間のうち、当日が実際には欠席でない
  // (出欠編集で外した/登園した)園児には当日を欠席予定として見せない。
  // 期間が明日以降に続く場合は開始日を明日へ読み替え、当日のみなら非表示(null)。
  ({DateTime start, DateTime end, String kind})? _displayAbsencePeriod(DailyBoardRow row) {
    final p = _absenceByChild[row.childId];
    if (p == null) return null;
    if (effectiveBoardStatus(row) == 'absent') return p;
    final tomorrow = DateTime(_businessDate.year, _businessDate.month, _businessDate.day)
        .add(const Duration(days: 1));
    final endDay = DateTime(p.end.year, p.end.month, p.end.day);
    if (endDay.isBefore(tomorrow)) return null;
    final startDay = DateTime(p.start.year, p.start.month, p.start.day);
    return (start: startDay.isBefore(tomorrow) ? tomorrow : startDay, end: p.end, kind: p.kind);
  }

  // 198: 承認済み欠席(期間)の小バッジ。期間/単日を短く表示。
  // 俊指示(2026-08-14): 本一覧に出るのは「予告」(当日が欠席でない園児)のみのためグレーで控えめに。
  // 欠席当日の強調(赤)は欠席児童一覧側の種別チップ・状態チップが担う。
  Widget _miniAbsenceBadge(({DateTime start, DateTime end, String kind}) p) {
    String md(DateTime d) => '${d.month}/${d.day}';
    final kindLabel = p.kind == 'sick_absence' ? '病欠' : p.kind == 'personal_absence' ? '都合欠' : '欠席';
    final sameDay = p.start.year == p.end.year && p.start.month == p.end.month && p.start.day == p.end.day;
    final range = sameDay ? md(p.start) : '${md(p.start)}〜${md(p.end)}';
    return _miniBadge(Icons.event_busy_rounded, '$range 欠席予定($kindLabel)', AppColors.textSecondary);
  }

  // 俊指示(2026-08-14): 欠席児童一覧(クラス別)。本一覧から外した欠席児をまとめて表示し、
  // 期間・種別・保護者からの連絡に加えて 出欠編集/出席に戻す をその場で操作できるようにする。
  Widget _absentSection(List<DailyBoardRow> absent) {
    String md(DateTime d) => '${d.month}/${d.day}';
    final groups = <String, List<DailyBoardRow>>{};
    for (final r in absent) {
      (groups[r.className] ??= []).add(r);
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('欠席児童一覧 (${absent.length}名)',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            for (final entry in groups.entries) ...[
              const SizedBox(height: 10),
              Text(entry.key,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              for (final row in entry.value)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 180,
                        child: Text(row.nameLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.punchClockOut.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          row.attendanceKind == 'sick_absence'
                              ? '病欠'
                              : row.attendanceKind == 'personal_absence'
                                  ? '都合欠'
                                  : '欠席',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.punchClockOut),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 130,
                        child: Text(
                          _absenceByChild[row.childId] != null
                              ? '${md(_absenceByChild[row.childId]!.start)}〜${md(_absenceByChild[row.childId]!.end)}'
                              : '本日',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                      // 206+俊指示: 欠席児童一覧でも感染症の内容(病名+書類状態)を残す
                      for (final ic in _infectionByChild[row.childId] ?? const [])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.punchClockOut.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '感染症: ${ic.diseaseName ?? ''}'
                              '${ic.requiredDocument == 'opinion_letter' ? ' 許可書' : ic.requiredDocument == 'return_form' ? ' 登園届' : ''}'
                              '${ic.documentState == 'required_not_submitted' ? '待ち' : ic.documentState == 'submitted_electronically' ? '提出済み' : ic.documentState == 'received_on_paper' ? '紙受領済み' : ''}',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.punchClockOut),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          _absenceCommentByChild[row.childId] ?? '—',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _actionIcon(Icons.edit_calendar_rounded, '出欠編集', AppColors.warmOrange,
                          () => _openAttendanceEdit(row)),
                      _actionIcon(Icons.undo_rounded, '出席に戻す', AppColors.leafGreen,
                          () => _toggleAbsence(row)),
                    ],
                  ),
                ),
            ],
          ],
        ),
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
        officeId: _officeId,
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
    _loadMedication();
    _loadPickupChanges();
  }

  // K5(iii)/Phase A: 園児行から当日の連絡帳(園側 日誌・連絡帳)へ。既存詳細画面を再利用。
  Future<void> _openContact(DailyBoardRow row) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DailyContactDetailScreen(
        service: widget.service,
        officeId: _officeId,
        childId: row.childId,
        childNameLabel: row.nameLabel,
        businessDate: _businessDate,
        isManager: _isManager,
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
        isManager: _isManager,
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
        officeId: _officeId,
        businessDate: _businessDate,
      ),
    ));
  }

  // 健康チェック(6タブ: 検温/排便/ミルク/おやつ/昼食)へ。199 UI実装で準備中タイルを結線。
  void _openHealthCheck() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TemperatureScreen(
        service: widget.service,
        officeId: _officeId,
        businessDate: _businessDate,
        isManager: _isManager,
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
          officeId: _officeId,
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
      ),
      body: Column(
        children: [
          // 2段目: 1行固定(俊指示)。左=クラス・天気(1行表示・右の一括群に干渉しない可変幅)、右寄せ=連絡帳一括。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  child: _ClassFilterBar(
                    classes: _classes,
                    selectedClassId: _selectedClassId,
                    onChanged: _onClassChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: _WeatherBar(weather: _weather, loaded: _weatherLoaded, onTap: _editWeather),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _bulkGroup(),
              ],
            ),
          ),
          if (_napMissing.isNotEmpty) _NapMissingBanner(missing: _napMissing),
          // 3段目(俊指示の並び): 本日/日付/在籍〜欠席/出席簿/家庭での様子/健康チェック。
          // 1行固定(溢れは横スクロール)。食事チェックは健康チェックへ統合予定のためタイル廃止。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                // 配置バランス(俊指示): 本日・日付=左寄せ / 在籍〜欠席=中央寄せ / タイル3枚=右寄せ。
                // 中央のサマリーは幅不足時に FittedBox で縮小し1行を維持する。
                child: Row(
                  children: [
                    _quickTile(Icons.today_rounded, '本日', AppColors.skyBlue,
                        onTap: () => _onDateChanged(DateTime.now())),
                    const SizedBox(width: 4),
                    BusinessDateAction(date: _businessDate, onChanged: _onDateChanged),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _SummaryInline(
                            summary: _summary,
                            infectionAbsent: _allRows
                                .where((r) =>
                                    (_selectedClassId == null || r.classId == _selectedClassId) &&
                                    effectiveBoardStatus(r) == 'absent' &&
                                    (_infectionByChild[r.childId]?.isNotEmpty ?? false))
                                .length,
                          ),
                        ),
                      ),
                    ),
                    _quickTile(Icons.fact_check_rounded, '出席簿', AppColors.skyBlue, current: true),
                    const SizedBox(width: 8),
                    _quickTile(Icons.family_restroom_rounded, '家庭での様子', AppColors.leafGreen,
                        onTap: _openFamilyReports),
                    const SizedBox(width: 8),
                    _quickTile(Icons.thermostat_rounded, '健康チェック', AppColors.punchClockOut, onTap: _openHealthCheck),
                  ],
                ),
              ),
            ),
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
                  // 俊指示(2026-08-14): 欠席園児は本一覧から外し、下部の「欠席児童一覧」に
                  // クラス別でまとめる(admin_webと同構成)。
                  final present = rows.where((r) => effectiveBoardStatus(r) != 'absent').toList();
                  final absent = rows.where((r) => effectiveBoardStatus(r) == 'absent').toList();
                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: present.length + (absent.isEmpty ? 0 : 1),
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == present.length) return _absentSection(absent);
                      final row = present[index];
                      // 60/40レイアウト: 左=氏名/クラス+登降園タイムバー(約60%)、右=状態/操作/バッジ(約40%)。
                      return Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          onTap: () => _openChildDetail(row),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 左 約60%: 氏名/クラス + タイムバー
                                Expanded(
                                  flex: 6,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(row.nameLabel,
                                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                                overflow: TextOverflow.ellipsis),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(row.className, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      _AttendanceTimeBar(row: row),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // 右 約40%: 状態チップ + 操作アイコン + 補足バッジ + 連絡帳公開
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 2,
                                        runSpacing: 0,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          _StatusChip(status: effectiveBoardStatus(row)),
                                          _actionIcon(Icons.menu_book_rounded, '日誌・連絡帳', AppColors.skyBlue, () => _openContact(row)),
                                          _actionIcon(Icons.edit_calendar_rounded, '出欠編集', AppColors.warmOrange, () => _openAttendanceEdit(row)),
                                          _actionIcon(
                                            row.status == 'absent' ? Icons.undo_rounded : Icons.event_busy_rounded,
                                            row.status == 'absent' ? '出席に戻す' : '欠席にする',
                                            row.status == 'absent' ? AppColors.leafGreen : AppColors.punchClockOut,
                                            () => _toggleAbsence(row),
                                          ),
                                        ],
                                      ),
                                      // 登園・お迎え時間バッジ。氏名・続柄は連絡帳から廃止(申請・連絡に一本化)
                                      // したため、氏名は旧データがある場合のみ表示。時刻はtime('HH:MM:SS')をHH:MMへ整形。
                                      if (row.hasPickupChange || row.pickupTimeFrom != null || row.pickupTimeTo != null)
                                        _miniBadge(
                                            Icons.person_pin_circle_rounded,
                                            ('${row.hasPickupChange ? 'お迎え変更: ${row.pickupPersonName ?? ''}${row.pickupPersonRelationship != null && row.pickupPersonRelationship!.isNotEmpty ? '(${row.pickupPersonRelationship})' : ''}' : ''}'
                                                    '${row.pickupTimeFrom != null ? ' 登園${_hm5(row.pickupTimeFrom)}' : ''}${row.pickupTimeTo != null ? ' お迎え${_hm5(row.pickupTimeTo)}' : ''}')
                                                .trim(),
                                            AppColors.warmOrange),
                                      if (row.onTherapyOuting)
                                        _miniBadge(Icons.directions_walk_rounded,
                                            '療育外出中'
                                            '${row.therapyOutAt != null ? '(${row.therapyOutAt!.toLocal().hour.toString().padLeft(2, '0')}:${row.therapyOutAt!.toLocal().minute.toString().padLeft(2, '0')})' : ''}',
                                            const Color(0xFF7A5FC0)),
                                      if (_displayAbsencePeriod(row) != null)
                                        _miniAbsenceBadge(_displayAbsencePeriod(row)!),
                                      // 承認済み 遅刻/早退(俊指示 2026-08-14: 欠席と同様にボードで見えるように)
                                      for (final tc in _timeChangeByChild[row.childId] ?? const [])
                                        _miniBadge(
                                            tc.type == 'tardiness' ? Icons.schedule_rounded : Icons.directions_run_rounded,
                                            '${tc.type == 'tardiness' ? '遅刻予定' : '早退予定'}'
                                            '${tc.time != null ? ' ${tc.time}' : ''}'
                                            '${tc.reason != null && tc.reason!.isNotEmpty ? '(${tc.reason})' : ''}',
                                            AppColors.warmOrange),
                                      // 202: 承認済みお迎え変更(申請・連絡由来)。複数申請はバッジを重ねて表示。
                                      for (final pc in _pickupChangeByChild[row.childId] ?? const [])
                                        _pickupChangeBadge(row, pc),
                                      // 206: 感染症案件バッジ(進行中のみ)。書類待ち=赤/提出・受領済み=緑。
                                      for (final ic in _infectionByChild[row.childId] ?? const [])
                                        _miniBadge(
                                            Icons.medical_information_rounded,
                                            '感染症: ${ic.diseaseName ?? ''}'
                                            '${ic.requiredDocument == 'opinion_letter' ? ' 許可書' : ic.requiredDocument == 'return_form' ? ' 登園届' : ''}'
                                            '${ic.documentState == 'required_not_submitted' ? '待ち' : ic.documentState == 'submitted_electronically' ? '提出済み' : ic.documentState == 'received_on_paper' ? '紙受領済み' : ''}',
                                            ic.documentState == 'required_not_submitted'
                                                ? AppColors.punchClockOut
                                                : AppColors.leafGreen),
                                      // 201: 服薬バッジ。解熱剤を含む場合は赤警告。タップで種類と様子を表示。
                                      if (_medicationByChild[row.childId] != null)
                                        _medicationBadge(row, _medicationByChild[row.childId]!),
                                      _ContactPublishRow(
                                        row: row,
                                        onSchedule17: () => _scheduleContacts([row.contactId!], hour: 17, minute: 0),
                                        onPickTime: () => _pickAndSchedule([row.contactId!]),
                                        onPublishNow: () => _publishContactsNow([row.contactId!]),
                                        onCancel: () => _cancelContacts([row.contactId!]),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
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
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

/// 在籍登園状況サマリー(在籍/登園予定/出席/登園中/欠席)のインライン表示。数字はRPC集計のまま。
/// クイックリンク・連絡帳一括と同じ帯(Wrap)に置くため、外枠(Card)は持たない小型Row。
class _SummaryInline extends StatelessWidget {
  const _SummaryInline({required this.summary, this.infectionAbsent});

  final DailyBoardSummary? summary;
  // 欠席のうち感染症案件のある人数(206・俊指示 2026-08-14)。クライアント算出。
  final int? infectionAbsent;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final items = <_SummaryItem>[
      _SummaryItem('在籍', s?.enrolled, AppColors.textPrimary),
      _SummaryItem('登園予定', s?.expected, AppColors.skyBlue),
      _SummaryItem('出席', s?.attended, AppColors.leafGreen),
      _SummaryItem('登園中', s?.presentNow, AppColors.leafGreen),
      _SummaryItem('欠席', s?.absent, AppColors.punchClockOut),
      _SummaryItem('感染症', infectionAbsent, AppColors.punchClockOut),
    ];
    // 項目の間に縦の区切り線を入れて視認性を上げる(俊指示)。
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (i > 0) {
        children.add(Container(
          width: 1,
          height: 18,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: AppColors.textSecondary.withValues(alpha: 0.30),
        ));
      }
      children.add(Text(item.label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)));
      children.add(const SizedBox(width: 4));
      children.add(Text(
        item.value?.toString() ?? '—',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: item.color),
      ));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
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

            // 始点(登園)・終点(降園)の濃色丸マーカー(俊指示)。降園済みの園児は終点の丸が付くため、
            // 誰が帰ったかを時間軸だけで視覚的に区別できる(在園中は終点マーカーなし)。
            const dotColor = Color(0xFF2F7FA6); // skyBlueより濃い青
            Widget dot(int m) {
              final cx = frac(m) * w;
              return Positioned(
                left: (cx - 5).clamp(0.0, (w - 10).clamp(0.0, double.infinity)),
                top: 3,
                width: 10,
                height: 14,
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              );
            }

            if (arr != null) children.add(dot(arr));
            if (dep != null) children.add(dot(dep));
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
