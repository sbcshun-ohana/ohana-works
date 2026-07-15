import 'package:flutter/material.dart';

import '../../models/leave_grant_run.dart';
import '../../services/leave_grant_service.dart';
import '../../theme/app_theme.dart';

/// 15.1 有給自動付与エンジンの実行結果詳細(職員ごとの8割出勤判定内訳)。
class LeaveGrantRunDetailScreen extends StatefulWidget {
  const LeaveGrantRunDetailScreen({super.key, required this.run, required this.service});

  final LeaveGrantRun run;
  final LeaveGrantService service;

  @override
  State<LeaveGrantRunDetailScreen> createState() => _LeaveGrantRunDetailScreenState();
}

class _LeaveGrantRunDetailScreenState extends State<LeaveGrantRunDetailScreen> {
  late Future<List<LeaveGrantRunResult>> _resultsFuture;

  @override
  void initState() {
    super.initState();
    _resultsFuture = widget.service.fetchRunResults(widget.run.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('付与エンジン実行結果')),
      body: FutureBuilder<List<LeaveGrantRunResult>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snapshot.data ?? const [];
          if (results.isEmpty) {
            return const Center(child: Text('この基準日で評価対象となった職員はいません'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final result = results[index];
              final ratePercent = (result.attendanceRate * 100).toStringAsFixed(1);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              result.employeeName ?? '(不明な職員)',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          _EligibilityBadge(eligible: result.eligible),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '基準日 ${result.milestoneDate.year}/${result.milestoneDate.month}/${result.milestoneDate.day} ・ '
                        '出勤率 $ratePercent%(${result.attendedDays}/${result.prescribedDays}日)',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      if (result.eligible)
                        Text(
                          '付与 ${result.grantedDays?.toStringAsFixed(0)}日(${result.basis ?? ''})',
                          style: const TextStyle(color: AppColors.leafGreen, fontWeight: FontWeight.w600),
                        )
                      else
                        Text(
                          result.skipReason ?? '対象外',
                          style: const TextStyle(color: AppColors.warmOrange, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EligibilityBadge extends StatelessWidget {
  const _EligibilityBadge({required this.eligible});

  final bool eligible;

  @override
  Widget build(BuildContext context) {
    final color = eligible ? AppColors.leafGreen : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        eligible ? '付与' : '対象外',
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
