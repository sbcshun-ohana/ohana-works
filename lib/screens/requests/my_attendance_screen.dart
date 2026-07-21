import 'dart:io';

import 'package:excel/excel.dart' as xlsx;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/my_attendance.dart';
import '../../services/my_data_service.dart';
import '../../theme/app_theme.dart';

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

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
  bool _isExporting = false;

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

  Future<void> _exportExcel(List<MyAttendanceDay> days) async {
    if (days.isEmpty) return;
    setState(() => _isExporting = true);
    try {
      final byOffice = _groupByOffice(days);
      final workbook = xlsx.Excel.createExcel();
      final defaultSheetName = workbook.getDefaultSheet();

      for (final entry in byOffice.entries) {
        // 施設ごとに別シート(全体を合算した1枚のシートは作らない)。
        final sheet = workbook[entry.key];
        sheet.appendRow([
          xlsx.TextCellValue('日付'),
          xlsx.TextCellValue('曜日'),
          xlsx.TextCellValue('出勤(実打刻)'),
          xlsx.TextCellValue('出勤(承認済み)'),
          xlsx.TextCellValue('退勤(実打刻)'),
          xlsx.TextCellValue('退勤(承認済み)'),
          xlsx.TextCellValue('休憩(分)'),
          xlsx.TextCellValue('勤務区分'),
          xlsx.TextCellValue('アラート'),
        ]);
        for (final day in entry.value) {
          sheet.appendRow([
            xlsx.TextCellValue('${day.workDate.month}/${day.workDate.day}'),
            xlsx.TextCellValue(_weekdayLabels[day.workDate.weekday - 1]),
            xlsx.TextCellValue(_formatTime(day.actualClockInAt)),
            xlsx.TextCellValue(_formatTime(day.approvedWorkStartAt)),
            xlsx.TextCellValue(_formatTime(day.actualClockOutAt)),
            xlsx.TextCellValue(_formatTime(day.approvedWorkEndAt)),
            xlsx.TextCellValue(day.approvedBreakMinutes?.toString() ?? '--'),
            xlsx.TextCellValue(day.shiftType ?? '--'),
            xlsx.TextCellValue(day.alertCodes.join('、')),
          ]);
        }
      }
      if (defaultSheetName != null && !byOffice.containsKey(defaultSheetName)) {
        workbook.delete(defaultSheetName);
      }

      final bytes = workbook.save();
      if (bytes == null) throw Exception('Excel生成に失敗しました');

      final directory = await getTemporaryDirectory();
      final fileName = '勤怠_${_targetMonth.year}年${_targetMonth.month}月.xlsx';
      final file = File('${directory.path}/$fileName')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

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
      body: FutureBuilder<List<MyAttendanceDay>>(
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
          return Column(
            children: [
              Expanded(
                child: ListView(
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
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: _isExporting ? null : () => _exportExcel(days),
                    icon: _isExporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.ios_share_rounded),
                    label: Text(_isExporting ? '出力中…' : 'Excelで共有(施設別シート)'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
