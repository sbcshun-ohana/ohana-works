import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// アレルギー発症報告(271・保護者)。ご家庭で食べたものでアレルギー反応が出た場合に園へ報告する。
/// 送信すると園の主任以上へ重要通知が届き、園が給食停止(弁当持参)の要否を判断する。
/// 自動では給食は止まらない(§7.2)。
class AllergyIncidentReportScreen extends StatefulWidget {
  const AllergyIncidentReportScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<AllergyIncidentReportScreen> createState() => _AllergyIncidentReportScreenState();
}

class _AllergyIncidentReportScreenState extends State<AllergyIncidentReportScreen> {
  final _eatenFood = TextEditingController();
  final _symptoms = TextEditingController();
  final _hospitalPlan = TextEditingController();
  DateTime _occurredAt = DateTime.now();
  DateTime? _hospitalDate; // 受診予定日(任意・カレンダー選択)
  bool _submitting = false;

  @override
  void dispose() {
    _eatenFood.dispose();
    _symptoms.dispose();
    _hospitalPlan.dispose();
    super.dispose();
  }

  // 受診予定日(カレンダー)と受診予定(自由記載)を1つの文言にまとめる。両方任意。
  String? _composeHospitalPlan() {
    final parts = <String>[];
    if (_hospitalDate != null) {
      parts.add('${_hospitalDate!.year}年${_hospitalDate!.month}月${_hospitalDate!.day}日');
    }
    if (_hospitalPlan.text.trim().isNotEmpty) parts.add(_hospitalPlan.text.trim());
    return parts.isEmpty ? null : parts.join(' / ');
  }

  Future<void> _pickHospitalDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _hospitalDate ?? now,
      firstDate: now.subtract(const Duration(days: 3)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    setState(() => _hospitalDate = date);
  }

  Future<void> _pickOccurredAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: now.subtract(const Duration(days: 14)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_occurredAt));
    if (!mounted) return;
    setState(() {
      _occurredAt = DateTime(date.year, date.month, date.day, time?.hour ?? _occurredAt.hour, time?.minute ?? _occurredAt.minute);
    });
  }

  Future<void> _submit() async {
    if (_symptoms.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('症状を入力してください')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.guardianService.submitAllergyIncidentReport(
        childId: widget.child.childId,
        eatenFood: _eatenFood.text.trim().isEmpty ? null : _eatenFood.text.trim(),
        symptoms: _symptoms.text.trim(),
        occurredAt: _occurredAt,
        hospitalPlan: _composeHospitalPlan(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('送信しました', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: const Text('園へアレルギー発症報告を送信しました。園が内容を確認し、必要に応じて連絡します。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('閉じる'))],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('送信に失敗しました: $e')));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _occurredAt;
    final occurredLabel =
        '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const Text('アレルギー発症報告')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warmOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${widget.child.displayName}さんが、ご家庭で食べたものでアレルギー反応が出た場合に報告してください。'
              '園が内容を確認し、給食での対応(除去等)を検討します。送信すると園に通知が届きます。緊急時はまず園へお電話ください。',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text('食べたもの(任意)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _eatenFood,
            decoration: const InputDecoration(hintText: '例: 卵焼き / 牛乳 / パン(ご家庭で食べたもの)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 18),
          const Text('症状(必須)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _symptoms,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '例: 口のまわりが赤くなった / じんましん / 咳き込み など',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          const Text('発生日時', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickOccurredAt,
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(occurredLabel),
          ),
          const SizedBox(height: 18),
          const Text('受診予定日(任意)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickHospitalDate,
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                label: Text(_hospitalDate != null
                    ? '${_hospitalDate!.year}年${_hospitalDate!.month}月${_hospitalDate!.day}日'
                    : '日付を選択'),
              ),
              if (_hospitalDate != null)
                TextButton(
                  onPressed: () => setState(() => _hospitalDate = null),
                  child: const Text('クリア'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('受診予定(任意)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _hospitalPlan,
            decoration: const InputDecoration(hintText: '例: 本日午後に受診予定 / かかりつけ小児科', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('園へ報告する', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
