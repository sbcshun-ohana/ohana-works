import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/now_clock.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// §8 クラス活動の入力・申請(職員)と承認・差し戻し(管理者)。
/// 管理者はiPad・iPhone(本アプリ)からも承認・差し戻し・担当者変更ができる。
class ClassActivityDetailScreen extends StatefulWidget {
  const ClassActivityDetailScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.classId,
    required this.className,
    required this.businessDate,
    required this.isManager,
  });

  final ChildcareService service;
  final String officeId;
  final String classId;
  final String className;
  final DateTime businessDate;
  final bool isManager;

  @override
  State<ClassActivityDetailScreen> createState() => _ClassActivityDetailScreenState();
}

class _ClassActivityDetailScreenState extends State<ClassActivityDetailScreen> {
  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  String? _myEmployeeId;
  ClassActivity? _activity;
  List<ChildcareStaffMember> _staff = const [];

  final _themeController = TextEditingController();
  final _contentController = TextEditingController();
  final _overviewController = TextEditingController();
  final _announcementController = TextEditingController();
  final _otherController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _themeController.dispose();
    _contentController.dispose();
    _overviewController.dispose();
    _announcementController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _myEmployeeId = await widget.service.fetchMyEmployeeId();
      final activityId =
          await widget.service.ensureClassDailyActivity(widget.classId, widget.businessDate);
      final activity = await widget.service.fetchClassActivityDetail(activityId);
      if (widget.isManager) {
        _staff = await widget.service.fetchChildcareOfficeStaff(widget.officeId);
      }
      _themeController.text = activity.todayTheme ?? '';
      _contentController.text = activity.activityContent ?? '';
      _overviewController.text = activity.classOverview ?? '';
      _announcementController.text = activity.classAnnouncement ?? '';
      _otherController.text = activity.otherNotes ?? '';
      setState(() => _activity = activity);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isAssignee =>
      _activity?.assigneeEmployeeId != null && _activity!.assigneeEmployeeId == _myEmployeeId;

  bool get _canEditContent =>
      widget.isManager || (_isAssignee && (_activity?.status == 'draft' || _activity?.status == 'rejected'));

  bool get _canSubmit => _isAssignee && (_activity?.status == 'draft' || _activity?.status == 'rejected');

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

  Future<void> _saveContent() => _run(() => widget.service.updateClassActivityContent(
        _activity!.activityId!,
        todayTheme: _themeController.text.trim().isEmpty ? null : _themeController.text.trim(),
        activityContent:
            _contentController.text.trim().isEmpty ? null : _contentController.text.trim(),
        classOverview:
            _overviewController.text.trim().isEmpty ? null : _overviewController.text.trim(),
        classAnnouncement:
            _announcementController.text.trim().isEmpty ? null : _announcementController.text.trim(),
        otherNotes: _otherController.text.trim().isEmpty ? null : _otherController.text.trim(),
      ));

  Future<void> _claim() => _run(() => widget.service.claimClassActivity(_activity!.activityId!));

  Future<void> _submit() => _run(() async {
        await _saveContent();
        await widget.service.submitClassActivity(_activity!.activityId!);
      }, successMessage: '申請しました');

  Future<void> _approve() =>
      _run(() => widget.service.approveClassActivity(_activity!.activityId!), successMessage: '承認しました');

  Future<void> _reject() async {
    final reason = await _promptText('差し戻し理由(必須)');
    if (reason == null || reason.trim().isEmpty) return;
    await _run(
      () => widget.service.rejectClassActivity(_activity!.activityId!, reason.trim()),
      successMessage: '差し戻しました',
    );
  }

  Future<void> _reassign(ChildcareStaffMember member) => _run(
        () => widget.service.reassignClassActivity(_activity!.activityId!, member.employeeId),
        successMessage: '担当者を変更しました',
      );

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
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaBackHomeLeading(),
        leadingWidth: 200,
        toolbarHeight: 48,
        title: Text(widget.className),
        actions: const [NowClock()],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '担当: ${_activity?.assigneeName ?? "未割当"}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_activity?.assigneeEmployeeId == null)
                        OutlinedButton(onPressed: _claim, child: const Text('自分を担当にする')),
                    ],
                  ),
                  if (widget.isManager && _staff.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DropdownButton<ChildcareStaffMember>(
                      hint: const Text('担当者を変更…'),
                      isExpanded: true,
                      items: _staff
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                          .toList(),
                      onChanged: (member) {
                        if (member != null) _reassign(member);
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_activity?.rejectedReason != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.punchClockOut.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text('差し戻し理由: ${_activity!.rejectedReason}'),
                    ),
                  _field('今日の活動のねらい', _themeController, enabled: _canEditContent),
                  _field('活動内容', _contentController, enabled: _canEditContent, maxLines: 3),
                  _field('子どもたちの様子', _overviewController, enabled: _canEditContent, maxLines: 3),
                  _field('クラス全体へのお知らせ', _announcementController, enabled: _canEditContent),
                  _field('その他', _otherController, enabled: _canEditContent),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 24),
                  if (_canEditContent)
                    OutlinedButton(
                      onPressed: _isBusy ? null : _saveContent,
                      child: const Text('下書き保存'),
                    ),
                  const SizedBox(height: 12),
                  if (_canSubmit)
                    ElevatedButton(
                      onPressed: _isBusy ? null : _submit,
                      child: const Text('申請する'),
                    ),
                  if (widget.isManager && _activity?.status == 'submitted') ...[
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
            ),
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
