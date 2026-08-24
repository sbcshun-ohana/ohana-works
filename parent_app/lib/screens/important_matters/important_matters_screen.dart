import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 重要事項説明書(310)。公開中の文書を閲覧し、世帯単位で同意する。同意は必須(未同意は利用不可)。
class ImportantMattersScreen extends StatefulWidget {
  const ImportantMattersScreen({super.key, required this.guardianService, required this.child});
  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<ImportantMattersScreen> createState() => _ImportantMattersScreenState();
}

class _ImportantMattersScreenState extends State<ImportantMattersScreen> {
  ({String id, String title, int fiscalYear, int version, String storagePath, bool consented, String? agreedAt})? _doc;
  bool _loading = true;
  bool _busy = false;
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await widget.guardianService.fetchActiveImportantMatters(widget.child.childId);
      if (!mounted) return;
      setState(() {
        _doc = d;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPdf() async {
    final d = _doc;
    if (d == null) return;
    try {
      final url = await widget.guardianService.importantMattersSignedUrl(d.storagePath);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(d.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          content: SelectableText('以下のURLをブラウザで開くと表示・保存できます(5分間有効)\n\n$url'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
    } catch (_) {}
  }

  Future<void> _consent() async {
    final d = _doc;
    if (d == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同意される方のお名前を入力してください')));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.guardianService.submitImportantMattersConsent(d.id, widget.child.childId, name);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同意を記録しました')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同意できません: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    return Scaffold(
      appBar: AppBar(title: const Text('重要事項説明書')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? const Center(child: Text('現在公開されている重要事項説明書はありません', style: TextStyle(color: AppColors.textSecondary)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(d.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('${d.fiscalYear}年度', style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _openPdf,
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('重要事項説明書を開く(PDF)'),
                    ),
                    const SizedBox(height: 24),
                    if (d.consented)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.leafGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.leafGreen.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.leafGreen),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('同意済みです${d.agreedAt != null ? '（${d.agreedAt!.substring(0, 10)}）' : ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warmOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.warmOrange.withValues(alpha: 0.5)),
                        ),
                        child: const Text(
                          '内容をご確認のうえ、同意をお願いします。\n※ 重要事項説明書への同意は保育園のご利用に必須です。',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: '同意される方のお名前(保護者)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _busy ? null : _consent,
                          child: const Text('上記の内容に同意します', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('※ 世帯で一度同意すれば、ご家族全員の同意として記録されます。',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
    );
  }
}
