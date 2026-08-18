import 'package:flutter/material.dart';

import '../../../models/development_record.dart';
import '../../../services/childcare_service.dart';

/// 発達記録タブ(Ohana Kids・239/240/241)。担任・担当クラス職員が達成申請を出す。
/// 承認(確定)は主任以上が管理者Webの承認キューで行う(本タブは閲覧+申請+取下げ)。
class ChildDevelopmentTab extends StatefulWidget {
  const ChildDevelopmentTab({
    super.key,
    required this.service,
    required this.childId,
  });

  final ChildcareService service;
  final String childId;

  @override
  State<ChildDevelopmentTab> createState() => _ChildDevelopmentTabState();
}

class _ChildDevelopmentTabState extends State<ChildDevelopmentTab> {
  DevelopmentHeader? _header;
  List<DevelopmentRecord> _records = [];
  String? _band;
  String _domainFilter = 'all';
  bool _hideAchieved = false;
  bool _loading = true;
  String? _error;
  String? _busyItemId;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  Future<void> _load({bool initial = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (initial) {
        _header = await widget.service.fetchChildDevelopmentHeader(widget.childId);
        _band = _header?.applicableBand ?? 'AGE_2';
      }
      final records = await widget.service
          .fetchChildDevelopmentRecords(widget.childId, ageBandCode: _band);
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit(DevelopmentRecord r) async {
    final note = await _promptNote('達成申請の根拠メモ(任意)');
    if (note == null) return; // キャンセル
    setState(() => _busyItemId = r.itemId);
    try {
      await widget.service.submitDevelopmentAchievementRequest(
        childId: widget.childId,
        itemId: r.itemId,
        note: note.isNotEmpty ? note : null,
      );
      await _load();
      _snack('達成申請を送信しました(主任以上の承認待ち)');
    } catch (e) {
      _snack(_friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }

  Future<void> _withdraw(DevelopmentRecord r) async {
    if (r.requestId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('申請の取下げ'),
        content: Text('「${r.itemName}」の達成申請を取り下げますか?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('取り下げる')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyItemId = r.itemId);
    try {
      await widget.service.withdrawDevelopmentAchievementRequest(r.requestId!);
      await _load();
      _snack('申請を取り下げました');
    } catch (e) {
      _snack(_friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyItemId = null);
    }
  }

  Future<String?> _promptNote(String title) async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '観察した根拠(任意)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('申請する'),
          ),
        ],
      ),
    );
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('not authorized')) return '担任・担当クラスの職員のみ申請できます';
    if (s.contains('既に達成済み')) return 'この項目は既に達成済みです';
    if (s.contains('既に承認待ち')) return '既に承認待ちの申請があります';
    return '処理に失敗しました: $s';
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade600 : null,
    ));
  }

  List<DevelopmentRecord> get _filtered => _records.where((r) {
        if (_domainFilter != 'all' && r.domainCode != _domainFilter) return false;
        if (_hideAchieved && r.isAchieved) return false;
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final achievedCount = _records.where((r) => r.isAchieved).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ヘッダ + バンド切替
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_header?.className ?? 'クラス未所属'}'
                '${_header?.applicableBand != null ? ' / 適用: ${kDevelopmentBandLabels[_header!.applicableBand] ?? _header!.applicableBand}' : ''}'
                ' / 達成 $achievedCount件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final code in kDevelopmentBandOrder)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            '${kDevelopmentBandLabels[code]}'
                            '${_header?.applicableBand == code ? ' ●' : ''}',
                          ),
                          selected: _band == code,
                          onSelected: (_) {
                            setState(() => _band = code);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 絞り込み
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              DropdownButton<String>(
                value: _domainFilter,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全領域')),
                  for (final e in kDevelopmentDomainLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _domainFilter = v ?? 'all'),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  Checkbox(
                    value: _hideAchieved,
                    onChanged: (v) => setState(() => _hideAchieved = v ?? false),
                  ),
                  const Text('達成済みを隠す'),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_friendlyError(_error!), style: const TextStyle(color: Colors.red)));
    }
    final rows = _filtered;
    if (rows.isEmpty) {
      return const Center(child: Text('該当する項目がありません'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildItem(rows[i]),
    );
  }

  Widget _buildItem(DevelopmentRecord r) {
    final busy = _busyItemId == r.itemId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: r.isAchieved ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: r.isAchieved ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  kDevelopmentDomainLabels[r.domainCode] ?? r.domainCode,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (r.observationPoint != null && r.observationPoint!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(r.observationPoint!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
          if (r.isAchieved)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '達成済み${r.firstAchievedOn != null ? '(${r.firstAchievedOn})' : ''}'
                '${r.approvedByName != null ? ' / 承認: ${r.approvedByName}' : ''}',
                style: TextStyle(fontSize: 12, color: Colors.green.shade800),
              ),
            ),
          if (r.hasPending && !r.isAchieved)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '申請中${r.requestedByName != null ? '(${r.requestedByName})' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => _withdraw(r),
                    child: const Text('取下げ'),
                  ),
                ],
              ),
            ),
          if (!r.isAchieved && !r.hasPending)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.tonal(
                  onPressed: busy ? null : () => _submit(r),
                  child: const Text('達成申請'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
