import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/guardian_broadcast_notice.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// お知らせ(一斉配信)の詳細。到達時に既読を記録する(RPC側で二重INSERT防止)。
class BroadcastNoticeDetailScreen extends StatefulWidget {
  const BroadcastNoticeDetailScreen({
    super.key,
    required this.guardianService,
    required this.notice,
    required this.childLabels,
  });

  final GuardianService guardianService;
  final GuardianBroadcastNotice notice;
  final List<String> childLabels;

  @override
  State<BroadcastNoticeDetailScreen> createState() => _BroadcastNoticeDetailScreenState();
}

class _BroadcastNoticeDetailScreenState extends State<BroadcastNoticeDetailScreen> {
  @override
  void initState() {
    super.initState();
    // 到達=既読。失敗しても表示は妨げない。
    unawaited(widget.guardianService.markBroadcastNoticeRead(widget.notice.id));
  }

  String _formatDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    final badges = <Widget>[
      if (notice.isWholeSchool) _Badge(label: '園全体', color: AppColors.skyBlue),
      ...widget.childLabels.map((l) => _Badge(label: l, color: AppColors.leafGreen)),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('お知らせ')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: badges),
            ),
          Text(
            notice.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            _formatDate(notice.sentAt),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const Divider(height: 28),
          Text(notice.body, style: const TextStyle(fontSize: 15, height: 1.6, color: AppColors.textPrimary)),
        ],
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
