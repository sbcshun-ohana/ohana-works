import 'package:flutter/material.dart';

import '../../models/leave_grant_run.dart';
import '../../services/leave_grant_service.dart';
import '../../theme/app_theme.dart';
import 'leave_grant_run_detail_screen.dart';

/// 15.1 有給自動付与エンジン(労務管理者以上)。
/// 手動トリガーで run_paid_leave_auto_grant() を実行し、実行履歴を表示する。
class PaidLeaveAutoGrantScreen extends StatefulWidget {
  const PaidLeaveAutoGrantScreen({super.key, required this.service});

  final LeaveGrantService service;

  @override
  State<PaidLeaveAutoGrantScreen> createState() => _PaidLeaveAutoGrantScreenState();
}

class _PaidLeaveAutoGrantScreenState extends State<PaidLeaveAutoGrantScreen> {
  DateTime _targetDate = DateTime.now();
  bool _isRunning = false;
  late Future<List<LeaveGrantRun>> _runsFuture;

  @override
  void initState() {
    super.initState();
    _runsFuture = widget.service.fetchRuns();
  }

  Future<void> _pickTargetDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: now.subtract(const Duration(days: 3650)),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _targetDate = picked);
    }
  }

  Future<void> _run() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('有給自動付与を実行しますか?'),
        content: Text(
          '基準日 ${_targetDate.year}/${_targetDate.month}/${_targetDate.day} 時点で全職員を評価し、'
          '8割出勤要件を満たす対象者へ有給休暇を付与します。この操作は取り消せません。',
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
      await widget.service.runAutoGrant(targetDate: _targetDate);
      if (!mounted) return;
      setState(() => _runsFuture = widget.service.fetchRuns());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('有給自動付与を実行しました')),
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
      appBar: AppBar(title: const Text('有給自動付与')),
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
                    const Text('基準日', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickTargetDate,
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text('${_targetDate.year}/${_targetDate.month}/${_targetDate.day}'),
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
                      label: const Text('この基準日で実行'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<LeaveGrantRun>>(
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
                          '基準日 ${run.targetDate.year}/${run.targetDate.month}/${run.targetDate.day}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '評価 ${run.totalEvaluated}件 / 付与 ${run.totalGranted}件 / 未達 ${run.totalSkipped}件'
                          '${run.runByName != null ? '\n実行者: ${run.runByName}' : ''}',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                        isThreeLine: run.runByName != null,
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LeaveGrantRunDetailScreen(
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
