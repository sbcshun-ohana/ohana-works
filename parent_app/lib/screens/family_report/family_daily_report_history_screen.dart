import 'package:flutter/material.dart';

import '../../models/family_daily_report.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 提出済みの家庭連絡帳を一覧・閲覧する(過去の記録は編集不可)。
class FamilyDailyReportHistoryScreen extends StatefulWidget {
  const FamilyDailyReportHistoryScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<FamilyDailyReportHistoryScreen> createState() => _FamilyDailyReportHistoryScreenState();
}

class _FamilyDailyReportHistoryScreenState extends State<FamilyDailyReportHistoryScreen> {
  late Future<List<FamilyDailyReport>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = widget.guardianService.fetchFamilyDailyReportHistory(widget.child.childId);
  }

  void _showDetail(FamilyDailyReport report) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_formatDate(report.businessDate), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _DetailRow(label: '体温', value: report.temperature == null ? '未入力' : '${report.temperature!.toStringAsFixed(1)}℃'),
            _DetailRow(label: '検温時刻', value: report.temperatureMeasuredAt ?? '未入力'),
            _DetailRow(label: '症状', value: (report.symptoms?.isNotEmpty ?? false) ? report.symptoms! : 'なし'),
            _DetailRow(label: '自宅での様子', value: (report.homeNotes?.isNotEmpty ?? false) ? report.homeNotes! : 'なし'),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.child.nameLabel}の記録')),
      body: FutureBuilder<List<FamilyDailyReport>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final reports = snapshot.data ?? const [];
          if (reports.isEmpty) {
            return const Center(
              child: Text('提出済みの記録はまだありません', style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _showDetail(report),
                  title: Text(_formatDate(report.businessDate)),
                  subtitle: Text(
                    report.temperature == null ? '体温未入力' : '体温 ${report.temperature!.toStringAsFixed(1)}℃',
                    style: TextStyle(color: report.hasFeverWarning ? AppColors.danger : AppColors.textSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ),
              );
            },
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}
