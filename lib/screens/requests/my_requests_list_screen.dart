import 'package:flutter/material.dart';

import '../../models/leave_request.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';

/// 15章/28.4 自分の申請履歴。
class MyRequestsListScreen extends StatefulWidget {
  const MyRequestsListScreen({super.key, required this.service});

  final RequestService service;

  @override
  State<MyRequestsListScreen> createState() => _MyRequestsListScreenState();
}

class _MyRequestsListScreenState extends State<MyRequestsListScreen> {
  late Future<List<AppRequest>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _requestsFuture = widget.service.fetchMyRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('申請履歴')),
      body: FutureBuilder<List<AppRequest>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final requests = snapshot.data ?? const [];
          if (requests.isEmpty) {
            return const Center(child: Text('申請はありません'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final request = requests[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            requestTypeLabel(request.requestType),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          _StatusBadge(status: request.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${request.targetDate.year}/${request.targetDate.month}/${request.targetDate.day}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      if (request.decisionReason != null &&
                          request.decisionReason!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          request.decisionReason!,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  Color get _color {
    switch (status) {
      case 'approved':
        return AppColors.leafGreen;
      case 'rejected':
        return AppColors.punchClockOut;
      case 'cancelled':
        return AppColors.textSecondary;
      default:
        return AppColors.warmOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        requestStatusLabel(status),
        style: TextStyle(color: _color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
