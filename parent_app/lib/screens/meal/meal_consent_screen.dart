import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 給食会議の保護者同意(272・保護者)。園での対面説明のうえ、除去食提供に同意する。
/// 同意すると日時・氏名・同意文言が不変記録される(§7)。
class MealConsentScreen extends StatefulWidget {
  const MealConsentScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<MealConsentScreen> createState() => _MealConsentScreenState();
}

class _MealConsentScreenState extends State<MealConsentScreen> {
  bool _loading = true;
  String? _error;
  List<({String conferenceId, DateTime? heldOn, String? nutritionistName, String? eliminationPlan, String? consentBody})>
      _pending = const [];
  List<({String id, DateTime agreedAt, String agreedGuardianName, String? consentText, DateTime? heldOn,
      String? nutritionistName, String? eliminationPlan})> _history = const [];
  final _name = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pending = await widget.guardianService.fetchPendingMealConsents(widget.child.childId);
      List<({String id, DateTime agreedAt, String agreedGuardianName, String? consentText, DateTime? heldOn,
          String? nutritionistName, String? eliminationPlan})> history = const [];
      try {
        history = await widget.guardianService.fetchMealConsentHistory(widget.child.childId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _history = history;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit(String conferenceId) async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同意者のお名前を入力してください')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.guardianService.submitMealConsent(conferenceId: conferenceId, agreedGuardianName: _name.text.trim());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('同意を記録しました', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: const Text('アレルギー除去食の提供について同意いただきました。園が提供を開始します。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同意の記録に失敗しました: $e')));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('アレルギー除去食提供の同意')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : (_pending.isEmpty && _history.isEmpty)
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('アレルギー除去食に関する同意の記録はありません。', style: TextStyle(color: AppColors.textSecondary)),
                    ))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_pending.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text('同意のお願い', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          for (final p in _pending) _consentCard(p),
                        ],
                        if (_history.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
                            child: Text('これまでの同意履歴',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          ),
                          for (final h in _history) _historyCard(h),
                        ],
                      ],
                    ),
    );
  }

  Widget _historyCard(
      ({String id, DateTime agreedAt, String agreedGuardianName, String? consentText, DateTime? heldOn,
        String? nutritionistName, String? eliminationPlan}) h) {
    final a = h.agreedAt.toLocal();
    final agreedLabel =
        '${a.year}/${a.month}/${a.day} ${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppColors.leafGreen, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('給食会議の内容に同意しました',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _kv('同意日時', agreedLabel),
            _kv('同意者', h.agreedGuardianName),
            if (h.heldOn != null) _kv('給食会議 開催日', '${h.heldOn!.year}/${h.heldOn!.month}/${h.heldOn!.day}'),
            if (h.nutritionistName != null && h.nutritionistName!.isNotEmpty) _kv('栄養士', h.nutritionistName!),
            if (h.eliminationPlan != null && h.eliminationPlan!.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Text('提供方針', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 2),
              Text(h.eliminationPlan!, style: const TextStyle(fontSize: 13, height: 1.5)),
            ],
            if (h.consentText != null && h.consentText!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: const Text('同意した文面を表示', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(h.consentText!, style: const TextStyle(fontSize: 13, height: 1.6)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _consentCard(
      ({String conferenceId, DateTime? heldOn, String? nutritionistName, String? eliminationPlan, String? consentBody})
          p) {
    final held = p.heldOn;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.child.displayName}さんのアレルギー除去食について',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (held != null)
              _kv('給食会議 開催日', '${held.year}/${held.month}/${held.day}'),
            if (p.nutritionistName != null && p.nutritionistName!.isNotEmpty)
              _kv('栄養士', p.nutritionistName!),
            if (p.eliminationPlan != null && p.eliminationPlan!.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('提供方針', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 4),
              Text(p.eliminationPlan!, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            const Divider(height: 24),
            if (p.consentBody != null && p.consentBody!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.leafGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(p.consentBody!, style: const TextStyle(fontSize: 14, height: 1.6)),
              )
            else
              const Text('同意文言が未設定です。園にお問い合わせください。', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            const Text('同意者のお名前', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: '例: 山田 花子', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_submitting || p.consentBody == null || p.consentBody!.isEmpty)
                    ? null
                    : () => _submit(p.conferenceId),
                child: _submitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('上記に同意する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
