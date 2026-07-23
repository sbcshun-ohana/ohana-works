import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../family_daily_report_summary_view.dart';

/// 保護者アプリ・後続保育機能 Phase A: デイリーボード(iPad中心)。
/// 登降園は保護者アプリ・キオスク端末など複数端末から記録されるため、Realtimeで即時反映する。
class DailyBoardScreen extends StatefulWidget {
  const DailyBoardScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;

  @override
  State<DailyBoardScreen> createState() => _DailyBoardScreenState();
}

class _DailyBoardScreenState extends State<DailyBoardScreen> {
  late Future<List<DailyBoardRow>> _rowsFuture;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = widget.service.watchDailyChildStatus(widget.officeId, () {
      if (mounted) setState(_load);
    });
  }

  @override
  void dispose() {
    if (_channel != null) Supabase.instance.client.removeChannel(_channel!);
    super.dispose();
  }

  void _load() {
    _rowsFuture = widget.service.fetchDailyBoardForOffice(widget.officeId, widget.businessDate);
  }

  Future<void> _reload() async {
    setState(_load);
    await _rowsFuture;
  }

  Future<void> _showFamilyDailyReport(DailyBoardRow row) async {
    final report = await widget.service.fetchFamilyDailyReportForStaff(row.childId, widget.businessDate);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${row.nameLabel}の家庭連絡帳', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              FamilyDailyReportSummaryView(report: report),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('デイリーボード')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<DailyBoardRow>>(
          future: _rowsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 120), Center(child: Text('在籍園児がいません'))],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final row = rows[index];
                return Card(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        onTap: () => _showFamilyDailyReport(row),
                        title: Text(row.nameLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(row.className, style: const TextStyle(color: AppColors.textSecondary)),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _StatusChip(status: row.status),
                            if (row.lastEventAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${row.lastEventAt!.hour.toString().padLeft(2, '0')}:'
                                  '${row.lastEventAt!.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (row.hasPickupChange)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.warmOrange.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person_pin_circle_rounded, size: 18, color: AppColors.warmOrange),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'お迎え変更あり: ${row.pickupPersonName}'
                                  '${row.pickupTimeFrom != null ? '(${row.pickupTimeFrom}〜${row.pickupTimeTo})' : ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
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
