import 'package:flutter/material.dart';

import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';
import 'incident_common.dart';

/// ヒヤリハット・事故報告の作成/下書き編集フォーム。種別でセクションを出し分ける。
/// pop時に true を返すと呼び出し元が再読み込みする。
class IncidentFormScreen extends StatefulWidget {
  const IncidentFormScreen({
    super.key,
    required this.service,
    required this.officeId,
    this.reportId,
  });

  final ChildcareService service;
  final String officeId;
  final String? reportId; // 既存下書きの編集時

  @override
  State<IncidentFormScreen> createState() => _IncidentFormScreenState();
}

class _MedicalVisit {
  String? institution;
  String? doctorName;
  String? departmentId;
  final Set<String> examIds = {};
  final Set<String> treatmentIds = {};
  String? examDetail;
  String? doctorInstruction;
  bool prescriptionPresent = false;
  final Set<String> prescriptionIds = {};
  String? prescriptionDetail;
  String? treatmentPeriod;
}

class _ProgressLog {
  DateTime loggedAt = DateTime.now();
  String kind = 'ok';
  String text = '';
}

class _GuardianContact {
  DateTime contactedAt = DateTime.now();
  bool contactBookWritten = true; // true=連絡帳に記載 / false=口頭で直接
  String reactionKind = 'understood';
  String text = '';
}

class _IncidentFormScreenState extends State<IncidentFormScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // ルックアップ(kind別)
  final Map<String, List<Map<String, dynamic>>> _options = {};
  // 園児候補
  List<Map<String, dynamic>> _children = const [];
  List<String> _classNames = const []; // 年齢順の全クラス(絞り込み用)

  // 本体
  String _reportType = 'hiyari';
  DateTime _occurredOn = DateTime.now();
  TimeOfDay? _occurredAt = TimeOfDay.now();
  String? _placeOptionId;
  final _placeOther = TextEditingController();
  final _situationWhen = TextEditingController();
  final _situationWhere = TextEditingController();
  final _situationWhat = TextEditingController();
  final _situationResult = TextEditingController();
  final _staffHoiku = TextEditingController();
  final _staffJido = TextEditingController();
  final _staffWitness = TextEditingController();
  final _causeChild = TextEditingController();
  final _causeEnv = TextEditingController();
  final _causeObj = TextEditingController();
  final _causeRules = TextEditingController();
  String? _injurySiteOptionId;
  final _injuryDetail = TextEditingController();
  final _firstAid = TextEditingController();
  final _prevention = TextEditingController();
  final _note = TextEditingController();

  final List<Map<String, dynamic>> _selectedChildren = []; // {child_id, name}
  final List<_ProgressLog> _progress = [];
  final List<_GuardianContact> _guardians = [];
  final List<_MedicalVisit> _medicals = [];

  bool get _isAccident => _reportType == 'minor' || _reportType == 'hospital';
  bool get _isHospital => _reportType == 'hospital';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _placeOther, _situationWhen, _situationWhere, _situationWhat, _situationResult,
      _staffHoiku, _staffJido, _staffWitness, _causeChild, _causeEnv, _causeObj, _causeRules,
      _injuryDetail, _firstAid, _prevention, _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final opts = await widget.service.fetchIncidentLookupOptions();
      final children = await widget.service.fetchChildrenForOfficeMaster(widget.officeId);
      final classes = await widget.service.fetchChildcareClasses(widget.officeId);
      for (final o in opts) {
        (_options[o['kind'] as String] ??= []).add(o);
      }
      if (widget.reportId != null) {
        await _prefill(widget.reportId!);
      }
      if (!mounted) return;
      setState(() {
        _children = children.where((c) => c['enrollment_status'] != '退園済み').toList();
        _classNames = classes.map((c) => c.className).toList(); // 年齢順(age_group)
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '読み込みに失敗しました'; _loading = false; });
    }
  }

  Future<void> _prefill(String id) async {
    final d = await widget.service.fetchIncidentReportDetail(id);
    final r = (d['report'] as Map).cast<String, dynamic>();
    _reportType = r['report_type'] as String? ?? 'hiyari';
    if (r['occurred_on'] != null) _occurredOn = DateTime.parse(r['occurred_on'] as String);
    if (r['occurred_at'] != null) {
      final p = (r['occurred_at'] as String).split(':');
      _occurredAt = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }
    _placeOptionId = r['place_option_id'] as String?;
    _placeOther.text = r['place_other'] as String? ?? '';
    _situationWhen.text = r['situation_when'] as String? ?? '';
    _situationWhere.text = r['situation_where'] as String? ?? '';
    _situationWhat.text = r['situation_what'] as String? ?? '';
    _situationResult.text = r['situation_result'] as String? ?? '';
    final counts = (r['staff_counts'] as Map?)?.cast<String, dynamic>() ?? {};
    _staffHoiku.text = '${counts['hoiku'] ?? ''}';
    _staffJido.text = '${counts['jido'] ?? ''}';
    _staffWitness.text = '${counts['witness'] ?? ''}';
    final causes = (r['causes'] as Map?)?.cast<String, dynamic>() ?? {};
    _causeChild.text = causes['child_behavior'] as String? ?? '';
    _causeEnv.text = causes['environment'] as String? ?? '';
    _causeObj.text = causes['objects'] as String? ?? '';
    _causeRules.text = causes['care_rules'] as String? ?? '';
    _injurySiteOptionId = r['injury_site_option_id'] as String?;
    _injuryDetail.text = r['injury_detail'] as String? ?? '';
    _firstAid.text = r['first_aid'] as String? ?? '';
    _prevention.text = r['prevention_text'] as String? ?? '';
    _note.text = r['note_text'] as String? ?? '';
    for (final c in (d['children'] as List? ?? const [])) {
      final m = (c as Map).cast<String, dynamic>();
      _selectedChildren.add({'child_id': m['child_id'], 'name': m['child_name_snapshot'] ?? ''});
    }
    for (final p in (d['progress_logs'] as List? ?? const [])) {
      final m = (p as Map).cast<String, dynamic>();
      final log = _ProgressLog()
        ..loggedAt = DateTime.tryParse('${m['logged_at']}') ?? DateTime.now()
        ..kind = m['report_kind'] as String? ?? 'ok'
        ..text = m['report_text'] as String? ?? '';
      _progress.add(log);
    }
    for (final g in (d['guardian_contacts'] as List? ?? const [])) {
      final m = (g as Map).cast<String, dynamic>();
      final gc = _GuardianContact()
        ..contactedAt = DateTime.tryParse('${m['contacted_at']}') ?? DateTime.now()
        ..contactBookWritten = m['contact_book_written'] == true
        ..reactionKind = m['reaction_kind'] as String? ?? 'understood'
        ..text = m['reaction_text'] as String? ?? '';
      _guardians.add(gc);
    }
    for (final mv in (d['medical_visits'] as List? ?? const [])) {
      final m = (mv as Map).cast<String, dynamic>();
      final v = _MedicalVisit()
        ..institution = m['medical_institution'] as String?
        ..doctorName = m['doctor_name'] as String?
        ..departmentId = m['department_option_id'] as String?
        ..examDetail = m['exam_detail'] as String?
        ..doctorInstruction = m['doctor_instruction'] as String?
        ..prescriptionPresent = m['prescription_present'] == true
        ..prescriptionDetail = m['prescription_detail'] as String?
        ..treatmentPeriod = m['treatment_period'] as String?;
      v.examIds.addAll(((m['exam_option_ids'] as List?) ?? const []).map((e) => '$e'));
      v.treatmentIds.addAll(((m['treatment_option_ids'] as List?) ?? const []).map((e) => '$e'));
      v.prescriptionIds.addAll(((m['prescription_option_ids'] as List?) ?? const []).map((e) => '$e'));
      _medicals.add(v);
    }
  }

  Map<String, dynamic> _buildPayload() {
    String? nz(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    int? ni(TextEditingController c) => int.tryParse(c.text.trim());
    return {
      'office_id': widget.officeId,
      'report_type': _reportType,
      'occurred_on': _dateStr(_occurredOn),
      'occurred_at': _occurredAt == null
          ? null
          : '${_occurredAt!.hour.toString().padLeft(2, '0')}:${_occurredAt!.minute.toString().padLeft(2, '0')}',
      'place_option_id': _placeOptionId,
      'place_other': nz(_placeOther),
      'situation_when': nz(_situationWhen),
      'situation_where': nz(_situationWhere),
      'situation_what': nz(_situationWhat),
      'situation_result': nz(_situationResult),
      'staff_counts': {'hoiku': ni(_staffHoiku), 'jido': ni(_staffJido), 'witness': ni(_staffWitness)},
      'causes': {
        'child_behavior': nz(_causeChild),
        'environment': nz(_causeEnv),
        'objects': nz(_causeObj),
        'care_rules': nz(_causeRules),
      },
      'injury_site_option_id': _isAccident ? _injurySiteOptionId : null,
      'injury_detail': _isAccident ? nz(_injuryDetail) : null,
      'first_aid': _isAccident ? nz(_firstAid) : null,
      'prevention_text': nz(_prevention),
      'note_text': nz(_note),
      'children': [for (final c in _selectedChildren) {'child_id': c['child_id']}],
      'progress_logs': [
        for (final p in _progress)
          {'logged_at': p.loggedAt.toIso8601String(), 'report_kind': p.kind, 'report_text': p.text},
      ],
      'guardian_contacts': [
        for (final g in _guardians)
          {
            'contacted_at': g.contactedAt.toIso8601String(),
            'contact_book_written': g.contactBookWritten,
            'reaction_kind': g.reactionKind,
            'reaction_text': g.text,
          },
      ],
      'medical_visits': _isHospital
          ? [
              for (final v in _medicals)
                {
                  'medical_institution': v.institution,
                  'doctor_name': v.doctorName,
                  'department_option_id': v.departmentId,
                  'exam_option_ids': v.examIds.toList(),
                  'treatment_option_ids': v.treatmentIds.toList(),
                  'exam_detail': v.examDetail,
                  'doctor_instruction': v.doctorInstruction,
                  'prescription_present': v.prescriptionPresent,
                  'prescription_option_ids': v.prescriptionIds.toList(),
                  'prescription_detail': v.prescriptionDetail,
                  'treatment_period': v.treatmentPeriod,
                },
            ]
          : [],
    };
  }

  Future<String?> _save() async {
    setState(() => _saving = true);
    try {
      final id = await widget.service.saveIncidentReport(_buildPayload(), id: widget.reportId);
      return id;
    } catch (e) {
      _snack('保存に失敗しました: $e');
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDraft() async {
    final id = await _save();
    if (id != null && mounted) {
      _snack('下書きを保存しました');
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _deleteDraft() async {
    final id = widget.reportId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下書きを削除', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: const Text('この下書きを削除します。元に戻せません。よろしいですか?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await widget.service.deleteIncidentReport(id);
      if (mounted) {
        _snack('下書きを削除しました');
        // 'deleted' を返し、詳細画面には再取得させず一覧まで戻す(削除済みデータの取得エラー防止)。
        Navigator.of(context).pop('deleted');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('削除できません: ${_cleanError(e)}');
      }
    }
  }

  Future<void> _submit() async {
    final id = await _save();
    if (id == null) return;
    try {
      await widget.service.submitIncidentReport(id);
      if (mounted) {
        _snack('申請しました');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _snack('申請できません: ${_cleanError(e)}');
    }
  }

  String _cleanError(Object e) {
    final s = e.toString();
    final i = s.indexOf('必須項目');
    return i >= 0 ? s.substring(i) : s;
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reportId == null ? '報告書の作成' : '報告書の編集'),
        actions: [
          // 既存下書きのみ削除可(283)。申請中/承認済はこの画面に来ない。
          if (widget.reportId != null && !_loading)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'この下書きを削除',
              onPressed: _saving ? null : _deleteDraft,
            ),
        ],
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _saveDraft,
                        child: const Text('下書き保存'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: const Icon(Icons.send),
                        label: const Text('申請する'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  children: [
                    _sectionTitle('1. 基本情報'),
                    _typeSelector(),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _dateField()),
                      const SizedBox(width: 12),
                      Expanded(child: _timeField()),
                    ]),
                    const SizedBox(height: 12),
                    _placeField(),
                    const SizedBox(height: 12),
                    _childrenField(),
                    const SizedBox(height: 20),

                    _sectionTitle('2. 発生状況'),
                    _multiline(_situationWhen, 'いつ', maxLength: 200),
                    _multiline(_situationWhere, 'どこで', maxLength: 200),
                    _multiline(_situationWhat, '何をしたとき', maxLength: 200),
                    _multiline(_situationResult, 'どうなった', maxLength: 200),
                    const SizedBox(height: 12),

                    _sectionTitle('3. 現場の人員'),
                    Row(children: [
                      Expanded(child: _numField(_staffHoiku, '保育士(名)')),
                      const SizedBox(width: 10),
                      Expanded(child: _numField(_staffJido, '園児(名)')),
                      const SizedBox(width: 10),
                      Expanded(child: _numField(_staffWitness, '目撃者(名)')),
                    ]),
                    const SizedBox(height: 20),

                    _sectionTitle('4. 原因・問題点(該当項目のみ)'),
                    _multiline(_causeChild, '子どもの状況・行動', maxLength: 300),
                    _multiline(_causeEnv, '環境・設備', maxLength: 300),
                    _multiline(_causeObj, '物・遊具', maxLength: 300),
                    _multiline(_causeRules, '保育・対応・ルール', maxLength: 300),
                    const SizedBox(height: 12),

                    if (_isAccident) ...[
                      _sectionTitle('5. 発生後の対応'),
                      _lookupDropdown('injury_site', '受傷部位', _injurySiteOptionId,
                          (v) => setState(() => _injurySiteOptionId = v)),
                      const SizedBox(height: 10),
                      _multiline(_injuryDetail, '受傷内容', maxLength: 200),
                      _multiline(_firstAid, '応急処置', maxLength: 200),
                      const SizedBox(height: 12),
                    ],

                    // 6.経過と観察記録 / 7.保護者連絡 は事故報告(軽症/重大)のみ。
                    // ヒヤリハットでは不要(俊指示 2026-08-24)。
                    if (_isAccident) ...[
                      _sectionTitleRow('6. 経過と観察記録', () => setState(() => _progress.add(_ProgressLog()))),
                      ..._progress.asMap().entries.map((e) => _progressCard(e.key, e.value)),
                      const SizedBox(height: 12),

                      _sectionTitleRow('7. 保護者連絡', () => setState(() => _guardians.add(_GuardianContact()))),
                      ..._guardians.asMap().entries.map((e) => _guardianCard(e.key, e.value)),
                      const SizedBox(height: 12),
                    ],

                    if (_isHospital) ...[
                      _sectionTitleRow('受診記録', () => setState(() => _medicals.add(_MedicalVisit()))),
                      ..._medicals.asMap().entries.map((e) => _medicalCard(e.key, e.value)),
                      const SizedBox(height: 12),
                    ],

                    _sectionTitle('8. 再発防止'),
                    _multiline(_prevention, '再発防止に向けて', maxLength: 300),
                    const SizedBox(height: 12),
                    _sectionTitle('その他(任意)'),
                    _multiline(_note, 'その他', maxLength: 300),
                  ],
                ),
    );
  }

  // ---- 部品 ----
  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.leafGreen)),
      );

  Widget _sectionTitleRow(String t, VoidCallback onAdd) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Row(children: [
          Text(t, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.leafGreen)),
          const Spacer(),
          TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add, size: 18), label: const Text('追加')),
        ]),
      );

  void _onTypeChanged(String v) {
    setState(() {
      _reportType = v;
      // 事故報告(園内対応/病院搬送)は経過・保護者連絡が必須のため、最初から1行表示する。
      if (_isAccident) {
        if (_progress.isEmpty) _progress.add(_ProgressLog());
        if (_guardians.isEmpty) _guardians.add(_GuardianContact());
      }
    });
  }

  Widget _typeSelector() {
    return RadioGroup<String>(
      groupValue: _reportType,
      onChanged: (v) => _onTypeChanged(v!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in IncidentLabels.reportTypes.entries)
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: e.key,
              title: Text(e.value),
            ),
        ],
      ),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: _occurredOn,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
        );
        if (d != null) setState(() => _occurredOn = d);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: '発生日', border: OutlineInputBorder()),
        child: Text('${_occurredOn.year}/${_occurredOn.month}/${_occurredOn.day}'),
      ),
    );
  }

  /// 発生時間は他項目と同じプルダウン(5分刻み)。現在値が刻みに無ければ先頭に追加。
  Widget _timeField() {
    final current = _occurredAt == null
        ? null
        : '${_occurredAt!.hour.toString().padLeft(2, '0')}:${_occurredAt!.minute.toString().padLeft(2, '0')}';
    final opts = <String>[
      for (var h = 0; h < 24; h++)
        for (var m = 0; m < 60; m += 5) '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
    ];
    if (current != null && !opts.contains(current)) opts.insert(0, current);
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '発生時間', border: OutlineInputBorder(), isDense: true),
      items: [for (final t in opts) DropdownMenuItem(value: t, child: Text(t))],
      onChanged: (v) {
        if (v == null) return;
        final p = v.split(':');
        setState(() => _occurredAt = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
      },
    );
  }

  Widget _placeField() {
    return Column(
      children: [
        _lookupDropdown('place', '発生場所', _placeOptionId, (v) => setState(() => _placeOptionId = v)),
        const SizedBox(height: 8),
        TextField(
          controller: _placeOther,
          maxLength: 100,
          decoration: const InputDecoration(
            labelText: 'その他の場所(任意)', border: OutlineInputBorder(), counterText: '', isDense: true),
        ),
      ],
    );
  }

  Widget _lookupDropdown(String kind, String label, String? value, ValueChanged<String?> onChanged) {
    final opts = _options[kind] ?? const [];
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: [
        const DropdownMenuItem(value: null, child: Text('未選択')),
        for (final o in opts)
          DropdownMenuItem(value: o['id'] as String, child: Text(o['label'] as String)),
      ],
      onChanged: onChanged,
    );
  }

  Widget _childrenField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('対象園児', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(onPressed: _pickChildren, icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('選択')),
        ]),
        if (_selectedChildren.isEmpty)
          const Text('未選択(職員のみの事案は空でも可)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _selectedChildren.length; i++)
                Chip(
                  label: Text('${_selectedChildren[i]['name']}'),
                  onDeleted: () => setState(() => _selectedChildren.removeAt(i)),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _pickChildren() async {
    final selectedIds = _selectedChildren.map((c) => c['child_id'] as String).toSet();
    // クラスは全クラスを年齢順(はな→そら→かぜ→つき→ほし→にじ)で表示(在籍児がいないクラスも含む)。
    final classes = _classNames;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        String query = '';
        String classFilter = '';
        return StatefulBuilder(builder: (ctx, setLocal) {
          final filtered = _children.where((c) {
            final name = '${c['display_name'] ?? ''}';
            final cn = (c['class_name'] as String?) ?? '';
            if (query.isNotEmpty && !name.contains(query)) return false;
            if (classFilter.isNotEmpty && cn != classFilter) return false;
            return true;
          }).toList();
          return AlertDialog(
            title: const Text('園児を選択'),
            content: SizedBox(
              width: 440,
              height: 500,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(hintText: '氏名で検索', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setLocal(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  // クラス絞り込み(横スクロールのチップ)
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ChoiceChip(
                          label: const Text('全クラス'),
                          selected: classFilter.isEmpty,
                          onSelected: (_) => setLocal(() => classFilter = ''),
                        ),
                        for (final cn in classes)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              label: Text(cn),
                              selected: classFilter == cn,
                              onSelected: (_) => setLocal(() => classFilter = cn),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final c in filtered)
                          CheckboxListTile(
                            dense: true,
                            value: selectedIds.contains(c['child_id']),
                            title: Text('${c['display_name'] ?? ''}'),
                            subtitle: c['class_name'] != null ? Text('${c['class_name']}') : null,
                            onChanged: (v) => setLocal(() {
                              if (v == true) {
                                selectedIds.add(c['child_id'] as String);
                              } else {
                                selectedIds.remove(c['child_id']);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _selectedChildren
                      ..clear()
                      ..addAll([
                        for (final c in _children)
                          if (selectedIds.contains(c['child_id']))
                            {'child_id': c['child_id'], 'name': c['display_name'] ?? ''}
                      ]);
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('決定'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _multiline(TextEditingController c, String label, {int maxLength = 200}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        maxLines: null,
        minLines: 2,
        maxLength: maxLength,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: ''),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    );
  }

  Widget _progressCard(int i, _ProgressLog log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _dateTimeButton(log.loggedAt, (d) => setState(() => log.loggedAt = d)),
              const SizedBox(width: 8),
              _segmented<String>(
                options: IncidentLabels.progressKinds,
                value: log.kind,
                onChanged: (v) => setState(() => log.kind = v),
              ),
              const Spacer(),
              _deleteButton(() => setState(() => _progress.removeAt(i))),
            ]),
            if (log.kind == 'other') ...[
              const SizedBox(height: 6),
              TextField(
                controller: TextEditingController(text: log.text)
                  ..selection = TextSelection.collapsed(offset: log.text.length),
                maxLength: 200,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(labelText: '報告内容', border: OutlineInputBorder(), counterText: '', isDense: true),
                onChanged: (v) => log.text = v,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _guardianCard(int i, _GuardianContact gc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _dateTimeButton(gc.contactedAt, (d) => setState(() => gc.contactedAt = d)),
              const Spacer(),
              _deleteButton(() => setState(() => _guardians.removeAt(i))),
            ]),
            const SizedBox(height: 6),
            _labeledRow('報告方法', _segmented<bool>(
              options: const {true: '連絡帳に記載', false: '口頭で直接'},
              value: gc.contactBookWritten,
              onChanged: (v) => setState(() => gc.contactBookWritten = v),
            )),
            const SizedBox(height: 6),
            _labeledRow('相手の反応', _segmented<String>(
              options: const {'understood': 'ご理解いただけた', 'other': 'その他'},
              value: gc.reactionKind,
              onChanged: (v) => setState(() => gc.reactionKind = v),
            )),
            if (gc.reactionKind == 'other') ...[
              const SizedBox(height: 6),
              TextField(
                controller: TextEditingController(text: gc.text)
                  ..selection = TextSelection.collapsed(offset: gc.text.length),
                maxLength: 200,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(labelText: '相手の反応(詳細)', border: OutlineInputBorder(), counterText: '', isDense: true),
                onChanged: (v) => gc.text = v,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// ラベル + 右側にセグメント選択(1行にコンパクト表示)。
  Widget _labeledRow(String label, Widget child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 68, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
      ],
    );
  }

  /// 小さな2〜3択セグメント(ラジオより省スペース)。
  Widget _segmented<T>({required Map<T, String> options, required T value, required ValueChanged<T> onChanged}) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value, style: const TextStyle(fontSize: 12)),
            selected: value == e.key,
            onSelected: (_) => onChanged(e.key),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }

  Widget _deleteButton(VoidCallback onTap) {
    return IconButton(
      icon: const Icon(Icons.delete_outline, size: 20),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }

  Widget _medicalCard(int i, _MedicalVisit v) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.punchClockOut.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('受診記録', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _medicals.removeAt(i))),
            ]),
            _textInline('医療機関名', v.institution, (s) => v.institution = s),
            _textInline('医師名', v.doctorName, (s) => v.doctorName = s),
            const SizedBox(height: 6),
            _lookupDropdown('med_department', '診察科', v.departmentId, (val) => setState(() => v.departmentId = val)),
            const SizedBox(height: 8),
            _chips('受診内容', 'med_exam', v.examIds),
            _chips('処置内容', 'med_treatment', v.treatmentIds),
            _multilineInline('診察・処置の内容(補足)', v.examDetail, (s) => v.examDetail = s, 400),
            const SizedBox(height: 6),
            RadioGroup<String>(
              groupValue: v.doctorInstruction,
              onChanged: (val) => setState(() => v.doctorInstruction = val),
              child: Row(
                children: [
                  for (final e in IncidentLabels.doctorInstructions.entries)
                    Expanded(
                      child: RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: e.key,
                        title: Text(e.value, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: v.prescriptionPresent,
              title: const Text('処方薬あり'),
              onChanged: (val) => setState(() => v.prescriptionPresent = val ?? false),
            ),
            if (v.prescriptionPresent) ...[
              _chips('処方薬', 'med_prescription', v.prescriptionIds),
              _textInline('処方薬の内容(補足)', v.prescriptionDetail, (s) => v.prescriptionDetail = s),
            ],
            _textInline('治療期間', v.treatmentPeriod, (s) => v.treatmentPeriod = s),
          ],
        ),
      ),
    );
  }

  Widget _chips(String label, String kind, Set<String> selected) {
    final opts = _options[kind] ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in opts)
                FilterChip(
                  label: Text(o['label'] as String, style: const TextStyle(fontSize: 12)),
                  selected: selected.contains(o['id']),
                  onSelected: (s) => setState(() {
                    if (s) {
                      selected.add(o['id'] as String);
                    } else {
                      selected.remove(o['id']);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textInline(String label, String? value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: TextEditingController(text: value ?? '')
          ..selection = TextSelection.collapsed(offset: (value ?? '').length),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        onChanged: onChanged,
      ),
    );
  }

  Widget _multilineInline(String label, String? value, ValueChanged<String> onChanged, int maxLength) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        controller: TextEditingController(text: value ?? '')
          ..selection = TextSelection.collapsed(offset: (value ?? '').length),
        maxLines: 2,
        minLines: 1,
        maxLength: maxLength,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: '', isDense: true),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateTimeButton(DateTime dt, ValueChanged<DateTime> onChanged) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.schedule, size: 16),
      label: Text(
        '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
        style: const TextStyle(fontSize: 13),
      ),
      onPressed: () async {
        final d = await showDatePicker(
          context: context, initialDate: dt, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 1)));
        if (d == null) return;
        if (!mounted) return;
        final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dt));
        onChanged(DateTime(d.year, d.month, d.day, t?.hour ?? dt.hour, t?.minute ?? dt.minute));
      },
    );
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
