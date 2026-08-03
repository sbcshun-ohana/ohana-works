import 'package:flutter/material.dart';

import '../../models/guardian_broadcast_notice.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import 'broadcast_notice_detail_screen.dart';

/// 保護者向けお知らせ(一斉配信)の園児横断一覧。園児を選ばずトップから入る。
/// 各行に「園全体」または「園児名(クラス)」バッジを出し、兄弟児の対象を判別できる。
class BroadcastNoticeListScreen extends StatefulWidget {
  const BroadcastNoticeListScreen({
    super.key,
    required this.guardianService,
    required this.guardianId,
    required this.children,
  });

  final GuardianService guardianService;
  final String guardianId;
  final List<LinkedChild> children;

  @override
  State<BroadcastNoticeListScreen> createState() => _BroadcastNoticeListScreenState();
}

class _BroadcastNoticeListScreenState extends State<BroadcastNoticeListScreen> {
  late Future<List<GuardianBroadcastNotice>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.guardianService.fetchBroadcastNotices(widget.guardianId);
  }

  void _reload() {
    setState(() {
      _future = widget.guardianService.fetchBroadcastNotices(widget.guardianId);
    });
  }

  /// child_id → 「園児名(クラス)」ラベル。未紐付けidは汎用表記。
  List<String> _childLabels(GuardianBroadcastNotice notice) {
    final byId = {for (final c in widget.children) c.childId: c};
    return notice.childIds.map((id) {
      final child = byId[id];
      if (child == null) return '園児';
      return child.className == null ? child.nameLabel : '${child.nameLabel}(${child.className})';
    }).toList();
  }

  String _formatDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('お知らせ')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<GuardianBroadcastNotice>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final notices = snapshot.data ?? const [];
            if (notices.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text('お知らせはまだありません', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notices.length,
              itemBuilder: (context, index) => _NoticeCard(
                notice: notices[index],
                childLabels: _childLabels(notices[index]),
                dateLabel: _formatDate(notices[index].sentAt),
                onTap: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => BroadcastNoticeDetailScreen(
                        guardianService: widget.guardianService,
                        notice: notices[index],
                        childLabels: _childLabels(notices[index]),
                      ),
                    ),
                  );
                  if (mounted) _reload();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.notice,
    required this.childLabels,
    required this.dateLabel,
    required this.onTap,
  });

  final GuardianBroadcastNotice notice;
  final List<String> childLabels;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[
      if (notice.isWholeSchool) _Badge(label: '園全体', color: AppColors.skyBlue),
      ...childLabels.map((l) => _Badge(label: l, color: AppColors.leafGreen)),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          notice.isRead ? Icons.mark_email_read_rounded : Icons.campaign_rounded,
          color: notice.isRead ? AppColors.textSecondary : AppColors.warmOrange,
        ),
        title: Text(
          notice.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: notice.isRead ? FontWeight.w500 : FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(dateLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            if (badges.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 6, children: badges),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
