import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';

/// 引き継ぎカード作成(209・設計書§3.1/§8)。
/// 検温・排便の時系列プレビュー(送信時にサーバー側でスナップショット固定=AC-03)、
/// 症状入力(蕁麻疹/発疹+部位)、園内感染症の参考表示、保護者向け文面(既定=施設テンプレ)。
class HandoverCardCreateScreen extends StatefulWidget {
  const HandoverCardCreateScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.childId,
    required this.childNameLabel,
  });

  final ChildcareService service;
  final String officeId;
  final String childId;
  final String childNameLabel;

  @override
  State<HandoverCardCreateScreen> createState() => _HandoverCardCreateScreenState();
}

class _HandoverCardCreateScreenState extends State<HandoverCardCreateScreen> {
  static const List<String> _rashLocationOptions = [
    '顔', '首', '胸', '腹部', '背中', '腕', '手', '脚', '足', '臀部', '全身', 'その他',
  ];

  String _hives = 'unchecked';
  String _rash = 'unchecked';
  final Set<String> _rashLocations = {};
  final _rashOtherController = TextEditingController();
  final _freeNoteController = TextEditingController();
  final _messageController = TextEditingController();

  List<({String time, double temperature})> _temps = const [];
  List<({String time, String type})> _toileting = const [];
  List<({String disease, int count})> _referenceCounts = const [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rashOtherController.dispose();
    _freeNoteController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final preview = await widget.service.fetchHandoverPreview(widget.childId, DateTime.now());
      final refs = await widget.service.fetchInfectionReferenceCounts(widget.officeId);
      if (!mounted) return;
      setState(() {
        _temps = preview.temps;
        _toileting = preview.toileting;
        _referenceCounts = refs;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _send() async {
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      final caseId = await widget.service.createInfectionHandoverCase(widget.childId);
      await widget.service.sendHandoverCard(
        caseId: caseId,
        hives: _hives,
        rash: _rash,
        rashLocations: _rash == 'yes' && _rashLocations.isNotEmpty ? _rashLocations.toList() : null,
        rashLocationOther:
            _rashLocations.contains('その他') && _rashOtherController.text.trim().isNotEmpty
                ? _rashOtherController.text.trim()
                : null,
        freeNote: _freeNoteController.text.trim().isEmpty ? null : _freeNoteController.text.trim(),
        guardianMessage: _messageController.text.trim().isEmpty ? null : _messageController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('引き継ぎカードを保護者へ送信しました')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _error = '送信に失敗しました: $e';
        });
      }
    }
  }

  Widget _sectionLabel(String text) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14));

  Widget _threeState(String label, String value, ValueChanged<String> onChanged) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        for (final opt in const [('yes', 'あり'), ('no', 'なし'), ('unchecked', '未確認')])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(opt.$2),
              selected: value == opt.$1,
              onSelected: (_) => onChanged(opt.$1),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('引き継ぎカード作成 — ${widget.childNameLabel}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 本日の記録プレビュー(送信時にこの内容がスナップショットとして固定される)
                  _sectionLabel('本日の検温(送信時に固定されます)'),
                  const SizedBox(height: 6),
                  if (_temps.isEmpty)
                    const Text('本日の検温記録はありません', style: TextStyle(color: AppColors.textSecondary))
                  else
                    Wrap(
                      spacing: 12,
                      children: _temps
                          .map((t) => Chip(label: Text('${t.time}  ${t.temperature.toStringAsFixed(1)}℃')))
                          .toList(),
                    ),
                  const SizedBox(height: 16),
                  _sectionLabel('本日の排便'),
                  const SizedBox(height: 6),
                  if (_toileting.isEmpty)
                    const Text('本日の排便記録はありません', style: TextStyle(color: AppColors.textSecondary))
                  else
                    Wrap(
                      spacing: 12,
                      children: _toileting.map((t) => Chip(label: Text('${t.time}  ${t.type}'))).toList(),
                    ),
                  if (_referenceCounts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.skyBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('園内感染症の参考表示(過去7日・診断ではなく受診時の参考情報です)',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          for (final r in _referenceCounts)
                            Text('・${r.disease}の報告 ${r.count}件', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 32),
                  _sectionLabel('園で確認した症状'),
                  const SizedBox(height: 10),
                  _threeState('蕁麻疹', _hives, (v) => setState(() => _hives = v)),
                  const SizedBox(height: 8),
                  _threeState('発疹', _rash, (v) => setState(() => _rash = v)),
                  if (_rash == 'yes') ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _rashLocationOptions
                          .map((loc) => FilterChip(
                                label: Text(loc),
                                selected: _rashLocations.contains(loc),
                                onSelected: (sel) => setState(() {
                                  if (sel) {
                                    _rashLocations.add(loc);
                                  } else {
                                    _rashLocations.remove(loc);
                                  }
                                }),
                              ))
                          .toList(),
                    ),
                    if (_rashLocations.contains('その他')) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _rashOtherController,
                        decoration: const InputDecoration(hintText: 'その他の部位'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  _sectionLabel('自由記述(園で確認した様子・症状の開始時刻・医療機関への補足)'),
                  const SizedBox(height: 6),
                  TextField(controller: _freeNoteController, maxLines: 3),
                  const SizedBox(height: 16),
                  _sectionLabel('保護者向け文面(空欄=施設の既定文面を使用)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        hintText: '空欄の場合は施設の既定文面(受診への協力依頼)が使われます'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.punchClockOut)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                      label: Text(_isSending ? '送信中…' : '保護者へ送信する'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '送信すると保護者にプッシュ通知が届き、受診結果の入力を依頼します。訂正が必要な場合は再送信してください(保護者には最新版が表示されます)。',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
    );
  }
}
