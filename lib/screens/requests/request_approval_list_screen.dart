import 'package:flutter/material.dart';

import '../../models/leave_request.dart';
import '../../services/request_service.dart';
import '../../theme/app_theme.dart';
import 'request_approval_detail_screen.dart';

/// 15.4/28.4 管理者モード: 承認待ち申請一覧。
class RequestApprovalListScreen extends StatefulWidget {
  const RequestApprovalListScreen({super.key, required this.service});

  final RequestService service;

  @override
  State<RequestApprovalListScreen> createState() => _RequestApprovalListScreenState();
}

class _RequestApprovalListScreenState extends State<RequestApprovalListScreen> {
  late Future<List<AppRequest>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _requestsFuture = widget.service.fetchPendingRequests();
  }

  Future<void> _reload() async {
    setState(_load);
    await _requestsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('承認待ち申請')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<AppRequest>>(
          future: _requestsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final requests = snapshot.data ?? const [];
            if (requests.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('承認待ちの申請はありません')),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final request = requests[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      request.employeeName ?? '(不明な職員)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${requestTypeLabel(request.requestType)}'
                      '${request.officeName != null ? ' ・ ${request.officeName}' : ''}\n'
                      '${request.targetDate.year}/${request.targetDate.month}/${request.targetDate.day}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RequestApprovalDetailScreen(
                            request: request,
                            service: widget.service,
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
