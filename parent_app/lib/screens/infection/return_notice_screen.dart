import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/time_dropdown_picker.dart';

/// 電子登園届(211・設計書§3.5)。
/// 確認項目はマスターの宣言的ルールから動的生成。全条件充足時のみ提出可能(未達理由を表示)。
/// 提出後は修正不可(提出時の内容・マスター版で凍結)。
class ReturnNoticeScreen extends StatefulWidget {
  const ReturnNoticeScreen({
    super.key,
    required this.guardianService,
    required this.child,
    required this.caseId,
  });

  final GuardianService guardianService;
  final LinkedChild child;
  final String caseId;

  @override
  State<ReturnNoticeScreen> createState() => _ReturnNoticeScreenState();
}

class _ReturnNoticeScreenState extends State<ReturnNoticeScreen> {
  String? _diseaseName;
  String? _returnCriteria;
  List<String> _checks = const [];
  String? _dateLabel;
  int? _minHours;
  final Map<String, bool> _checked = {};
  DateTime? _baseAt;
  bool _declared = false;
  bool _submitted = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ctx = await widget.guardianService.fetchReturnNoticeContext(widget.caseId);
      if (!mounted) return;
      setState(() {
        _diseaseName = ctx.diseaseName;
        _returnCriteria = ctx.returnCriteria;
        _checks = ctx.checks;
        _dateLabel = ctx.dateConditionLabel;
        _minHours = ctx.dateConditionMinHours;
        final notice = ctx.notice;
        _submitted = notice?['status'] == 'submitted';
        final inputs = (notice?['inputs'] as Map<String, dynamic>?) ?? const {};
        for (final c in (inputs['checks'] as List?) ?? const []) {
          final m = c as Map<String, dynamic>;
          _checked[m['label'] as String] = m['checked'] == true;
        }
        final base = inputs['date_condition_base_at'] as String?;
        if (base != null) _baseAt = DateTime.tryParse(base)?.toLocal();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _buildInputs() => {
        'checks': [
          for (final label in _checks) {'label': label, 'checked': _checked[label] ?? false},
        ],
        if (_baseAt != null) 'date_condition_base_at': _baseAt!.toUtc().toIso8601String(),
      };

  bool get _allChecked => _checks.every((c) => _checked[c] ?? false);
  bool get _dateOk {
    if (_dateLabel == null) return true;
    if (_baseAt == null || _minHours == null) return false;
    return DateTime.now().isAfter(_baseAt!.add(Duration(hours: _minHours!)));
  }

  List<String> get _unmetReasons {
    final reasons = <String>[];
    for (final c in _checks) {
      if (!(_checked[c] ?? false)) reasons.add('「$c」が未確認です');
    }
    if (_dateLabel != null) {
      if (_baseAt == null) {
        reasons.add('$_dateLabelが入力されていません');
      } else if (!_dateOk) {
        reasons.add('$_dateLabelから$_minHours時間が経過していません');
      }
    }
    if (!_declared) reasons.add('提出内容の確認チェックが必要です');
    return reasons;
  }

  Future<void> _saveDraft() async {
    setState(() => _isSaving = true);
    try {
      await widget.guardianService.saveReturnNoticeDraft(widget.caseId, _buildInputs());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下書きを保存しました')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.guardianService.submitReturnNotice(widget.caseId, _buildInputs());
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('登園届を提出しました。ご協力ありがとうございます')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = '提出できませんでした: $e';
        });
      }
    }
  }

  Future<void> _pickBaseAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _baseAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 14)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimeDropdownPicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_baseAt ?? DateTime.now()));
    if (time == null) return;
    setState(() => _baseAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _allChecked && _dateOk && _declared && !_isSaving;
    return Scaffold(
      appBar: AppBar(title: Text('登園届(${widget.child.nameLabel})')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _submitted
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.leafGreen, size: 48),
                        const SizedBox(height: 12),
                        Text('$_diseaseNameの登園届は提出済みです',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 6),
                        const Text('提出後の内容修正はできません。変更が必要な場合は園へご連絡ください',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('感染症: ${_diseaseName ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (_returnCriteria != null) ...[
                      const SizedBox(height: 6),
                      Text('登園のめやす: $_returnCriteria',
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                    const Divider(height: 28),
                    const Text('お子さまの状態を確認してチェックしてください',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    for (final label in _checks)
                      CheckboxListTile(
                        value: _checked[label] ?? false,
                        onChanged: (v) => setState(() => _checked[label] = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(label),
                      ),
                    if (_dateLabel != null) ...[
                      const SizedBox(height: 8),
                      Text(_dateLabel!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _pickBaseAt,
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(_baseAt == null
                            ? '日時を選択'
                            : '${_baseAt!.month}/${_baseAt!.day} ${_baseAt!.hour.toString().padLeft(2, '0')}:${_baseAt!.minute.toString().padLeft(2, '0')}'),
                      ),
                      if (_minHours != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('$_dateLabelから$_minHours時間の経過が必要です',
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ),
                    ],
                    const Divider(height: 28),
                    CheckboxListTile(
                      value: _declared,
                      onChanged: (v) => setState(() => _declared = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('上記内容を確認し、この内容で登園届を提出します'),
                    ),
                    if (!canSubmit && _unmetReasons.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warmOrange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('提出には以下の確認が必要です:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            for (final r in _unmetReasons)
                              Text('・$r', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isSaving ? null : _saveDraft,
                            child: const Text('下書き保存'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: canSubmit ? _submit : null,
                            child: Text(_isSaving ? '送信中…' : '提出する'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }
}
