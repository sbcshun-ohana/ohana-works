import 'package:flutter/material.dart';

import '../../models/notice.dart';
import '../../services/notice_service.dart';
import '../../theme/app_theme.dart';

/// 8章 管理者モード: お知らせ対象者ごとの既読状況(未読者一覧)。
class NoticeAudienceScreen extends StatefulWidget {
  const NoticeAudienceScreen({
    super.key,
    required this.notice,
    required this.service,
  });

  final Notice notice;
  final NoticeService service;

  @override
  State<NoticeAudienceScreen> createState() => _NoticeAudienceScreenState();
}

class _NoticeAudienceScreenState extends State<NoticeAudienceScreen> {
  late Future<List<NoticeAudienceEntry>> _audienceFuture;

  @override
  void initState() {
    super.initState();
    _audienceFuture = widget.service.fetchAudienceStatus(widget.notice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('未読者一覧 - ${widget.notice.title}')),
      body: FutureBuilder<List<NoticeAudienceEntry>>(
        future: _audienceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return const Center(child: Text('対象者がいません'));
          }
          final unreadCount = entries.where((e) => !e.isRead).length;
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: AppColors.background,
                padding: const EdgeInsets.all(16),
                child: Text(
                  '未読 $unreadCount / ${entries.length} 名',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      leading: Icon(
                        entry.isRead
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: entry.isRead
                            ? AppColors.leafGreen
                            : AppColors.warmOrange,
                      ),
                      title: Text(entry.employeeName),
                      trailing: entry.isRead
                          ? Text(
                              '${entry.readAt!.month}/${entry.readAt!.day} '
                              '${entry.readAt!.hour.toString().padLeft(2, '0')}:'
                              '${entry.readAt!.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            )
                          : const Text(
                              '未読',
                              style: TextStyle(
                                color: AppColors.warmOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
