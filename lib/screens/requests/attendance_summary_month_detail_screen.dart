import 'package:flutter/material.dart';

import '../../models/attendance_summary.dart';
import '../../services/attendance_summary_service.dart';
import '../../theme/app_theme.dart';

/// 11章/12章 月次勤怠集計の職員ごとの内訳。
class AttendanceSummaryMonthDetailScreen extends StatefulWidget {
  const AttendanceSummaryMonthDetailScreen({
    super.key,
    required this.targetMonth,
    required this.service,
  });

  final DateTime targetMonth;
  final AttendanceSummaryService service;

  @override
  State<AttendanceSummaryMonthDetailScreen> createState() =>
      _AttendanceSummaryMonthDetailScreenState();
}

class _AttendanceSummaryMonthDetailScreenState extends State<AttendanceSummaryMonthDetailScreen> {
  late Future<List<AttendanceSummary>> _summariesFuture;

  @override
  void initState() {
    super.initState();
    _summariesFuture = widget.service.fetchSummariesForMonth(widget.targetMonth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('勤怠集計 ${widget.targetMonth.year}/${widget.targetMonth.month}'),
      ),
      body: FutureBuilder<List<AttendanceSummary>>(
        future: _summariesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final summaries = snapshot.data ?? const [];
          if (summaries.isEmpty) {
            return const Center(child: Text('この対象月の集計結果はありません'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: summaries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final s = summaries[index];
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
                              s.employeeName ?? '(不明な職員)',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          _SystemBadge(workTimeSystem: s.workTimeSystem),
                        ],
                      ),
                      if (s.officeName != null) ...[
                        const SizedBox(height: 2),
                        Text(s.officeName!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                      const Divider(height: 20),
                      _MetricRow(label: '出勤日数', value: '${s.attendanceDays}日'),
                      _MetricRow(label: '所定労働時間', value: formatMinutes(s.prescribedMinutes)),
                      _MetricRow(label: '実労働時間', value: formatMinutes(s.actualWorkedMinutes)),
                      _MetricRow(
                        label: '時間外(日/週/月)',
                        value: '${formatMinutes(s.overtimeMinutes)}'
                            '(${formatMinutes(s.dailyOvertimeMinutes)}/'
                            '${formatMinutes(s.weeklyOvertimeMinutes)}/'
                            '${formatMinutes(s.monthlyOvertimeMinutes)})',
                      ),
                      if (s.overtimeOver60hMinutes > 0)
                        _MetricRow(
                          label: '月60h超過分',
                          value: formatMinutes(s.overtimeOver60hMinutes),
                          valueColor: AppColors.punchClockOut,
                        ),
                      _MetricRow(label: '深夜時間', value: formatMinutes(s.lateNightMinutes)),
                      _MetricRow(label: '法定休日時間', value: formatMinutes(s.statutoryHolidayMinutes)),
                      _MetricRow(label: '欠勤日数', value: '${s.absenceDays}日'),
                      _MetricRow(label: '遅刻早退回数', value: '${s.tardinessEarlyLeaveCount}回'),
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

class _SystemBadge extends StatelessWidget {
  const _SystemBadge({required this.workTimeSystem});

  final String workTimeSystem;

  @override
  Widget build(BuildContext context) {
    final isDeformed = workTimeSystem == '1ヶ月単位変形労働時間制';
    final color = isDeformed ? AppColors.skyBlue : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        workTimeSystem,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
