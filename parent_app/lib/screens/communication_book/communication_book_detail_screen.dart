import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/communication_book_entry.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 園連絡帳の詳細。開いた時点で閲覧履歴を記録する(v0.4 §5.3 変更4)。
/// 「重要事項として確認しました」ボタンは、園から重要事項確認を依頼された内容向けに
/// 常時表示する(該当連絡帳を限定するフラグは現時点でスキーマに無いため)。
class CommunicationBookDetailScreen extends StatefulWidget {
  const CommunicationBookDetailScreen({
    super.key,
    required this.guardianService,
    required this.entryId,
    required this.guardianId,
  });

  final GuardianService guardianService;
  final String entryId;
  final String guardianId;

  @override
  State<CommunicationBookDetailScreen> createState() => _CommunicationBookDetailScreenState();
}

class _CommunicationBookDetailScreenState extends State<CommunicationBookDetailScreen> {
  CommunicationBookEntry? _entry;
  bool _isLoading = true;
  bool _isConfirmed = false;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entry = await widget.guardianService.fetchCommunicationBookEntryDetail(widget.entryId);
    final confirmed = await widget.guardianService.hasConfirmedImportantMatter(
      entryId: widget.entryId,
      guardianId: widget.guardianId,
    );
    // 閲覧履歴を記録(1名でも閲覧すれば家庭確認済みとする判定は職員側で行う)
    unawaited(widget.guardianService.markCommunicationBookRead(
      entryId: widget.entryId,
      guardianId: widget.guardianId,
    ));
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _isConfirmed = confirmed;
      _isLoading = false;
    });
  }

  Future<void> _confirmImportantMatter() async {
    setState(() => _isConfirming = true);
    await widget.guardianService.confirmImportantMatter(entryId: widget.entryId, guardianId: widget.guardianId);
    if (!mounted) return;
    setState(() {
      _isConfirmed = true;
      _isConfirming = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('確認しました')));
  }

  String _mealLabel(int? pct) {
    if (pct == null) return '未入力';
    return '$pct%';
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      appBar: AppBar(title: entry == null ? const Text('連絡帳') : Text('${entry.businessDate.year}/${entry.businessDate.month}/${entry.businessDate.day}の連絡帳')),
      body: _isLoading || entry == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (entry.currentText?.isNotEmpty ?? false) ...[
                  const Text('本文', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(entry.currentText!, style: const TextStyle(fontSize: 15, height: 1.5)),
                  const SizedBox(height: 24),
                ],
                if (entry.supplyItems.isNotEmpty) ...[
                  const Text('備品利用', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...entry.supplyItems.map((item) => Text('・${item.itemName} × ${item.quantity}')),
                  const SizedBox(height: 24),
                ],
                _SectionCard(
                  title: '午睡',
                  child: entry.napPeriods.isEmpty
                      ? const Text('記録なし', style: TextStyle(color: AppColors.textSecondary))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: entry.napPeriods.map((p) => Text('${p.start} 〜 ${p.end}')).toList(),
                        ),
                ),
                _SectionCard(
                  title: '排泄',
                  child: entry.toiletingRecords.isEmpty
                      ? const Text('記録なし', style: TextStyle(color: AppColors.textSecondary))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: entry.toiletingRecords.map((r) => Text('${r.time}  ${r.type}')).toList(),
                        ),
                ),
                _SectionCard(
                  title: '食事',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('完食割合: ${_mealLabel(entry.mealCompletionPct)}'),
                      if (entry.mealFreeNote?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(entry.mealFreeNote!),
                      ],
                    ],
                  ),
                ),
                _SectionCard(
                  title: '検温',
                  child: Text(
                    entry.temperature == null
                        ? '未入力'
                        : '${entry.temperature!.toStringAsFixed(1)}℃'
                            '${entry.temperatureMeasuredAt != null ? '(${entry.temperatureMeasuredAt})' : ''}',
                  ),
                ),
                _SectionCard(
                  title: '入浴',
                  child: Text(entry.bathTaken == null ? '未入力' : (entry.bathTaken! ? 'あり' : 'なし')),
                ),
                const SizedBox(height: 12),
                if (_isConfirmed)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.leafGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.leafGreen),
                        SizedBox(width: 8),
                        Text('重要事項として確認済みです', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                else
                  OutlinedButton(
                    onPressed: _isConfirming ? null : _confirmImportantMatter,
                    child: const Text('重要事項として確認しました'),
                  ),
              ],
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
