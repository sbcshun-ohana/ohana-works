import 'package:flutter/material.dart';

import '../../models/attendance_summary.dart';
import '../../services/attendance_summary_service.dart';
import '../../theme/app_theme.dart';
import 'attendance_summary_month_detail_screen.dart';

/// 11章/12章 月次勤怠集計エンジン(労務管理者以上)。
/// 手動トリガーで run_attendance_summary() を実行し、実行履歴を表示する。
class AttendanceSummaryScreen extends StatefulWidget {
  const AttendanceSummaryScreen({super.key, required this.service});

  final AttendanceSummaryService service;

  @override
  State<AttendanceSummaryScreen> createState() => _AttendanceSummaryScreenState();
}

class _AttendanceSummaryScreenState extends State<AttendanceSummaryScreen> {
  DateTime _targetMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isRunning = false;
  late Future<List<AttendanceSummaryRun>> _runsFuture;

  @override
  void initState() {
    super.initState();
    _runsFuture = widget.service.fetchRuns();
  }

  Future<void> _pickTargetMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetMonth,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, 1),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _targetMonth = DateTime(picked.year, picked.month, 1));
    }
  }

  Future<void> _run() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('月次勤怠集計を実行しますか?'),
        content: Text(
          '対象月 ${_targetMonth.year}/${_targetMonth.month} の出勤日数・所定/実労働時間・'
          '時間外・深夜時間・欠勤日数・遅刻早退回数を全職員分再集計します。'
          '既存の集計結果は上書きされます。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('実行')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRunning = true);
    try {
      await widget.service.runSummary(targetMonth: _targetMonth);
      if (!mounted) return;
      setState(() => _runsFuture = widget.service.fetchRuns());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('月次勤怠集計を実行しました')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('実行に失敗しました。もう一度お試しください。')),
      );
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('月次勤怠集計')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('対象月', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickTargetMonth,
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text('${_targetMonth.year}/${_targetMonth.month}'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isRunning ? null : _run,
                      icon: _isRunning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: const Text('この対象月で実行'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<AttendanceSummaryRun>>(
              future: _runsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final runs = snapshot.data ?? const [];
                if (runs.isEmpty) {
                  return const Center(child: Text('実行履歴はありません'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: runs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final run = runs[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          '対象月 ${run.targetMonth.year}/${run.targetMonth.month}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '対象職員 ${run.totalEmployees}名'
                          '${run.runByName != null ? '\n実行者: ${run.runByName}' : ''}',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        isThreeLine: run.runByName != null,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AttendanceSummaryMonthDetailScreen(
                                targetMonth: run.targetMonth,
                                service: widget.service,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
