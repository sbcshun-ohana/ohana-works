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

  List<Notice>? _notices;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final notices = await _service.fetchNotices();
      if (!mounted) return;
      setState(() {
        _notices = notices;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  /// 詳細画面から戻ってきた最新のお知らせ情報を、再取得せずその場で一覧へ反映する。
  void _applyUpdatedNotice(Notice updated) {
    final notices = _notices;
    if (notices == null) return;
    final index = notices.indexWhere((n) => n.id == updated.id);
    if (index == -1) return;
    setState(() {
      _notices = List<Notice>.of(notices)..[index] = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('お知らせ')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _notices == null) {
      return _buildScrollableMessage(
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_hasError) {
      return _buildMessage('お知らせの取得に失敗しました');
    }
    final notices = _notices ?? const [];
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
            final updated = await Navigator.of(context).push<Notice>(
              MaterialPageRoute(
                builder: (_) => NoticeDetailScreen(
                  noticeId: notice.id,
                  service: _service,
                ),
              ),
            );
            if (!mounted) return;
            if (updated != null) {
              _applyUpdatedNotice(updated);
            } else {
              await _load();
            }
          },
        );
      },
    );
  }

  Widget _buildScrollableMessage({required Widget child}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        child,
      ],
    );
  }

  Widget _buildMessage(String message) {
    return _buildScrollableMessage(
      child: Column(
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 56,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
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
