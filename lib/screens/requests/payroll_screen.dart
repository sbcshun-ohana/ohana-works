import 'package:flutter/material.dart';

import '../../models/payroll_run.dart';
import '../../services/payroll_service.dart';
import '../../theme/app_theme.dart';
import 'payroll_run_detail_screen.dart';

/// 16章〜18章 給与計算エンジン(労務管理者以上)。
/// 手動トリガーで run_payroll() を実行し、実行履歴(給与計算単位)を表示する。
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.service});

  final PayrollService service;

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  DateTime _targetMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isRunning = false;
  late Future<List<PayrollRun>> _runsFuture;

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
        title: const Text('給与計算を実行しますか?'),
        content: Text(
          '対象月 ${_targetMonth.year}/${_targetMonth.month} の月次勤怠集計(attendance_summaries)を'
          '基に全職員の給与明細を計算します。既に確定済み/振込済みの月は再計算できません。',
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
      await widget.service.runPayroll(targetMonth: _targetMonth);
      if (!mounted) return;
      setState(() => _runsFuture = widget.service.fetchRuns());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('給与計算を実行しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('実行に失敗しました: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('給与計算')),
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
            child: FutureBuilder<List<PayrollRun>>(
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
                          run.statusLabel,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PayrollRunDetailScreen(
                                run: run,
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
