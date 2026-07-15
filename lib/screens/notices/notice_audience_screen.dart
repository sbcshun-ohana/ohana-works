import 'package:flutter/material.dart';

import '../../models/notice.dart';
import '../../services/notice_service.dart';
import '../../theme/app_theme.dart';

enum _AudienceFilter { unread, read, all }

/// 8章 管理者モード: お知らせ対象者ごとの既読状況(未読者一覧・既読者一覧)。
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
  _AudienceFilter _filter = _AudienceFilter.unread;

  @override
  void initState() {
    super.initState();
    _audienceFuture = widget.service.fetchAudienceStatus(widget.notice);
  }

  List<NoticeAudienceEntry> _applyFilter(List<NoticeAudienceEntry> entries) {
    switch (_filter) {
      case _AudienceFilter.unread:
        return entries.where((e) => !e.isRead).toList();
      case _AudienceFilter.read:
        return entries.where((e) => e.isRead).toList();
      case _AudienceFilter.all:
        return entries;
    }
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
          final unreadCount = entries.where((e) => !e.isRead).length;
          final visibleEntries = _applyFilter(entries);
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '未読 $unreadCount / ${entries.length} 名',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<_AudienceFilter>(
                      segments: const [
                        ButtonSegment(
                          value: _AudienceFilter.unread,
                          label: Text('未読'),
                          icon: Icon(Icons.radio_button_unchecked_rounded),
                        ),
                        ButtonSegment(
                          value: _AudienceFilter.read,
                          label: Text('既読'),
                          icon: Icon(Icons.check_circle_rounded),
                        ),
                        ButtonSegment(
                          value: _AudienceFilter.all,
                          label: Text('全て'),
                        ),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (selection) {
                        setState(() => _filter = selection.first);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('対象者がいません'))
                    : visibleEntries.isEmpty
                        ? const Center(child: Text('該当する対象者がいません'))
                        : ListView.separated(
                            itemCount: visibleEntries.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = visibleEntries[index];
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
                                subtitle: entry.officeName != null
                                    ? Text(
                                        entry.officeName!,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                      )
                                    : null,
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
