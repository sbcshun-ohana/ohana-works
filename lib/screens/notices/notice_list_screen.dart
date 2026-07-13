import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/notice.dart';
import '../../services/notice_service.dart';
import '../../theme/app_theme.dart';
import 'notice_detail_screen.dart';

/// 8章 職員連絡(お知らせ)一覧。
class NoticeListScreen extends StatefulWidget {
  const NoticeListScreen({super.key});

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  final _service = NoticeService(Supabase.instance.client);
  late Future<List<Notice>> _noticesFuture;

  @override
  void initState() {
    super.initState();
    _noticesFuture = _service.fetchNotices();
  }

  Future<void> _refresh() async {
    final future = _service.fetchNotices();
    setState(() => _noticesFuture = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('お知らせ')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Notice>>(
          future: _noticesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _buildMessage('お知らせの取得に失敗しました');
            }
            final notices = snapshot.data ?? const [];
            if (notices.isEmpty) {
              return _buildMessage('お知らせはありません');
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: notices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final notice = notices[index];
                return _NoticeListTile(
                  notice: notice,
                  onTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => NoticeDetailScreen(
                          noticeId: notice.id,
                          service: _service,
                        ),
                      ),
                    );
                    if (mounted) await _refresh();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessage(String message) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.mark_email_read_outlined,
          size: 56,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _NoticeListTile extends StatelessWidget {
  const _NoticeListTile({required this.notice, required this.onTap});

  final Notice notice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6, right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      notice.isRead ? Colors.transparent : AppColors.warmOrange,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _CategoryBadge(category: notice.category),
                        const Spacer(),
                        Text(
                          '${notice.createdAt.month}/${notice.createdAt.day}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notice.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight:
                            notice.isRead ? FontWeight.w500 : FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.skyBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        category,
        style: const TextStyle(
          color: AppColors.skyBlue,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
