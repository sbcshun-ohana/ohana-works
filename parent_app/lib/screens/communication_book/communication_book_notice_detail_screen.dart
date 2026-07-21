import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/communication_book_entry.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 保育園からのお知らせ(個別お知らせ)の詳細。開いた時点で閲覧履歴を記録する。
/// 連絡帳(本文)とお知らせは同じ閲覧履歴(communication_book_reads)を共有しているため、
/// どちらか一方を開くと、その日の両方の未読バッジがまとめて既読になる。
class CommunicationBookNoticeDetailScreen extends StatefulWidget {
  const CommunicationBookNoticeDetailScreen({
    super.key,
    required this.guardianService,
    required this.entryId,
    required this.guardianId,
  });

  final GuardianService guardianService;
  final String entryId;
  final String guardianId;

  @override
  State<CommunicationBookNoticeDetailScreen> createState() => _CommunicationBookNoticeDetailScreenState();
}

class _CommunicationBookNoticeDetailScreenState extends State<CommunicationBookNoticeDetailScreen> {
  CommunicationBookEntry? _entry;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entry = await widget.guardianService.fetchCommunicationBookEntryDetail(widget.entryId);
    unawaited(widget.guardianService.markCommunicationBookRead(
      entryId: widget.entryId,
      guardianId: widget.guardianId,
    ));
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      appBar: AppBar(
        title: entry == null
            ? const Text('お知らせ')
            : Text('${entry.businessDate.year}/${entry.businessDate.month}/${entry.businessDate.day}のお知らせ'),
      ),
      body: _isLoading || entry == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (entry.noticeLabels.isEmpty)
                  const Text('お知らせはありません', style: TextStyle(color: AppColors.textSecondary))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: entry.noticeLabels
                        .map((label) => Chip(
                              label: Text(label),
                              backgroundColor: AppColors.warmOrange.withValues(alpha: 0.15),
                            ))
                        .toList(),
                  ),
              ],
            ),
    );
  }
}
