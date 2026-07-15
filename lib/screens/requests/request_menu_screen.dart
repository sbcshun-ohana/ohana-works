import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/attendance_summary_service.dart';
import '../../services/leave_grant_service.dart';
import '../../services/payroll_service.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';
import 'absence_request_screen.dart';
import 'attendance_summary_screen.dart';
import 'info_change_request_screen.dart';
import 'my_requests_list_screen.dart';
import 'paid_leave_auto_grant_screen.dart';
import 'paid_leave_request_screen.dart';
import 'payroll_screen.dart';
import 'request_approval_list_screen.dart';
import 'tardiness_request_screen.dart';

/// 15章/28.4 各種申請メニュー。
class RequestMenuScreen extends StatefulWidget {
  const RequestMenuScreen({super.key});

  @override
  State<RequestMenuScreen> createState() => _RequestMenuScreenState();
}

class _RequestMenuScreenState extends State<RequestMenuScreen> {
  final _service = RequestService(Supabase.instance.client);
  final _leaveGrantService = LeaveGrantService(Supabase.instance.client);
  final _attendanceSummaryService = AttendanceSummaryService(Supabase.instance.client);
  final _payrollService = PayrollService(Supabase.instance.client);
  late final Future<bool> _canApproveFuture;
  late final Future<bool> _canRunAutoGrantFuture;
  late final Future<bool> _canRunAttendanceSummaryFuture;
  late final Future<bool> _canRunPayrollFuture;

  @override
  void initState() {
    super.initState();
    _canApproveFuture = _service.canApproveRequests();
    _canRunAutoGrantFuture = _leaveGrantService.canRunAutoGrant();
    _canRunAttendanceSummaryFuture = _attendanceSummaryService.canRunSummary();
    _canRunPayrollFuture = _payrollService.canRunPayroll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('各種申請')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RequestTypeCard(
            icon: Icons.beach_access_rounded,
            color: AppColors.leafGreen,
            title: '有給休暇申請',
            subtitle: '1日・半日・時間単位で申請できます',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaidLeaveRequestScreen(service: _service),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _RequestTypeCard(
            icon: Icons.event_busy_rounded,
            color: AppColors.warmOrange,
            title: '欠勤連絡',
            subtitle: 'やむを得ない事情がある場合にご利用ください',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AbsenceRequestScreen(service: _service),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _RequestTypeCard(
            icon: Icons.schedule_rounded,
            color: AppColors.skyBlue,
            title: '遅刻・早退申請',
            subtitle: '事前申請・事後報告どちらも可能です',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TardinessRequestScreen(service: _service),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _RequestTypeCard(
            icon: Icons.edit_note_rounded,
            color: AppColors.skyBlue,
            title: '登録情報変更申請',
            subtitle: '住所・電話番号・振込先口座の変更を申請できます',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => InfoChangeRequestScreen(service: _service),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MyRequestsListScreen(service: _service),
                ),
              );
            },
            icon: const Icon(Icons.history_rounded),
            label: const Text('申請履歴を見る'),
          ),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: _canApproveFuture,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RequestApprovalListScreen(service: _service),
                    ),
                  );
                },
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('承認待ち申請(管理者)'),
              );
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: _canRunAutoGrantFuture,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PaidLeaveAutoGrantScreen(service: _leaveGrantService),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('有給自動付与(労務管理者)'),
              );
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: _canRunAttendanceSummaryFuture,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AttendanceSummaryScreen(service: _attendanceSummaryService),
                    ),
                  );
                },
                icon: const Icon(Icons.summarize_outlined),
                label: const Text('月次勤怠集計(労務管理者)'),
              );
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: _canRunPayrollFuture,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PayrollScreen(service: _payrollService),
                    ),
                  );
                },
                icon: const Icon(Icons.payments_outlined),
                label: const Text('給与計算(労務管理者)'),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RequestTypeCard extends StatelessWidget {
  const _RequestTypeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: enabled ? 0.15 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: enabled ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
