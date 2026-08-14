import 'package:flutter/material.dart';

import '../../../models/childcare.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ohana_logo_home_button.dart';

/// 園内連絡(156/213・設計書§7/8/10)。
/// 一覧=自施設の全職員が全連絡を閲覧可(掲示板方式)。確認ボタン=宛先該当者のみ。
/// 既定は直近30日・アーカイブ切替で全期間(物理削除なし)。
class StaffMessageListScreen extends StatefulWidget {
  const StaffMessageListScreen({
    super.key,
    required this.service,
    required this.officeId,
    required this.isManager,
  });

  final ChildcareService service;
  final String officeId;
  final bool isManager;

  @override
  State<StaffMessageListScreen> createState() => _StaffMessageListScreenState();
}

class _StaffMessageListScreenState extends State<StaffMessageListScreen> {
  List<({String messageId, String body, DateTime? targetDate, DateTime createdAt,
      String authorEmployeeId, String authorName, List<String> targetLabels,
      bool isAddressedToMe, bool acknowledgedByMe, int ackCount, int addressedCount})> _messages = const [];
  bool _includeArchive = false;
  bool _isLoading = true;
  String? _myEmployeeId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await widget.service.fetchStaffMessages(widget.officeId, includeArchive: _includeArchive);
      final me = await widget.service.fetchMyEmployeeId();
      if (!mounted) return;
      setState(() {
        _messages = list;
        _myEmployeeId = me;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _acknowledge(String messageId) async {
    try {
      await widget.service.acknowledgeStaffMessage(messageId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('確認の記録に失敗しました: $e')));
      }
    }
  }

  Future<void> _delete(String messageId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('この連絡を削除しますか?'),
        content: const Text('一覧から非表示になります(記録は残ります)。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.service.deleteStaffMessage(messageId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
      }
    }
  }

  String _fmt(DateTime d) => '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const OhanaLogoHomeButton(),
        leadingWidth: 148,
        toolbarHeight: 48,
        title: const Text('園内連絡'),
        actions: [
          Row(
            children: [
              const Text('アーカイブ', style: TextStyle(fontSize: 12)),
              Switch(
                value: _includeArchive,
                onChanged: (v) {
                  setState(() => _includeArchive = v);
                  _load();
                },
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showDialog<bool>(
            context: context,
            builder: (_) => _ComposeDialog(service: widget.service, officeId: widget.officeId),
          );
          if (created == true) _load();
        },
        icon: const Icon(Icons.edit_rounded),
        label: const Text('新規連絡'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _messages.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 120),
                        Center(
                            child: Text(_includeArchive ? '連絡はありません' : '直近30日の連絡はありません',
                                style: const TextStyle(color: AppColors.textSecondary))),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final m = _messages[index];
                        final needsAck = m.isAddressedToMe && !m.acknowledgedByMe;
                        return Card(
                          margin: EdgeInsets.zero,
                          shape: needsAck
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: AppColors.warmOrange, width: 1.5))
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(m.authorName,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                    const SizedBox(width: 8),
                                    Text(_fmt(m.createdAt),
                                        style:
                                            const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                    const Spacer(),
                                    if (m.authorEmployeeId == _myEmployeeId || widget.isManager)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                        color: AppColors.textSecondary,
                                        onPressed: () => _delete(m.messageId),
                                      ),
                                  ],
                                ),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    for (final label in m.targetLabels)
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.skyBlue.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                            '宛先: $label${m.targetDate != null ? '(${m.targetDate!.month}/${m.targetDate!.day})' : ''}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.skyBlue)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(m.body, style: const TextStyle(fontSize: 14, height: 1.5)),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Text('確認 ${m.ackCount}/${m.addressedCount}',
                                        style: const TextStyle(
                                            fontSize: 12, color: AppColors.textSecondary)),
                                    const Spacer(),
                                    if (needsAck)
                                      FilledButton.icon(
                                        onPressed: () => _acknowledge(m.messageId),
                                        icon: const Icon(Icons.check_rounded, size: 18),
                                        label: const Text('確認しました'),
                                      )
                                    else if (m.isAddressedToMe)
                                      const Row(
                                        children: [
                                          Icon(Icons.check_circle_rounded,
                                              color: AppColors.leafGreen, size: 18),
                                          SizedBox(width: 4),
                                          Text('確認済み',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.leafGreen)),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// 新規連絡の作成ダイアログ。宛先=施設全体/時間帯/個人/クラス(フラグON施設のみ)。
class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog({required this.service, required this.officeId});

  final ChildcareService service;
  final String officeId;

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final _bodyController = TextEditingController();
  bool _facility = false;
  final Set<String> _bandIds = {};
  final Set<String> _employeeIds = {};
  final Set<String> _classIds = {};
  DateTime _targetDate = DateTime.now().add(const Duration(days: 1));
  List<({String bandId, String name})> _bands = const [];
  List<ChildcareStaffMember> _staff = const [];
  List<ChildcareClass> _classes = const [];
  bool _classMessaging = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final bands = await widget.service.fetchStaffTimeBands(widget.officeId);
      final staff = await widget.service.fetchChildcareOfficeStaff(widget.officeId);
      final classMessaging = await widget.service.isClassMessagingEnabled(widget.officeId);
      final classes = classMessaging ? await widget.service.fetchChildcareClasses(widget.officeId) : <ChildcareClass>[];
      if (!mounted) return;
      setState(() {
        _bands = bands;
        _staff = staff;
        _classMessaging = classMessaging;
        _classes = classes;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  bool get _needsTargetDate => _bandIds.isNotEmpty || _classIds.isNotEmpty;

  Future<void> _send() async {
    final targets = <Map<String, dynamic>>[
      if (_facility) {'type': 'facility'},
      for (final b in _bandIds) {'type': 'band', 'band_id': b},
      for (final e in _employeeIds) {'type': 'individual', 'employee_id': e},
      for (final c in _classIds) {'type': 'class', 'class_id': c},
    ];
    if (_bodyController.text.trim().isEmpty) {
      setState(() => _error = '本文を入力してください');
      return;
    }
    if (targets.isEmpty) {
      setState(() => _error = '宛先を1つ以上選択してください');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.service.createStaffMessage(
        officeId: widget.officeId,
        body: _bodyController.text.trim(),
        targetDate: _needsTargetDate ? _targetDate : null,
        targets: targets,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = '送信に失敗しました: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('園内連絡を送る', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _bodyController,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '連絡内容(例: 明日の早番の方へ…)'),
              ),
              const SizedBox(height: 14),
              const Text('宛先(複数選択可)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 6),
              FilterChip(
                label: const Text('施設全体'),
                selected: _facility,
                onSelected: (v) => setState(() => _facility = v),
              ),
              if (_bands.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('時間帯(対象日のシフトで判定)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Wrap(
                  spacing: 6,
                  children: _bands
                      .map((b) => FilterChip(
                            label: Text(b.name),
                            selected: _bandIds.contains(b.bandId),
                            onSelected: (v) => setState(() {
                              if (v) {
                                _bandIds.add(b.bandId);
                              } else {
                                _bandIds.remove(b.bandId);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ],
              if (_classMessaging && _classes.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('クラス(担任へ)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Wrap(
                  spacing: 6,
                  children: _classes
                      .map((c) => FilterChip(
                            label: Text(c.className),
                            selected: _classIds.contains(c.classId),
                            onSelected: (v) => setState(() {
                              if (v) {
                                _classIds.add(c.classId);
                              } else {
                                _classIds.remove(c.classId);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ],
              if (_staff.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('個人', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _staff
                      .map((m) => FilterChip(
                            label: Text(m.name),
                            selected: _employeeIds.contains(m.employeeId),
                            onSelected: (v) => setState(() {
                              if (v) {
                                _employeeIds.add(m.employeeId);
                              } else {
                                _employeeIds.remove(m.employeeId);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ],
              if (_needsTargetDate) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _targetDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null) setState(() => _targetDate = picked);
                  },
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text('対象日: ${_targetDate.month}/${_targetDate.day}(時間帯・クラス宛てに必須)'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.punchClockOut)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('キャンセル')),
        FilledButton(
          onPressed: _isSaving ? null : _send,
          child: Text(_isSaving ? '送信中…' : '送信する'),
        ),
      ],
    );
  }
}
