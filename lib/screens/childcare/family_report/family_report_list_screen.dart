import 'package:flutter/material.dart';

import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/business_date_action.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// 家庭での様子 一覧(Phase A・UI-only)。保護者が朝提出した家庭連絡帳を全園児分まとめて表示。
/// 朝の受け入れ時に一括把握する用途。DB変更なし(既存RLSの直接selectを利用)。
class FamilyReportListScreen extends StatefulWidget {
  const FamilyReportListScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<FamilyReportListScreen> createState() => _FamilyReportListScreenState();
}

class _FamilyReportListScreenState extends State<FamilyReportListScreen> {
  late DateTime _businessDate = widget.businessDate;
  late Future<List<FamilyReportListItem>> _future;
  // K8: 園側検温の最新値(childId→(temp,time))。188の fetch_child_latest_temperatures_for_office。
  Map<String, ({double temperature, String measuredAt})> _latestTemps = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = widget.service.fetchFamilyDailyReportsForOffice(widget.officeId, _businessDate);
    widget.service
        .fetchChildLatestTemperaturesForOffice(widget.officeId, _businessDate)
        .then((m) {
      if (mounted) setState(() => _latestTemps = m);
    }).catchError((_) {
      if (mounted) setState(() => _latestTemps = const {});
    });
  }

  String _officeTempText(String childId) {
    final t = _latestTemps[childId];
    return t == null ? '—' : '${t.temperature}℃${t.measuredAt.length >= 5 ? '\n(${t.measuredAt.substring(0, 5)})' : ''}';
  }

  Future<void> _reload() async {
    setState(_load);
    await _future;
  }

  void _onDateChanged(DateTime d) {
    setState(() {
      _businessDate = d;
      _load();
    });
  }

  static const _mood = {'good': '良い', 'normal': '普通', 'bad': '悪い'};
  static const _bowel = {'normal': '普通', 'soft': '軟便', 'hard': '硬い', 'small': '少量'};

  String _hm(String? t) => (t == null || t.length < 5) ? (t ?? '') : t.substring(0, 5);
  String _moodText(String? n, String? m) => '夜:${_mood[n] ?? '—'} / 朝:${_mood[m] ?? '—'}';
  String _bowelOne(int? c, String? cond) => c == null ? '—' : '$c回${cond != null ? '(${_bowel[cond] ?? cond})' : ''}';
  String _bowelText(FamilyDailyReportSummary r) =>
      '夜:${_bowelOne(r.nightBowelCount, r.nightBowelCondition)} 朝:${_bowelOne(r.morningBowelCount, r.morningBowelCondition)}';
  String _sleepText(FamilyDailyReportSummary r) =>
      (r.sleepStartAt == null && r.sleepEndAt == null) ? '—' : '${_hm(r.sleepStartAt) == '' ? '--' : _hm(r.sleepStartAt)}〜${_hm(r.sleepEndAt) == '' ? '--' : _hm(r.sleepEndAt)}';
  String _mealText(FamilyDailyReportSummary r) {
    final parts = <String>[];
    if ((r.dinnerContent ?? '').isNotEmpty) parts.add('夕: ${r.dinnerContent}');
    if ((r.breakfastContent ?? '').isNotEmpty) parts.add('朝: ${r.breakfastContent}');
    return parts.isEmpty ? '—' : parts.join('\n');
  }

  String _tempText(FamilyDailyReportSummary r) =>
      r.temperature == null ? '—' : '${r.temperature}℃${r.temperatureMeasuredAt != null ? '\n(${_hm(r.temperatureMeasuredAt)})' : ''}';
  String _pickupText(FamilyDailyReportSummary r) => (r.pickupPersonName == null || r.pickupPersonName!.isEmpty)
      ? '—'
      : '${r.pickupPersonName}${r.pickupTimeFrom != null || r.pickupTimeTo != null ? '\n${r.pickupTimeFrom != null ? '登園${_hm(r.pickupTimeFrom)} ' : ''}${r.pickupTimeTo != null ? 'お迎え${_hm(r.pickupTimeTo)}' : ''}' : ''}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        toolbarHeight: 48,
        titleSpacing: 0,
        title: const Text('家庭での様子', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [BusinessDateAction(date: _businessDate, onChanged: _onDateChanged)],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<FamilyReportListItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                const SizedBox(height: 100),
                Center(child: Text('取得に失敗しました: ${snap.error}', style: const TextStyle(color: AppColors.punchClockOut))),
              ]);
            }
            final items = snap.data ?? const <FamilyReportListItem>[];
            if (items.isEmpty) {
              return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                SizedBox(height: 120),
                Center(child: Text('提出済みの家庭連絡帳がありません')),
              ]);
            }
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headerRow(),
                    for (final it in items) _dataRow(it),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 列幅(共通)。名前/機嫌/排便/睡眠/食事/検温/迎え/子どもの様子。
  static const _w = {
    'name': 120.0,
    'mood': 110.0,
    'bowel': 150.0,
    'sleep': 110.0,
    'meal': 220.0,
    'temp': 90.0,
    'otemp': 96.0,
    'pickup': 120.0,
    'notes': 300.0,
  };

  Widget _headerRow() {
    Widget h(String t, double w) => SizedBox(
          width: w,
          child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x22000000)))),
      child: Row(children: [
        h('名前', _w['name']!),
        h('機嫌', _w['mood']!),
        h('排便', _w['bowel']!),
        h('睡眠', _w['sleep']!),
        h('食事', _w['meal']!),
        h('検温(家庭)', _w['temp']!),
        h('検温(園・最新)', _w['otemp']!),
        h('迎え', _w['pickup']!),
        h('子どもの様子', _w['notes']!),
      ]),
    );
  }

  Widget _dataRow(FamilyReportListItem it) {
    final r = it.report;
    Widget c(String t, double w, {bool strong = false}) => SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(t, style: TextStyle(fontSize: 12, fontWeight: strong ? FontWeight.w700 : FontWeight.w400, height: 1.3)),
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x11000000)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          c(it.nameLabel, _w['name']!, strong: true),
          c(_moodText(r.nightMood, r.morningMood), _w['mood']!),
          c(_bowelText(r), _w['bowel']!),
          c(_sleepText(r), _w['sleep']!),
          c(_mealText(r), _w['meal']!),
          c(_tempText(r), _w['temp']!),
          c(_officeTempText(it.childId), _w['otemp']!),
          c(_pickupText(r), _w['pickup']!),
          c(r.homeNotes ?? '—', _w['notes']!),
        ],
      ),
    );
  }
}
