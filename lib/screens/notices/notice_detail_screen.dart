import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/notice.dart';
import '../../services/notice_service.dart';
import '../../theme/app_theme.dart';
import 'notice_audience_screen.dart';

/// 8章 お知らせ詳細。開封時に既読を記録し、定型返信・添付ファイルを表示する。
class NoticeDetailScreen extends StatefulWidget {
  const NoticeDetailScreen({
    super.key,
    required this.noticeId,
    required this.service,
  });

  final String noticeId;
  final NoticeService service;

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  late Future<Notice?> _noticeFuture;
  late Future<List<NoticeAttachment>> _attachmentsFuture;
  late Future<bool> _canViewAudienceFuture;

  Notice? _notice;
  String? _submittingReply;

  @override
  void initState() {
    super.initState();
    _noticeFuture = widget.service.fetchNotice(widget.noticeId);
    _attachmentsFuture = widget.service.fetchAttachments(widget.noticeId);
    _canViewAudienceFuture = widget.service.canViewAudienceStatus();
    widget.service.markAsRead(widget.noticeId);
  }

  Future<void> _openAttachment(NoticeAttachment attachment) async {
    try {
      final url =
          await widget.service.createAttachmentSignedUrl(attachment.filePath);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('添付ファイルを開けませんでした')),
      );
    }
  }

  Future<void> _reply(String option) async {
    setState(() => _submittingReply = option);
    try {
      await widget.service.submitReply(widget.noticeId, option);
      if (!mounted) return;
      setState(() {
        _notice = Notice(
          id: _notice!.id,
          category: _notice!.category,
          title: _notice!.title,
          body: _notice!.body,
          requiresReadConfirmation: _notice!.requiresReadConfirmation,
          standardReplyOptions: _notice!.standardReplyOptions,
          createdAt: _notice!.createdAt,
          targetOfficeId: _notice!.targetOfficeId,
          targetPositionId: _notice!.targetPositionId,
          myReadAt: DateTime.now(),
          myReplyOption: option,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「$option」で返信しました')),
      );
    } finally {
      if (mounted) setState(() => _submittingReply = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('お知らせ'),
        actions: [
          FutureBuilder<bool>(
            future: _canViewAudienceFuture,
            builder: (context, snapshot) {
              if (snapshot.data != true || _notice == null) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: '未読者一覧',
                icon: const Icon(Icons.fact_check_outlined),
                onPressed: () {
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => NoticeAudienceScreen(
                        notice: _notice!,
                        service: widget.service,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<Notice?>(
        future: _noticeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final notice = _notice ??= snapshot.data;
          if (notice == null) {
            return const Center(child: Text('お知らせが見つかりません'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.category,
                  style: const TextStyle(
                    color: AppColors.skyBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  notice.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${notice.createdAt.year}/${notice.createdAt.month}/${notice.createdAt.day}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                Text(
                  notice.body,
                  style: const TextStyle(fontSize: 16, height: 1.6),
                ),
                const SizedBox(height: 24),
                _buildAttachments(),
                if (notice.requiresReadConfirmation) ...[
                  const SizedBox(height: 32),
                  const Text(
                    '返信',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: notice.standardReplyOptions.map((option) {
                      final isSelected = notice.myReplyOption == option;
                      return ElevatedButton(
                        onPressed: _submittingReply != null
                            ? null
                            : () => _reply(option),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSelected
                              ? AppColors.leafGreen
                              : AppColors.skyBlue,
                        ),
                        child: _submittingReply == option
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(option),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttachments() {
    return FutureBuilder<List<NoticeAttachment>>(
      future: _attachmentsFuture,
      builder: (context, snapshot) {
        final attachments = snapshot.data ?? const [];
        if (attachments.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '添付ファイル',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...attachments.map(
              (attachment) => Card(
                child: ListTile(
                  leading: const Icon(Icons.attach_file_rounded),
                  title: Text(attachment.fileName),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => _openAttachment(attachment),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
