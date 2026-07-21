import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../models/parent_request.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import 'new_parent_request_screen.dart';
import 'parent_request_detail_screen.dart';

/// 保護者からの申請・連絡(欠席/遅刻/早退/お迎えの方の変更/その他連絡)の一覧・新規作成入口。
class ParentRequestListScreen extends StatefulWidget {
  const ParentRequestListScreen({
    super.key,
    required this.guardianService,
    required this.child,
    required this.guardianId,
  });

  final GuardianService guardianService;
  final LinkedChild child;
  final String guardianId;

  @override
  State<ParentRequestListScreen> createState() => _ParentRequestListScreenState();
}

class _ParentRequestListScreenState extends State<ParentRequestListScreen> {
  late Future<List<ParentRequest>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _requestsFuture = widget.guardianService.fetchParentRequests(widget.child.childId);
  }

  Future<void> _reload() async {
    setState(_load);
    await _requestsFuture;
  }

  Future<void> _openNewRequest() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewParentRequestScreen(
          guardianService: widget.guardianService,
          child: widget.child,
          guardianId: widget.guardianId,
        ),
      ),
    );
    if (created == true) await _reload();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.leafGreen;
      case 'rejected':
        return AppColors.danger;
      case 'pending':
      default:
        return AppColors.warmOrange;
    }
  }

  String _formatDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.child.nameLabel}の保護者からの申請・連絡')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewRequest,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新規申請'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<ParentRequest>>(
          future: _requestsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final requests = snapshot.data ?? const [];
            if (requests.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  Icon(Icons.assignment_outlined, size: 64, color: AppColors.textSecondary),
                  SizedBox(height: 16),
                  Text('申請履歴はまだありません', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                ],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final request = requests[index];
                final typeColor = parentRequestTypeColors[request.requestType] ?? AppColors.textSecondary;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: typeColor.withValues(alpha: 0.15),
                      child: Icon(
                        parentRequestTypeIcons[request.requestType] ?? Icons.assignment_outlined,
                        color: typeColor,
                      ),
                    ),
                    title: Text(parentRequestTypeLabels[request.requestType] ?? request.requestType),
                    subtitle: Text('対象日: ${_formatDate(request.targetDate)}'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(request.status).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        parentRequestStatusLabel(request.status),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(request.status)),
                      ),
                    ),
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ParentRequestDetailScreen(
                            guardianService: widget.guardianService,
                            request: request,
                            guardianId: widget.guardianId,
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
