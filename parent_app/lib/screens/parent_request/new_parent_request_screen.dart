import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/linked_child.dart';
import '../../models/parent_request.dart';
import '../../models/pickup_person.dart';
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
  // 登園・お迎え時間(任意)。連絡帳から移設(俊指示 2026-08-14)。details(日本語キー)に格納。
  TimeOfDay? _pickupArriveTime;
  TimeOfDay? _pickupLeaveTime;

  // お迎え者身分証明書(202)。フラグON施設のみ: 初回(=お迎え者マスタに同名なし)は写真添付必須。
  bool _pickupIdDocEnabled = false;
  List<PickupPerson> _pickupPersons = [];
  XFile? _pickupIdImage;

  bool _isInfectiousAbsence = false;
  final Set<String> _selectedDiseaseNames = {};
  Future<List<InfectiousDiseaseMaster>>? _diseasesFuture;

  // 服薬連絡(201)。種類=複数選択(日本語ラベル)。フラグOFF施設では種類プルダウンに出さない。
  bool _medicationEnabled = false;
  final Set<String> _selectedMedicationKinds = {};
  final _medicationOtherController = TextEditingController();
  final _symptomController = TextEditingController();
  final _medicationNotesController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _diseasesFuture = widget.guardianService.fetchInfectiousDiseaseMasters(widget.child.officeId);
    widget.guardianService.isMedicationReportEnabled(widget.child.officeId).then((enabled) {
      if (mounted) setState(() => _medicationEnabled = enabled);
    });
    widget.guardianService.isPickupIdDocumentEnabled(widget.child.officeId).then((enabled) {
      if (mounted) setState(() => _pickupIdDocEnabled = enabled);
    });
    // 取得失敗時は空のまま=既登録なし扱い(初回=添付必須の安全側)。
    widget.guardianService
        .fetchPickupPersonsForChild(widget.child.childId)
        .then((list) {
      if (mounted) setState(() => _pickupPersons = list);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _otherMessageController.dispose();
    _pickupNameController.dispose();
    _pickupRelationController.dispose();
    _pickupPhoneController.dispose();
    _medicationOtherController.dispose();
    _symptomController.dispose();
    _medicationNotesController.dispose();
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

  /// 入力中の氏名と一致する既登録お迎え者(園児×氏名)。
  PickupPerson? get _matchedPickupPerson {
    final name = _pickupNameController.text.trim();
    if (name.isEmpty) return null;
    for (final person in _pickupPersons) {
      if (person.name == name) return person;
    }
    return null;
  }

  /// 身分証明書セクション(202・フラグON施設のみ)。
  /// 既登録者(同名)は状態表示のみ、初回の方は写真添付必須。
  List<Widget> _buildPickupIdDocSection() {
    final matched = _matchedPickupPerson;
    if (matched != null && matched.hasDocument) {
      final verified = matched.idVerified;
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (verified ? AppColors.leafGreen : AppColors.warmOrange).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(verified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                  color: verified ? AppColors.leafGreen : AppColors.warmOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  verified
                      ? 'この方は身分証明書を確認済みです。アップロードは不要です'
                      : 'この方は身分証明書を提出済みです(園での確認待ち)。アップロードは不要です',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      const Text(
        '初めてお迎えに来られる方は、身分証明書(運転免許証・マイナンバーカード等)の写真の添付が必要です。'
        '2回目以降は不要になります。',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      if (_pickupIdImage != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(_pickupIdImage!.path), height: 160, fit: BoxFit.cover),
        ),
        const SizedBox(height: 8),
      ],
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickIdImage(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_rounded, size: 18),
              label: const Text('撮影する'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pickIdImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded, size: 18),
              label: Text(_pickupIdImage == null ? '写真を選ぶ' : '選び直す'),
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _pickIdImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (picked != null) setState(() => _pickupIdImage = picked);
  }

  Future<void> _pickPickupTime({required bool isArrive}) async {
    final current = isArrive ? _pickupArriveTime : _pickupLeaveTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? (isArrive ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 17, minute: 0)),
    );
    if (picked != null) {
      setState(() {
        if (isArrive) {
          _pickupArriveTime = picked;
        } else {
          _pickupLeaveTime = picked;
        }
      });
    }
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
          if (_pickupArriveTime != null) '登園時間': _formatTimeOfDay(_pickupArriveTime!),
          if (_pickupLeaveTime != null) 'お迎え時間': _formatTimeOfDay(_pickupLeaveTime!),
          if (_reasonController.text.trim().isNotEmpty) '備考': _reasonController.text.trim(),
        };
      case 'medication':
        // 種類はDBの medication_kinds 列(構造化)に保存。details は承認画面の汎用表示用。
        return {
          '薬の種類': _selectedMedicationKinds.join('、'),
          if (_selectedMedicationKinds.contains('その他')) 'その他の薬': _medicationOtherController.text.trim(),
          'お子さまの様子・症状': _symptomController.text.trim(),
          if (_medicationNotesController.text.trim().isNotEmpty) '備考': _medicationNotesController.text.trim(),
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
    if (_requestType == 'pickup_person_change' && _pickupIdDocEnabled) {
      final matched = _matchedPickupPerson;
      if ((matched == null || !matched.hasDocument) && _pickupIdImage == null) {
        return '初めてお迎えに来られる方は身分証明書の写真の添付が必要です';
      }
    }
    if (_requestType == 'other' && _otherMessageController.text.trim().isEmpty) {
      return '連絡内容を入力してください';
    }
    if (_requestType == 'medication') {
      if (_selectedMedicationKinds.isEmpty) return '薬の種類を選択してください';
      if (_selectedMedicationKinds.contains('その他') && _medicationOtherController.text.trim().isEmpty) {
        return '「その他」を選択した場合は薬の内容をご記入ください';
      }
      if (_symptomController.text.trim().isEmpty) return 'お子さまの様子・症状を入力してください';
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
      // 202: 身分証画像を先にアップロードし、申請行にパスを載せる(承認時にお迎え者マスタへ転記)。
      String? idDocumentPath;
      if (_requestType == 'pickup_person_change' && _pickupIdImage != null) {
        final bytes = await _pickupIdImage!.readAsBytes();
        idDocumentPath = await widget.guardianService.uploadPickupIdDocument(
          childId: widget.child.childId,
          bytes: bytes,
        );
      }
      await widget.guardianService.createParentRequest(
        childId: widget.child.childId,
        guardianId: widget.guardianId,
        requestType: _requestType,
        targetDate: _targetDate,
        details: _buildDetails(),
        endDate: _requestType == 'absence' ? _endDate : null,
        absenceKind: _requestType == 'absence' ? _absenceKind : null,
        medicationKinds: _requestType == 'medication' ? _selectedMedicationKinds.toList() : null,
        idDocumentPath: idDocumentPath,
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
                // 服薬連絡は機能フラグON施設のみ表示(201)。
                .where((e) => e.key != 'medication' || _medicationEnabled)
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
          if (_pickupPersons.isNotEmpty) ...[
            const Text('登録済みのお迎え者から選ぶ', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _pickupPersons
                  .map(
                    (person) => ActionChip(
                      avatar: person.idVerified
                          ? const Icon(Icons.verified_rounded, size: 18, color: AppColors.leafGreen)
                          : null,
                      label: Text(
                        '${person.name}${person.relationship != null && person.relationship!.isNotEmpty ? '(${person.relationship})' : ''}',
                      ),
                      onPressed: () => setState(() {
                        _pickupNameController.text = person.name;
                        _pickupRelationController.text = person.relationship ?? '';
                        _pickupPhoneController.text = person.phone ?? '';
                        _pickupIdImage = null;
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],
          const Text('お迎えの方の氏名', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(controller: _pickupNameController, onChanged: (_) => setState(() {})),
          const SizedBox(height: 20),
          const Text('続柄', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(controller: _pickupRelationController, decoration: const InputDecoration(hintText: '例: 祖母')),
          const SizedBox(height: 20),
          const Text('電話番号(任意)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(controller: _pickupPhoneController, keyboardType: TextInputType.phone),
          const SizedBox(height: 20),
          if (_pickupIdDocEnabled) ...[
            const Text('身分証明書', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            ..._buildPickupIdDocSection(),
            const SizedBox(height: 20),
          ],
          const Text('登園・お迎え時間(任意)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPickupTime(isArrive: true),
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: Text(_pickupArriveTime == null ? '登園時間' : '登園 ${_formatTimeOfDay(_pickupArriveTime!)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickPickupTime(isArrive: false),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(_pickupLeaveTime == null ? 'お迎え時間' : 'お迎え ${_formatTimeOfDay(_pickupLeaveTime!)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _reasonField('備考(任意)'),
        ];
      case 'medication':
        return [
          const Text('薬の種類(複数選択できます)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          ...medicationKindOptions.map(
            (kind) => CheckboxListTile(
              value: _selectedMedicationKinds.contains(kind),
              onChanged: (checked) => setState(() {
                if (checked ?? false) {
                  _selectedMedicationKinds.add(kind);
                } else {
                  _selectedMedicationKinds.remove(kind);
                }
              }),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(kind),
            ),
          ),
          // 解熱剤の特別ルール(201 §3.2): 赤の警告を表示するが送信は可能(園が服薬の事実を把握するため)。
          if (_selectedMedicationKinds.contains('解熱剤')) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                border: Border.all(color: AppColors.danger),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '解熱剤を服用した日は登園できません。欠席のご連絡をお願いします。',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
              ),
            ),
          ],
          if (_selectedMedicationKinds.contains('その他')) ...[
            const SizedBox(height: 12),
            const Text('その他の薬の内容', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            TextField(
              controller: _medicationOtherController,
              decoration: const InputDecoration(hintText: '薬の内容をご記入ください'),
            ),
          ],
          const SizedBox(height: 20),
          const Text('お子さまの様子・症状(必須)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: _symptomController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '例: 昨晩から咳が出ています。熱はありません'),
          ),
          const SizedBox(height: 20),
          const Text('備考(任意)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(controller: _medicationNotesController, maxLines: 2),
        ];
      case 'other':
        return [
          // 服薬の連絡は専用種類へ誘導(201 §3.5。フラグON施設のみ表示)。
          if (_medicationEnabled) ...[
            const Text(
              'お薬のご連絡は「服薬連絡」からお願いします',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
          ],
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
