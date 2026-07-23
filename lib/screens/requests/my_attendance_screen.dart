import 'package:flutter/material.dart';

import '../../models/my_attendance.dart';
import '../../services/my_data_service.dart';
import '../../theme/app_theme.dart';

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

enum _ViewMode { daily, summary }

/// 職員1名・1施設分の月間実績。日別データ(MyAttendanceDay)から都度集計する。
class _OfficeMonthlyTotals {
  const _OfficeMonthlyTotals({
    required this.officeName,
    required this.attendanceDays,
    required this.workedMinutes,
    required this.alertCount,
  });

  final String officeName;
  final int attendanceDays;
  final int workedMinutes;
  final int alertCount;
}

/// Phase1 A-4: 自分の勤怠(月間・施設別)。daily_attendances(生データ)から
/// 都度組み立てるfetch_my_attendance RPCを使うため、月次集計が未実行の月でも
/// 正しく表示される。
class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({super.key, required this.service});

  final MyDataService service;

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  DateTime _targetMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late Future<List<MyAttendanceDay>> _daysFuture;
  _ViewMode _viewMode = _ViewMode.daily;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final monthStart = DateTime(_targetMonth.year, _targetMonth.month, 1);
    final monthEnd = DateTime(_targetMonth.year, _targetMonth.month + 1, 0);
    _daysFuture = widget.service.fetchMyAttendance(monthStart: monthStart, monthEnd: monthEnd);
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetMonth,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year, now.month, 1),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() {
        _targetMonth = DateTime(picked.year, picked.month, 1);
        _load();
      });
    }
  }

  String _formatTime(DateTime? t) =>
      t == null ? '--:--' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Map<String, List<MyAttendanceDay>> _groupByOffice(List<MyAttendanceDay> days) {
    final byOffice = <String, List<MyAttendanceDay>>{};
    for (final day in days) {
      byOffice.putIfAbsent(day.officeName, () => []).add(day);
    }
    return byOffice;
  }

  /// 1日分の実労働時間(分)。出勤・退勤それぞれ承認済み時刻を優先し、
  /// 無ければ実打刻時刻で代用する(片方だけ承認済みの状態も許容する)。
  /// 日付をまたぐ夜勤で退勤時刻が出勤時刻より前になるケース(例:
  /// 承認側が当日日付のまま登録されている場合)は、退勤を翌日とみなして
  /// 24時間分繰り上げる。
  int _workedMinutes(MyAttendanceDay day) {
    final start = day.approvedWorkStartAt ?? day.actualClockInAt;
    final end = day.approvedWorkEndAt ?? day.actualClockOutAt;
    if (start == null || end == null) return 0;
    var minutes = end.difference(start).inMinutes;
    if (minutes < 0) minutes += const Duration(days: 1).inMinutes;
    final breakMinutes = day.approvedBreakMinutes ?? 0;
    return (minutes - breakMinutes).clamp(0, 1 << 30);
  }

  _OfficeMonthlyTotals _summarizeOffice(String officeName, List<MyAttendanceDay> days) {
    var attendanceDays = 0;
    var workedMinutes = 0;
    var alertCount = 0;
    for (final day in days) {
      if (day.approvedWorkStartAt != null || day.actualClockInAt != null) attendanceDays++;
      workedMinutes += _workedMinutes(day);
      alertCount += day.alertCodes.length;
    }
    return _OfficeMonthlyTotals(
      officeName: officeName,
      attendanceDays: attendanceDays,
      workedMinutes: workedMinutes,
      alertCount: alertCount,
    );
  }

  String _formatHoursMinutes(int minutes) => '${minutes ~/ 60}時間${minutes % 60}分';

  void _showDetail(MyAttendanceDay day) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.workDate.year}/${day.workDate.month}/${day.workDate.day}(${day.officeName})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _DetailRow(label: '出勤(実打刻)', value: _formatTime(day.actualClockInAt)),
            _DetailRow(label: '出勤(承認済み)', value: _formatTime(day.approvedWorkStartAt)),
            _DetailRow(label: '退勤(実打刻)', value: _formatTime(day.actualClockOutAt)),
            _DetailRow(label: '退勤(承認済み)', value: _formatTime(day.approvedWorkEndAt)),
            _DetailRow(label: '休憩開始', value: _formatTime(day.actualBreakStartAt)),
            _DetailRow(label: '休憩終了', value: _formatTime(day.actualBreakEndAt)),
            _DetailRow(
              label: '承認済み休憩時間',
              value: day.approvedBreakMinutes == null ? '--' : '${day.approvedBreakMinutes}分',
            ),
            _DetailRow(label: '勤務区分', value: day.shiftType ?? '--'),
            if (day.alertCodes.isNotEmpty) _DetailRow(label: 'アラート', value: day.alertCodes.join('、')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自分の勤怠'),
        actions: [
          TextButton(
            onPressed: _pickMonth,
            child: Text(
              '${_targetMonth.year}/${_targetMonth.month}',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SegmentedButton<_ViewMode>(
              segments: const [
                ButtonSegment(value: _ViewMode.daily, label: Text('日別'), icon: Icon(Icons.view_agenda_rounded)),
                ButtonSegment(value: _ViewMode.summary, label: Text('月間サマリー'), icon: Icon(Icons.summarize_rounded)),
              ],
              selected: {_viewMode},
              onSelectionChanged: (selection) => setState(() => _viewMode = selection.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MyAttendanceDay>>(
              future: _daysFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final days = snapshot.data ?? const [];
                if (days.isEmpty) {
                  return const Center(
                    child: Text('この月の勤怠記録はまだありません', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                final byOffice = _groupByOffice(days);
                return _viewMode == _ViewMode.daily
                    ? _buildDailyList(byOffice)
                    : _buildMonthlySummary(days, byOffice);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyList(Map<String, List<MyAttendanceDay>> byOffice) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in byOffice.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          ...entry.value.map(
            (day) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _showDetail(day),
                title: Text('${day.workDate.month}/${day.workDate.day}(${_weekdayLabels[day.workDate.weekday - 1]})'),
                subtitle: Text(
                  '出勤 ${_formatTime(day.approvedWorkStartAt ?? day.actualClockInAt)}'
                  ' 〜 退勤 ${_formatTime(day.approvedWorkEndAt ?? day.actualClockOutAt)}',
                ),
                trailing: day.alertCodes.isNotEmpty
                    ? const Icon(Icons.warning_amber_rounded, color: AppColors.warmOrange)
                    : const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMonthlySummary(List<MyAttendanceDay> days, Map<String, List<MyAttendanceDay>> byOffice) {
    final now = DateTime.now();
    final isInProgress = _targetMonth.year == now.year && _targetMonth.month == now.month;
    final officeTotals = byOffice.entries.map((e) => _summarizeOffice(e.key, e.value)).toList();
    final overall = _summarizeOffice('全体', days);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isInProgress)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warmOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '※ 今月の実績は集計中です。月末に最終確定します。',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('全体', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 12),
                _DetailRow(label: '出勤日数', value: '${overall.attendanceDays}日'),
                _DetailRow(label: '実労働時間合計', value: _formatHoursMinutes(overall.workedMinutes)),
                _DetailRow(label: 'アラート件数', value: '${overall.alertCount}件'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('施設別内訳', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        for (final office in officeTotals)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(office.officeName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _DetailRow(label: '出勤日数', value: '${office.attendanceDays}日'),
                  _DetailRow(label: '実労働時間合計', value: _formatHoursMinutes(office.workedMinutes)),
                  _DetailRow(label: 'アラート件数', value: '${office.alertCount}件'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
