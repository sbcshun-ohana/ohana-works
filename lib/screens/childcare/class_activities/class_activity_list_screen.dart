import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import 'class_activity_detail_screen.dart';

/// §8 クラス活動 入力・申請・承認の一覧(施設内の全クラスの当日分)。
class ClassActivityListScreen extends StatefulWidget {
  const ClassActivityListScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.businessDate,
    required this.isManager,
  });

  final ChildcareService service;
  final String officeId;
  final DateTime businessDate;
  final bool isManager;

  @override
  State<ClassActivityListScreen> createState() => _ClassActivityListScreenState();
}

class _ClassActivityListScreenState extends State<ClassActivityListScreen> {
  late Future<List<ClassActivity>> _activitiesFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _activitiesFuture =
        widget.service.fetchClassActivitiesForOffice(widget.officeId, widget.businessDate);
  }

  Future<void> _reload() async {
    setState(_load);
    await _activitiesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 180,
        title: const Text('クラス活動'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<ClassActivity>>(
          future: _activitiesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final activities = snapshot.data ?? const [];
            if (activities.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 120), Center(child: Text('クラスがありません'))],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: activities.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final activity = activities[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(activity.className, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '担当: ${activity.assigneeName ?? "未割当"}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: _StatusChip(status: activity.status),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ClassActivityDetailScreen(
                            service: widget.service,
                            officeId: widget.officeId,
                            classId: activity.classId,
                            className: activity.className,
                            businessDate: widget.businessDate,
                            isManager: widget.isManager,
                          ),
                        ),
                      );
                      await _reload();
                    },
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
  final String? status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case 'approved':
        color = AppColors.leafGreen;
      case 'rejected':
        color = AppColors.punchClockOut;
      case 'submitted':
        color = AppColors.skyBlue;
      default:
        color = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        childcareStatusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
