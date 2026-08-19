import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import 'incident_common.dart';
import 'incident_form_screen.dart';

/// ヒヤリハット・事故報告の詳細(閲覧+状態別アクション)。
class IncidentDetailScreen extends StatefulWidget {
  const IncidentDetailScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.reportId,
    required this.isManager,
  });

  final ChildcareService service;
  final String officeId;
  final String reportId;
  final bool isManager;

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _d = const {};
  Map<String, dynamic>? _closure;
  bool _changed = false;

  Map<String, dynamic> get _r => (_d['report'] as Map?)?.cast<String, dynamic>() ?? const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.service.fetchIncidentReportDetail(widget.reportId);
      final closure = await widget.service.fetchIncidentClosure(widget.reportId);
      if (!mounted) return;
      setState(() {
        _d = d;
        _closure = closure;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '取得に失敗しました'; _loading = false; });
    }
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作できません: ${_clean(e)}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clean(Object e) {
    final s = e.toString();
    if (s.contains('not authorized')) return '権限がありません';
    if (s.contains('invalid state')) return '対象の状態が変わっています';
    return s;
  }

  Future<String?> _askReason(String title) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '理由を入力', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('実行')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('報告書')),
        bottomNavigationBar: _loading ? null : _actionBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : RefreshIndicator(onRefresh: _load, child: _body()),
      ),
    );
  }

  Widget _body() {
    final r = _r;
    final status = r['status'] as String?;
    final rejected = r['rejected_reason'] as String?;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        Row(children: [
          IncidentTypeBadge(reportType: r['report_type'] as String?),
          const SizedBox(width: 8),
          IncidentStatusBadge(status: status),
        ]),
        const SizedBox(height: 12),
        if (rejected != null && rejected.isNotEmpty && status == 'draft')
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.punchClockOut.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('差し戻し理由: $rejected', style: const TextStyle(color: AppColors.punchClockOut)),
          ),
        _kv('発生日時', '${_fmtDate(r['occurred_on'])} ${_fmtTime(r['occurred_at'])}'),
        _kv('発生場所', (_d['place_label'] as String?) ?? '-'),
        _kv('記入者', (_d['created_by_name'] as String?) ?? '-'),
        _kv('対象園児', _childNames()),

        _section('発生状況'),
        _kv('いつ', r['situation_when'] as String?),
        _kv('どこで', r['situation_where'] as String?),
        _kv('何をしたとき', r['situation_what'] as String?),
        _kv('どうなった', r['situation_result'] as String?),

        _section('現場の人員'),
        _kv('人数', _staffCounts()),

        _section('原因・問題点'),
        ..._causes(),

        if (r['report_type'] != 'hiyari') ...[
          _section('発生後の対応'),
          _kv('受傷部位', (_d['injury_site_label'] as String?) ?? '-'),
          _kv('受傷内容', r['injury_detail'] as String?),
          _kv('応急処置', r['first_aid'] as String?),
        ],

        _section('経過と観察記録'),
        ..._progressList(),

        _section('保護者連絡'),
        ..._guardianList(),

        if (r['report_type'] == 'hospital') ...[
          _section('受診記録'),
          ..._medicalList(),
        ],

        _section('再発防止'),
        _kv('', r['prevention_text'] as String?),
        if ((r['note_text'] as String?)?.isNotEmpty == true) ...[
          _section('その他'),
          _kv('', r['note_text'] as String?),
        ],

        if (r['report_type'] != 'hiyari') ...[
          _section('保護者対応(クロージング)'),
          ..._closureRows(),
        ],

        _section('承認情報'),
        _kv('主任承認', _d['chief_approved_by_name'] as String?),
        _kv('園長承認', _d['approved_by_name'] as String?),
      ],
    );
  }

  List<Widget> _closureRows() {
    final cs = _closure?['closure_status'] as String?;
    final missing = ((_closure?['missing'] as List?) ?? const []).map((e) => '$e').toList();
    final out = <Widget>[];
    if (cs == 'closed') {
      out.add(_kv('状態', 'クローズ済'));
      out.add(_kv('クローズ',
          '${(_closure?['closed_by_name'] as String?) ?? '-'}  ${_fmtDateTime(_closure?['closed_at'])}'));
      if (_closure?['reopened_at'] != null) {
        out.add(_kv('再オープン',
            '${(_closure?['reopened_by_name'] as String?) ?? '-'}  ${_fmtDateTime(_closure?['reopened_at'])}'));
      }
    } else if (cs == 'open') {
      out.add(_kv('状態', '未クローズ'));
      out.add(_kv('不足', missing.isEmpty ? 'なし(クローズ可能)' : missing.join('、')));
    } else {
      out.add(_kv('状態', '-'));
    }
    if ((_closure?['closure_note'] as String?)?.isNotEmpty == true) {
      out.add(_kv('メモ', _closure?['closure_note'] as String?));
    }
    return out;
  }

  String _childNames() {
    final list = (_d['children'] as List?) ?? const [];
    if (list.isEmpty) return '-';
    return list.map((c) => (c as Map)['child_name_snapshot'] ?? '').where((s) => '$s'.isNotEmpty).join('、');
  }

  String _staffCounts() {
    final m = (_r['staff_counts'] as Map?)?.cast<String, dynamic>() ?? {};
    String v(String k) => '${m[k] ?? 0}';
    return '保育士 ${v('hoiku')}名 / 園児 ${v('jido')}名 / 目撃者 ${v('witness')}名';
  }

  List<Widget> _causes() {
    final m = (_r['causes'] as Map?)?.cast<String, dynamic>() ?? {};
    final out = <Widget>[];
    for (final e in IncidentLabels.causeKeys.entries) {
      final v = m[e.key] as String?;
      if (v != null && v.isNotEmpty) out.add(_kv(e.value, v));
    }
    if (out.isEmpty) out.add(_kv('', '-'));
    return out;
  }

  List<Widget> _progressList() {
    final list = (_d['progress_logs'] as List?) ?? const [];
    if (list.isEmpty) return [_kv('', '記録なし')];
    return [
      for (final p in list)
        _logTile(
          _fmtDateTime((p as Map)['logged_at']),
          '${IncidentLabels.progressKinds[p['report_kind']] ?? ''}${(p['report_text'] as String?)?.isNotEmpty == true ? '  ${p['report_text']}' : ''}',
        ),
    ];
  }

  List<Widget> _guardianList() {
    final list = (_d['guardian_contacts'] as List?) ?? const [];
    if (list.isEmpty) return [_kv('', '記録なし')];
    return [
      for (final g in list)
        _logTile(
          '${_fmtDateTime((g as Map)['contacted_at'])}  ・  ${g['contact_book_written'] == true ? '連絡帳に記載' : '口頭で直接'}',
          '${IncidentLabels.reactionKinds[g['reaction_kind']] ?? ''}'
          '${(g['reaction_text'] as String?)?.isNotEmpty == true ? '  ${g['reaction_text']}' : ''}',
        ),
    ];
  }

  List<Widget> _medicalList() {
    final list = (_d['medical_visits'] as List?) ?? const [];
    if (list.isEmpty) return [_kv('', '記録なし')];
    return [
      for (final mv in list)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${(mv as Map)['medical_institution'] ?? '医療機関未記入'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (mv['doctor_name'] != null) Text('医師: ${mv['doctor_name']}'),
                if (mv['exam_detail'] != null) Text('内容: ${mv['exam_detail']}'),
                if (mv['doctor_instruction'] != null)
                  Text('医師の指示: ${IncidentLabels.doctorInstructions[mv['doctor_instruction']] ?? ''}'),
                if (mv['prescription_present'] == true)
                  Text('処方薬あり${mv['prescription_detail'] != null ? ': ${mv['prescription_detail']}' : ''}'),
                if (mv['treatment_period'] != null) Text('治療期間: ${mv['treatment_period']}'),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _actionBar() {
    final status = _r['status'] as String?;
    final buttons = <Widget>[];

    void add(String label, IconData icon, VoidCallback onTap, {Color? color}) {
      buttons.add(Padding(
        padding: const EdgeInsets.only(left: 8),
        child: FilledButton.icon(
          style: color != null ? FilledButton.styleFrom(backgroundColor: color) : null,
          onPressed: _busy ? null : onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      ));
    }

    if (status == 'draft') {
      buttons.add(OutlinedButton.icon(
        onPressed: _busy ? null : _edit,
        icon: const Icon(Icons.edit, size: 18),
        label: const Text('編集'),
      ));
      add('申請する', Icons.send, () => _run(() => widget.service.submitIncidentReport(widget.reportId), '申請しました'));
    } else if (status == 'submitted' && widget.isManager) {
      add('差し戻し', Icons.undo, _reject, color: AppColors.punchClockOut);
      add('主任承認', Icons.check, () => _run(() => widget.service.chiefApproveIncidentReport(widget.reportId), '主任承認しました'));
    } else if (status == 'chief_approved' && widget.isManager) {
      add('差し戻し', Icons.undo, _reject, color: AppColors.punchClockOut);
      add('園長承認', Icons.verified, () => _run(() => widget.service.approveIncidentReport(widget.reportId), '承認しました'));
    } else if (status == 'approved' && widget.isManager) {
      add('経過を追記', Icons.add_comment, _addProgress);
      add('承認取消', Icons.cancel, _cancel, color: AppColors.punchClockOut);
    }

    // 保護者対応クローズ/解除(事故報告書のみ・申請中以降・主任以上)
    final rt = _r['report_type'] as String?;
    final cs = _closure?['closure_status'] as String?;
    if (rt != 'hiyari' && status != 'draft' && widget.isManager) {
      if (cs == 'open') {
        final ready = _closure?['is_ready'] == true;
        buttons.add(Padding(
          padding: const EdgeInsets.only(left: 8),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.leafGreen),
            onPressed: (_busy || !ready) ? null : _close,
            icon: const Icon(Icons.task_alt, size: 18),
            label: const Text('保護者対応クローズ'),
          ),
        ));
      } else if (cs == 'closed') {
        add('クローズ解除', Icons.lock_open, _reopen, color: AppColors.punchClockOut);
      }
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
      ),
    );
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => IncidentFormScreen(service: widget.service, officeId: widget.officeId, reportId: widget.reportId),
    ));
    if (changed == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _reject() async {
    final reason = await _askReason('差し戻しの理由');
    if (reason == null || reason.isEmpty) return;
    await _run(() => widget.service.rejectIncidentReport(widget.reportId, reason), '差し戻しました');
  }

  Future<void> _cancel() async {
    final reason = await _askReason('承認取消の理由');
    if (reason == null || reason.isEmpty) return;
    await _run(() => widget.service.cancelIncidentApproval(widget.reportId, reason), '承認を取り消しました');
  }

  Future<void> _close() async {
    final note = await _askReason('保護者対応クローズ(コメント任意・空でも可)');
    if (note == null) return; // キャンセル
    await _run(() => widget.service.closeIncidentReport(widget.reportId, note.isEmpty ? null : note), 'クローズしました');
  }

  Future<void> _reopen() async {
    final reason = await _askReason('クローズ解除の理由(必須)');
    if (reason == null || reason.isEmpty) return;
    await _run(() => widget.service.reopenIncidentClosure(widget.reportId, reason), 'クローズを解除しました');
  }

  Future<void> _addProgress() async {
    final c = TextEditingController();
    String kind = 'ok';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('経過を追記'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<String>(
                groupValue: kind,
                onChanged: (v) => setLocal(() => kind = v!),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in IncidentLabels.progressKinds.entries)
                      RadioListTile<String>(
                        dense: true,
                        value: e.key,
                        title: Text(e.value),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: c,
                maxLines: 2,
                decoration: const InputDecoration(hintText: '内容(その他の場合)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('追記')),
          ],
        );
      }),
    );
    if (ok != true) return;
    await _run(
      () => widget.service.addIncidentProgressLog(
        reportId: widget.reportId,
        loggedAt: DateTime.now(),
        reportKind: kind,
        reportText: c.text.trim(),
      ),
      '追記しました',
    );
  }

  // ---- 表示部品 ----
  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.leafGreen)),
      );

  Widget _kv(String k, String? v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (k.isNotEmpty)
              SizedBox(
                width: 96,
                child: Text(k, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
            Expanded(child: Text((v == null || v.isEmpty) ? '-' : v)),
          ],
        ),
      );

  Widget _logTile(String head, String body) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF3F5F7), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(head, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const SizedBox(height: 2),
            Text(body),
          ],
        ),
      );

  String _fmtDate(dynamic iso) {
    final d = DateTime.tryParse('$iso');
    return d == null ? '' : '${d.year}/${d.month}/${d.day}';
  }

  String _fmtTime(dynamic t) {
    if (t == null) return '';
    final parts = '$t'.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : '$t';
  }

  String _fmtDateTime(dynamic iso) {
    final d = DateTime.tryParse('$iso');
    if (d == null) return '$iso';
    return '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
