import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';

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
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
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
