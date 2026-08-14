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
  // 208: 添付(PDF/画像)。画像はインライン表示、その他はタップでURL表示。
  List<({String filePath, String fileName, String? contentType})> _attachments = const [];
  final Map<String, String> _signedUrls = {};

  @override
  void initState() {
    super.initState();
    // 到達=既読。失敗しても表示は妨げない。
    unawaited(widget.guardianService.markBroadcastNoticeRead(widget.notice.id));
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    try {
      final list = await widget.guardianService.fetchBroadcastNoticeAttachments(widget.notice.id);
      if (!mounted) return;
      setState(() => _attachments = list);
      // 画像はインライン表示用に署名URLを先に取っておく
      for (final a in list) {
        if (a.contentType?.startsWith('image/') ?? false) {
          try {
            final url = await widget.guardianService.createBroadcastAttachmentUrl(a.filePath);
            if (mounted) setState(() => _signedUrls[a.filePath] = url);
          } catch (_) {}
        }
      }
    } catch (_) {
      // 取得失敗時は本文のみ表示。
    }
  }

  Future<void> _openAttachment(({String filePath, String fileName, String? contentType}) a) async {
    try {
      final url = await widget.guardianService.createBroadcastAttachmentUrl(a.filePath);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(a.fileName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          content: SelectableText('以下のURLをブラウザで開くと表示・保存できます(5分間有効)\n\n$url'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
    } catch (_) {}
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
          // 208: 添付。画像=インライン、PDF等=タップでURL表示。
          for (final a in _attachments) ...[
            const SizedBox(height: 16),
            if ((a.contentType?.startsWith('image/') ?? false) && _signedUrls[a.filePath] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _signedUrls[a.filePath]!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => OutlinedButton.icon(
                    onPressed: () => _openAttachment(a),
                    icon: const Icon(Icons.image_rounded, size: 18),
                    label: Text(a.fileName),
                  ),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _openAttachment(a),
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(a.fileName, overflow: TextOverflow.ellipsis),
              ),
          ],
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
