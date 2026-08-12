import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../models/parent_request.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/child_context_app_bar_title.dart';

/// 保護者からの申請・連絡の新規作成(欠席/遅刻/早退/お迎えの方の変更/その他連絡)。
/// detailsのキーはadmin_web側の汎用表示(key: value)にそのまま表示されるため日本語で統一する。
/// 欠席が感染症による場合は、details内(感染症により欠席・感染症の種類)にチェック結果を格納する
/// (感染症は独立した申請種類ではない)。
class NewParentRequestScreen extends StatefulWidget {
  const NewParentRequestScreen({
    super.key,
    required this.guardianService,
    required this.child,
    required this.guardianId,
  });

  final GuardianService guardianService;
  final LinkedChild child;
  final String guardianId;

  @override
  State<NewParentRequestScreen> createState() => _NewParentRequestScreenState();
}

class _NewParentRequestScreenState extends State<NewParentRequestScreen> {
  String _requestType = 'absence';
  DateTime _targetDate = DateTime.now();
  // 欠席の期間(任意・終了日)と種別(必須)。終了日は target_date 以降31日以内(DBのCHECKに一致)。
  DateTime? _endDate;
  String? _absenceKind; // 'sick_absence' | 'personal_absence'
  static const int _absenceMaxSpanDays = 31;
  final _reasonController = TextEditingController();
  final _otherMessageController = TextEditingController();
  TimeOfDay? _time;
  final _pickupNameController = TextEditingController();
  final _pickupRelationController = TextEditingController();
  final _pickupPhoneController = TextEditingController();

  bool _isInfectiousAbsence = false;
  final Set<String> _selectedDiseaseNames = {};
  Future<List<InfectiousDiseaseMaster>>? _diseasesFuture;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _diseasesFuture = widget.guardianService.fetchInfectiousDiseaseMasters(widget.child.officeId);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _otherMessageController.dispose();
    _pickupNameController.dispose();
    _pickupRelationController.dispose();
    _pickupPhoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() {
        _targetDate = picked;
        // 開始日を変えたら、範囲外になった終了日はクリア(単日へ戻す)。
        if (_endDate != null &&
            (_endDate!.isBefore(_targetDate) ||
                _endDate!.isAfter(_targetDate.add(const Duration(days: _absenceMaxSpanDays))))) {
          _endDate = null;
        }
      });
    }
  }

  // 欠席の終了日(任意)。target_date 以降・31日以内のみ選択可(DBのCHECKに合わせフォームで制限)。
  Future<void> _pickEndDate() async {
    final first = _targetDate;
    final last = _targetDate.add(const Duration(days: _absenceMaxSpanDays));
    final init = (_endDate != null && !_endDate!.isBefore(first) && !_endDate!.isAfter(last)) ? _endDate! : first;
    final picked = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: last);
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time ?? TimeOfDay.now());
    if (picked != null) setState(() => _time = picked);
  }

  String _formatTimeOfDay(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> _buildDetails() {
    switch (_requestType) {
      case 'tardiness':
        return {
          if (_time != null) '到着予定時刻': _formatTimeOfDay(_time!),
          if (_reasonController.text.trim().isNotEmpty) '理由': _reasonController.text.trim(),
        };
      case 'early_leave':
        return {
          if (_time != null) '降園予定時刻': _formatTimeOfDay(_time!),
          if (_reasonController.text.trim().isNotEmpty) '理由': _reasonController.text.trim(),
        };
      case 'pickup_person_change':
        return {
          'お迎えの方の氏名': _pickupNameController.text.trim(),
          '続柄': _pickupRelationController.text.trim(),
          if (_pickupPhoneController.text.trim().isNotEmpty) '電話番号': _pickupPhoneController.text.trim(),
          if (_reasonController.text.trim().isNotEmpty) '備考': _reasonController.text.trim(),
        };
      case 'other':
        return {'連絡内容': _otherMessageController.text.trim()};
      case 'absence':
      default:
        return {
          if (_isInfectiousAbsence) '感染症により欠席': 'はい',
          if (_isInfectiousAbsence && _selectedDiseaseNames.isNotEmpty)
            '感染症の種類': _selectedDiseaseNames.join('、'),
          if (_reasonController.text.trim().isNotEmpty) '理由': _reasonController.text.trim(),
        };
    }
  }

  String? _validate() {
    if (_requestType == 'absence' && _absenceKind == null) {
      return '欠席の種別(病気・家庭の都合)を選択してください';
    }
    if (_requestType == 'pickup_person_change' && _pickupNameController.text.trim().isEmpty) {
      return 'お迎えの方の氏名を入力してください';
    }
    if (_requestType == 'other' && _otherMessageController.text.trim().isEmpty) {
      return '連絡内容を入力してください';
    }
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _errorMessage = validationError);
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.guardianService.createParentRequest(
        childId: widget.child.childId,
        guardianId: widget.guardianId,
        requestType: _requestType,
        targetDate: _targetDate,
        details: _buildDetails(),
        endDate: _requestType == 'absence' ? _endDate : null,
        absenceKind: _requestType == 'absence' ? _absenceKind : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _errorMessage = '申請の送信に失敗しました。もう一度お試しください');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ChildContextAppBarTitle(
          title: '${widget.child.nameLabel}の申請・連絡',
          officeName: widget.child.officeName,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('申請の種類', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _requestType,
            items: parentRequestTypeLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _requestType = v);
            },
          ),
          const SizedBox(height: 20),
          const Text('対象日', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded),
            label: Text('${_targetDate.year}/${_targetDate.month}/${_targetDate.day}'),
          ),
          const SizedBox(height: 20),
          ..._buildTypeSpecificFields(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('送信する'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTypeSpecificFields() {
    switch (_requestType) {
      case 'tardiness':
        return [
          const Text('到着予定時刻', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickTime,
            icon: const Icon(Icons.access_time_rounded),
            label: Text(_time == null ? '時刻を選択' : _formatTimeOfDay(_time!)),
          ),
          const SizedBox(height: 20),
          _reasonField('理由(任意)'),
        ];
      case 'early_leave':
        return [
          const Text('降園予定時刻', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickTime,
            icon: const Icon(Icons.access_time_rounded),
            label: Text(_time == null ? '時刻を選択' : _formatTimeOfDay(_time!)),
          ),
          const SizedBox(height: 20),
          _reasonField('理由(任意)'),
        ];
      case 'pickup_person_change':
        return [
          const Text('お迎えの方の氏名', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(controller: _pickupNameController),
          const SizedBox(height: 20),
          const Text('続柄', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(controller: _pickupRelationController, decoration: const InputDecoration(hintText: '例: 祖母')),
          const SizedBox(height: 20),
          const Text('電話番号(任意)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(controller: _pickupPhoneController, keyboardType: TextInputType.phone),
          const SizedBox(height: 20),
          _reasonField('備考(任意)'),
        ];
      case 'other':
        return [
          const Text('連絡内容', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _otherMessageController,
            maxLines: 5,
            decoration: const InputDecoration(hintText: '園への連絡事項を自由にご記入ください'),
          ),
        ];
      case 'absence':
      default:
        return [
          const Text('欠席の種別', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _absenceKind,
            decoration: const InputDecoration(hintText: '病気 / 家庭の都合 を選択'),
            items: absenceKindLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _absenceKind = v),
          ),
          const SizedBox(height: 20),
          const Text('終了日(任意・連続で休む場合)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('未指定なら対象日1日のみ。最大31日先まで。', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickEndDate,
                icon: const Icon(Icons.event_rounded),
                label: Text(_endDate == null
                    ? '終了日を選択'
                    : '${_endDate!.year}/${_endDate!.month}/${_endDate!.day}'),
              ),
              if (_endDate != null)
                TextButton(
                  onPressed: () => setState(() => _endDate = null),
                  child: const Text('クリア'),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _reasonField('理由(任意)'),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _isInfectiousAbsence,
            onChanged: (v) => setState(() => _isInfectiousAbsence = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('感染症により欠席'),
          ),
          if (_isInfectiousAbsence) ...[
            const SizedBox(height: 4),
            const Text('感染症の種類', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            FutureBuilder<List<InfectiousDiseaseMaster>>(
              future: _diseasesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final diseases = snapshot.data ?? const [];
                if (diseases.isEmpty) {
                  return const Text(
                    '選択肢がありません。理由欄に感染症名をご記入ください',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  );
                }
                return Column(
                  children: diseases
                      .map(
                        (d) => CheckboxListTile(
                          value: _selectedDiseaseNames.contains(d.name),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _selectedDiseaseNames.add(d.name);
                            } else {
                              _selectedDiseaseNames.remove(d.name);
                            }
                          }),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(d.name),
                          subtitle: (d.requiresOpinionLetter || d.requiresReturnForm)
                              ? Text(
                                  [
                                    if (d.requiresOpinionLetter) '医師の意見書が必要',
                                    if (d.requiresReturnForm) '登園届の提出が必要',
                                  ].join('・'),
                                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                                )
                              : null,
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ];
    }
  }

  Widget _reasonField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(controller: _reasonController, maxLines: 3),
      ],
    );
  }
}
