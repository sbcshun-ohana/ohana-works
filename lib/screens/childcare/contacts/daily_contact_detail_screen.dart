import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../models/guardian_app.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';
import '../family_daily_report_summary_view.dart';

/// §10-13 連絡帳の入力・AI生成・申請(職員)と承認・差し戻し(管理者)。
/// 管理者はiPad・iPhone(本アプリ)からも承認・差し戻し・コメント・直接編集ができる。
class DailyContactDetailScreen extends StatefulWidget {
  const DailyContactDetailScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.childId,
    required this.childNameLabel,
    required this.businessDate,
    required this.isManager,
    this.embedded = false,
  });

  final ChildcareService service;
  final String officeId;
  final String childId;
  final String childNameLabel;
  final DateTime businessDate;
  final bool isManager;

  /// true のとき Scaffold/AppBar を付けず本体のみ返す(連絡帳の分割ビュー右パネルのタブ用)。
  final bool embedded;

  @override
  State<DailyContactDetailScreen> createState() => _DailyContactDetailScreenState();
}

class _DailyContactDetailScreenState extends State<DailyContactDetailScreen> {
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  String? _myEmployeeId;
  DailyContact? _contact;
  FamilyDailyReportSummary? _familyDailyReport;
  List<NoticeMaster> _noticeMasters = const [];
  Set<String> _checkedNoticeIds = {};
  List<({String itemName, int quantity})> _supplyItems = const [];

  final _guardianController = TextEditingController();
  final _todayNotesController = TextEditingController();
  final _freeNotesController = TextEditingController();
  final _currentTextController = TextEditingController();
  final _adminCommentController = TextEditingController();
  final _supplyItemController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _guardianController.dispose();
    _todayNotesController.dispose();
    _freeNotesController.dispose();
    _currentTextController.dispose();
    _adminCommentController.dispose();
    _supplyItemController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _myEmployeeId = await widget.service.fetchMyEmployeeId();
      final contactId =
          await widget.service.ensureChildDailyContact(widget.childId, widget.businessDate);
      final contact = await widget.service.fetchDailyContactDetail(contactId);
      final results = await Future.wait([
        widget.service.fetchNoticeMasters(widget.officeId),
        widget.service.fetchCheckedNoticeIds(contactId),
        widget.service.fetchSupplyItems(contactId),
        widget.service.fetchFamilyDailyReportForStaff(widget.childId, widget.businessDate),
      ]);
      _guardianController.text = contact.guardianMessage ?? '';
      _todayNotesController.text = contact.childTodayNotes ?? '';
      _freeNotesController.text = contact.freeNotes ?? '';
      _currentTextController.text = contact.currentText ?? contact.aiGeneratedText ?? '';
      setState(() {
        _contact = contact;
        _noticeMasters = results[0] as List<NoticeMaster>;
        _checkedNoticeIds = results[1] as Set<String>;
        _supplyItems = results[2] as List<({String itemName, int quantity})>;
        _familyDailyReport = results[3] as FamilyDailyReportSummary?;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isAssignee =>
      _contact?.assigneeEmployeeId != null && _contact!.assigneeEmployeeId == _myEmployeeId;

  bool get _canEditInput =>
      widget.isManager || (_isAssignee && (_contact?.status == 'draft' || _contact?.status == 'rejected'));

  bool get _canSubmit => _isAssignee && (_contact?.status == 'draft' || _contact?.status == 'rejected');

  // 207: 担当者変更ダイアログ。施設の在籍職員一覧から1タップで担当を渡す。
  Future<void> _changeAssignee() async {
    final List<ChildcareStaffMember> staff;
    try {
      staff = await widget.service.fetchChildcareOfficeStaff(widget.officeId);
    } catch (_) {
      return;
    }
    if (!mounted || staff.isEmpty) return;
    final selected = await showDialog<ChildcareStaffMember>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('担当者を選択', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        children: staff
            .map(
              (m) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        m.employeeId == _contact?.assigneeEmployeeId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: AppColors.skyBlue,
                      ),
                      const SizedBox(width: 8),
                      Text(m.name, style: const TextStyle(fontSize: 15)),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null || _contact?.contactId == null) return;
    await _run(
      () => widget.service.setDailyContactAssignee(_contact!.contactId!, selected.employeeId),
      successMessage: '担当を${selected.name}さんに変更しました',
    );
  }

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await action();
      await _load();
      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (_) {
      setState(() => _errorMessage = '処理に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _saveInput() async {
    await widget.service.updateDailyContactInput(
      _contact!.contactId!,
      guardianMessage: _guardianController.text.trim().isEmpty ? null : _guardianController.text.trim(),
      childTodayNotes:
          _todayNotesController.text.trim().isEmpty ? null : _todayNotesController.text.trim(),
      freeNotes: _freeNotesController.text.trim().isEmpty ? null : _freeNotesController.text.trim(),
    );
    await widget.service.saveCurrentText(_contact!.contactId!, _currentTextController.text, isInitial: false);
  }

  Future<void> _toggleNotice(NoticeMaster notice) => _run(() async {
        await widget.service.setNoticeChecked(
          contactId: _contact!.contactId!,
          noticeMasterId: notice.id,
          checked: !_checkedNoticeIds.contains(notice.id),
        );
      });

  Future<void> _addSupplyItem() async {
    final itemName = _supplyItemController.text.trim();
    if (itemName.isEmpty) return;
    await _run(() async {
      await widget.service.addSupplyItem(contactId: _contact!.contactId!, itemName: itemName, quantity: 1);
      _supplyItemController.clear();
    });
  }

  Future<void> _runAi(ContactAiAction action) => _run(() async {
        await _saveInput();
        final result = await widget.service.generateContactNote(
          childId: widget.childId,
          businessDate: widget.businessDate,
          action: action,
          currentText: _currentTextController.text.isEmpty ? null : _currentTextController.text,
        );
        _currentTextController.text = result.contactText;
        final isInitial = action == ContactAiAction.generate || action == ContactAiAction.regenerate;
        await widget.service.saveCurrentText(_contact!.contactId!, result.contactText, isInitial: isInitial);
        if (result.journalSections != null) {
          await widget.service.saveGeneratedJournal(
            childId: widget.childId,
            businessDate: widget.businessDate,
            sections: result.journalSections!,
          );
        }
      });

  Future<void> _submit() => _run(() async {
        await _saveInput();
        await widget.service.submitChildDailyContact(_contact!.contactId!);
      }, successMessage: '申請しました');

  Future<void> _approve() => _run(
        () => widget.service.approveChildDailyContact(
          _contact!.contactId!,
          finalText: _currentTextController.text,
          adminComment: _adminCommentController.text.trim().isEmpty ? null : _adminCommentController.text.trim(),
        ),
        successMessage: '承認しました',
      );

  Future<void> _reject() async {
    final reason = await _promptText('差し戻し理由(必須)');
    if (reason == null || reason.trim().isEmpty) return;
    await _run(
      () => widget.service.rejectChildDailyContact(_contact!.contactId!, reason.trim()),
      successMessage: '差し戻しました',
    );
  }

  Future<String?> _promptText(String title) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('決定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('担当: ${_contact?.assigneeName ?? "未割当"}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      // 未割当のとき、自分を担当にできる(200 claim_child_daily_contact。draft/rejectedのみ)。
                      if (_contact?.assigneeEmployeeId == null &&
                          (_contact?.status == 'draft' || _contact?.status == 'rejected')) ...[
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _isBusy
                              ? null
                              : () => _run(() => widget.service.claimDailyContact(_contact!.contactId!),
                                  successMessage: '担当になりました'),
                          child: const Text('自分を担当にする'),
                        ),
                      ],
                      // 207+俊指示(2026-08-14): 担当を他の職員へ渡す(下書き/差し戻し中のみ)。
                      if (_contact?.contactId != null &&
                          (_contact?.status == 'draft' || _contact?.status == 'rejected')) ...[
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _isBusy ? null : _changeAssignee,
                          child: const Text('変更'),
                        ),
                      ],
                    ],
                  ),
                  if (_contact?.rejectedReason != null) ...[
                    const SizedBox(height: 12),
                    _banner(AppColors.punchClockOut, '差し戻し理由: ${_contact!.rejectedReason}'),
                  ],
                  if (_contact?.adminComment != null) ...[
                    const SizedBox(height: 12),
                    _banner(AppColors.warmOrange, '管理者コメント(保護者非公開): ${_contact!.adminComment}'),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    color: AppColors.background,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '保護者記入(家庭連絡帳)',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          FamilyDailyReportSummaryView(report: _familyDailyReport),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _field('保護者からの連絡内容', _guardianController, enabled: _canEditInput, maxLines: 2),
                  _field('今日の園児の様子', _todayNotesController, enabled: _canEditInput, maxLines: 2),
                  _field('その他自由記載', _freeNotesController, enabled: _canEditInput, maxLines: 2),
                  const Text('個別のお知らせ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _noticeMasters
                        .map(
                          (notice) => FilterChip(
                            label: Text(notice.label),
                            selected: _checkedNoticeIds.contains(notice.id),
                            onSelected: _canEditInput ? (_) => _toggleNotice(notice) : null,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('備品利用の記録', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  for (final item in _supplyItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('・${item.itemName} × ${item.quantity}'),
                    ),
                  if (_canEditInput)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _supplyItemController,
                            decoration: const InputDecoration(hintText: '品目(例: おしりふき)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(onPressed: _addSupplyItem, child: const Text('追加')),
                      ],
                    ),
                  const SizedBox(height: 20),
                  const Text('連絡帳本文(保護者向け)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _currentTextController,
                    enabled: _canEditInput,
                    maxLines: 6,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ContactAiAction.values
                        .map(
                          (action) => OutlinedButton(
                            onPressed: (_isBusy || !_canEditInput) ? null : () => _runAi(action),
                            child: Text(action.label),
                          ),
                        )
                        .toList(),
                  ),
                  if (widget.isManager && _contact?.status == 'submitted') ...[
                    const SizedBox(height: 20),
                    const Text(
                      '職員向けコメント(保護者向け本文には含まれません)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: _adminCommentController, maxLines: 2),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 24),
                  if (_canEditInput)
                    OutlinedButton(
                      onPressed: _isBusy ? null : () => _run(_saveInput),
                      child: const Text('下書き保存'),
                    ),
                  const SizedBox(height: 12),
                  if (_canSubmit)
                    ElevatedButton(onPressed: _isBusy ? null : _submit, child: const Text('申請する')),
                  if (widget.isManager && _contact?.status == 'submitted') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isBusy ? null : _reject,
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.punchClockOut),
                            child: const Text('差し戻す'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isBusy ? null : _approve,
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.leafGreen),
                            child: const Text('承認する'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        toolbarHeight: 48,
        title: Text(widget.childNameLabel),
      ),
      body: body,
    );
  }

  Widget _banner(Color color, String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
      child: Text(text),
    );
  }

  Widget _field(String label, TextEditingController controller, {required bool enabled, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(controller: controller, enabled: enabled, maxLines: maxLines),
        ],
      ),
    );
  }
}
