import 'package:flutter/material.dart';

import '../models/guardian_qr_resolution.dart';
import '../services/guardian_qr_service.dart';

/// 兄弟一括登降園の確認画面(234・俊確定 2026-08-18)。
/// スキャンで返った候補を表示し、登園/降園する園児を選んで確定する(半自動)。
/// 欠席連絡がある子は既定OFF・注記付きだが選択可能(登園時は当日欠席が自動解除される)。
class FamilyCheckinScreen extends StatefulWidget {
  const FamilyCheckinScreen({
    super.key,
    required this.resolution,
    required this.service,
  });

  final GuardianQrResolution resolution;
  final GuardianQrService service;

  @override
  State<FamilyCheckinScreen> createState() => _FamilyCheckinScreenState();
}

class _FamilyCheckinScreenState extends State<FamilyCheckinScreen> {
  late final Map<String, bool> _selected;
  bool _isSubmitting = false;
  String? _errorMessage;
  List<Map<String, dynamic>>? _results;

  bool get _isArrival => widget.resolution.direction == 'arrival';

  @override
  void initState() {
    super.initState();
    _selected = {
      for (final c in widget.resolution.candidates) c.childId: c.defaultSelected,
    };
  }

  Future<void> _submit() async {
    final action = _isArrival ? 'checkin' : 'checkout';
    final selections = _selected.entries
        .where((e) => e.value)
        .map((e) => {'child_id': e.key, 'action': action})
        .toList();
    if (selections.isEmpty) {
      setState(() => _errorMessage = '登降園するお子様を選んでください');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final results = await widget.service.applyFamilyCheckin(
        sessionId: widget.resolution.sessionId!,
        selections: selections,
      );
      if (mounted) setState(() => _results = results);
    } on GuardianQrException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_results != null) return _buildResult();
    final title = _isArrival ? 'ご登園' : 'ご降園';
    return Scaffold(
      backgroundColor: const Color(0xFF0B1F3A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('$titleのお子様を選んでください',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(_isArrival ? '一緒に登園するお子様にチェックを入れてください' : 'お迎えするお子様にチェックを入れてください',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    const SizedBox(height: 20),
                    ...widget.resolution.candidates.map(_buildCandidateTile),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                            child: const Text('キャンセル', style: TextStyle(fontSize: 18)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                            child: _isSubmitting
                                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(_isArrival ? '登園する' : '降園する', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateTile(FamilyCheckinCandidate c) {
    // 選択できないケース(登園フェーズで既に在園中/降園済み、降園フェーズで未登園)は無効化。
    final disabled = _isArrival
        ? (c.todayStatus == 'present' || c.todayStatus == 'picked_up')
        : (c.todayStatus != 'present');
    final selected = !disabled && (_selected[c.childId] ?? false);
    const blue = Color(0xFF1E88E5);
    // タッチパネルでの押し間違いを防ぐため、カード全体を大きなタップ領域にし、
    // 兄弟ごとに十分な間隔と大きなチェック表示で独立して見せる。
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : () => setState(() => _selected[c.childId] = !selected),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            decoration: BoxDecoration(
              color: disabled ? Colors.grey.shade100 : (selected ? const Color(0xFFE3F2FD) : Colors.white),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: disabled ? Colors.grey.shade300 : (selected ? blue : Colors.grey.shade300),
                width: selected ? 3 : 2,
              ),
            ),
            child: Row(
              children: [
                // 大きめのチェックボックス(視認性・タップ精度向上)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? blue : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: disabled ? Colors.grey.shade400 : (selected ? blue : Colors.grey.shade500), width: 2),
                  ),
                  child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 30) : null,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.childName}${c.className != null ? '(${c.className})' : ''}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: disabled ? Colors.grey : Colors.black87,
                        ),
                      ),
                      if (c.note != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          c.note!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.isAbsentToday ? Colors.orange.shade800 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    final done = _results!.where((r) => r['result'] == 'checked_in' || r['result'] == 'checked_out').toList();
    final blocked = _results!.where((r) => r['result'] == 'blocked').toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0B1F3A),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(blocked.isEmpty ? Icons.check_circle_rounded : Icons.info_rounded,
                        size: 72, color: blocked.isEmpty ? Colors.green : Colors.orange),
                    const SizedBox(height: 16),
                    Text('${done.length}名を${_isArrival ? '登園' : '降園'}しました',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    if (blocked.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      for (final b in blocked)
                        Text('受付できなかったお子様: ${b['reason'] ?? ''}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15, color: Colors.orange, fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16)),
                      child: const Text('とじる', style: TextStyle(fontSize: 20)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
