import 'package:flutter/material.dart';

import '../../models/linked_child.dart';
import '../../models/parent_request.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 受診結果の入力(209・設計書§3.4)。
/// 感染症を選択→確定・必要書類の案内へ / 「感染症ではない」→案件終了 / 未受診→待ち継続。
class MedicalReportScreen extends StatefulWidget {
  const MedicalReportScreen({
    super.key,
    required this.guardianService,
    required this.child,
    required this.caseId,
  });

  final GuardianService guardianService;
  final LinkedChild child;
  final String caseId;

  @override
  State<MedicalReportScreen> createState() => _MedicalReportScreenState();
}

class _MedicalReportScreenState extends State<MedicalReportScreen> {
  bool _visited = true;
  DateTime _visitedAt = DateTime.now();
  final _institutionController = TextEditingController();
  bool _noInfection = false;
  String? _diseaseMasterId;
  final _doctorNoteController = TextEditingController();
  final _noteToSchoolController = TextEditingController();
  List<InfectiousDiseaseMaster> _diseases = const [];
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.guardianService.fetchInfectiousDiseaseMasters(widget.child.officeId).then((list) {
      if (mounted) setState(() => _diseases = list);
    });
  }

  @override
  void dispose() {
    _institutionController.dispose();
    _doctorNoteController.dispose();
    _noteToSchoolController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_visited && !_noInfection && _diseaseMasterId == null) {
      setState(() => _error = '診断された感染症を選択するか、「感染症ではないと診断された」を選んでください(未確定の場合は「受診していない」を選択)');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.guardianService.submitMedicalVisitReport(
        caseId: widget.caseId,
        visited: _visited,
        visitedAt: _visited ? _visitedAt : null,
        medicalInstitution:
            _institutionController.text.trim().isEmpty ? null : _institutionController.text.trim(),
        diseaseMasterId: _visited && !_noInfection ? _diseaseMasterId : null,
        noInfection: _visited && _noInfection,
        doctorNote: _doctorNoteController.text.trim().isEmpty ? null : _doctorNoteController.text.trim(),
        noteToSchool:
            _noteToSchoolController.text.trim().isEmpty ? null : _noteToSchoolController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('受診結果を園へ送信しました')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = '送信に失敗しました: $e';
        });
      }
    }
  }

  Future<void> _pickVisitedAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _visitedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 14)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_visitedAt));
    if (time == null) return;
    setState(() => _visitedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('受診結果の入力(${widget.child.nameLabel})')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('受診状況', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('受診した'),
                selected: _visited,
                onSelected: (_) => setState(() => _visited = true),
              ),
              ChoiceChip(
                label: const Text('受診していない(診断未確定)'),
                selected: !_visited,
                onSelected: (_) => setState(() => _visited = false),
              ),
            ],
          ),
          if (_visited) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickVisitedAt,
              icon: const Icon(Icons.event_rounded, size: 18),
              label: Text(
                  '受診日時: ${_visitedAt.month}/${_visitedAt.day} ${_visitedAt.hour.toString().padLeft(2, '0')}:${_visitedAt.minute.toString().padLeft(2, '0')}'),
            ),
            const SizedBox(height: 12),
            const Text('医療機関名(任意)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 6),
            TextField(controller: _institutionController),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _noInfection,
              onChanged: (v) => setState(() {
                _noInfection = v ?? false;
                if (_noInfection) _diseaseMasterId = null;
              }),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('感染症ではないと診断された'),
            ),
            if (!_noInfection) ...[
              const Text('診断された感染症', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _diseaseMasterId,
                isExpanded: true,
                hint: const Text('感染症を選択'),
                items: _diseases
                    .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                    .toList(),
                onChanged: (v) => setState(() => _diseaseMasterId = v),
              ),
            ],
            const SizedBox(height: 16),
            const Text('医師からの説明(任意)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 6),
            TextField(controller: _doctorNoteController, maxLines: 2),
          ],
          const SizedBox(height: 16),
          const Text('園への補足(任意)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(controller: _noteToSchoolController, maxLines: 2),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSaving ? null : _submit,
            child: Text(_isSaving ? '送信中…' : '受診結果を送信する'),
          ),
        ],
      ),
    );
  }
}
