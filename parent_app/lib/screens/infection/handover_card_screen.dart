import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import 'medical_report_screen.dart';

/// 引き継ぎカード閲覧(209・保護者)。最新版のスナップショット(検温/排便/参考表示)と
/// 園からの文面を表示し、「受診結果を入力」へ誘導する。
class HandoverCardScreen extends StatefulWidget {
  const HandoverCardScreen({
    super.key,
    required this.guardianService,
    required this.child,
    required this.caseId,
    required this.caseStatus,
  });

  final GuardianService guardianService;
  final LinkedChild child;
  final String caseId;
  final String caseStatus;

  @override
  State<HandoverCardScreen> createState() => _HandoverCardScreenState();
}

class _HandoverCardScreenState extends State<HandoverCardScreen> {
  Map<String, dynamic>? _card;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final card = await widget.guardianService.fetchLatestHandoverCard(widget.caseId);
      if (mounted) {
        setState(() {
          _card = card;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _threeStateLabel(String? v) => v == 'yes' ? 'あり' : v == 'no' ? 'なし' : '未確認';

  @override
  Widget build(BuildContext context) {
    final snapshot = (_card?['snapshot'] as Map<String, dynamic>?) ?? const {};
    final temps = (snapshot['temperatures'] as List?) ?? const [];
    final toileting = (snapshot['toileting'] as List?) ?? const [];
    final refs = (snapshot['reference_counts'] as List?) ?? const [];
    final rashLocations = ((_card?['rash_locations'] as List?) ?? const []).cast<String>();
    return Scaffold(
      appBar: AppBar(title: Text('引き継ぎカード(${widget.child.nameLabel})')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _card == null
              ? const Center(child: Text('カードが見つかりません'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_card!['guardian_message'] != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.skyBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(_card!['guardian_message'] as String,
                            style: const TextStyle(fontSize: 14, height: 1.6)),
                      ),
                    const SizedBox(height: 16),
                    const Text('園での様子', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('蕁麻疹: ${_threeStateLabel(_card!['hives'] as String?)}'
                        ' / 発疹: ${_threeStateLabel(_card!['rash'] as String?)}'
                        '${rashLocations.isNotEmpty ? '(${rashLocations.join('・')}'
                            '${_card!['rash_location_other'] != null ? '・${_card!['rash_location_other']}' : ''})' : ''}'),
                    if (_card!['free_note'] != null) ...[
                      const SizedBox(height: 6),
                      Text(_card!['free_note'] as String),
                    ],
                    const SizedBox(height: 16),
                    const Text('本日の検温', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    if (temps.isEmpty)
                      const Text('記録なし', style: TextStyle(color: AppColors.textSecondary))
                    else
                      Wrap(
                        spacing: 10,
                        children: temps
                            .map((t) => Chip(
                                label: Text(
                                    '${(t as Map)['time']}  ${((t['temperature']) as num).toStringAsFixed(1)}℃')))
                            .toList(),
                      ),
                    const SizedBox(height: 12),
                    const Text('本日の排便', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    if (toileting.isEmpty)
                      const Text('記録なし', style: TextStyle(color: AppColors.textSecondary))
                    else
                      Wrap(
                        spacing: 10,
                        children: toileting
                            .map((t) => Chip(label: Text('${(t as Map)['time']}  ${t['type']}')))
                            .toList(),
                      ),
                    if (refs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warmOrange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('園内で報告のある感染症(過去7日・受診時の参考情報です)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            for (final r in refs)
                              Text('・${(r as Map)['disease']}の報告 ${r['count']}件',
                                  style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (widget.caseStatus != 'closed')
                      FilledButton.icon(
                        onPressed: () async {
                          final submitted = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => MedicalReportScreen(
                                guardianService: widget.guardianService,
                                child: widget.child,
                                caseId: widget.caseId,
                              ),
                            ),
                          );
                          if (submitted == true && context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                        icon: const Icon(Icons.local_hospital_rounded),
                        label: const Text('受診結果を入力する'),
                      ),
                  ],
                ),
    );
  }
}
