import 'package:flutter/material.dart';

import '../../models/family_daily_report.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import 'family_daily_report_history_screen.dart';

/// 家庭連絡帳(保護者→園)。本日分の検温・症状・自宅での様子を入力・提出する。
/// 提出後は編集不可(下書き中のみ編集可、v0.4 §5.3)。37.5℃以上は警告を表示するが
/// 提出自体はブロックしない(受入れ判断は園側)。
class FamilyDailyReportScreen extends StatefulWidget {
  const FamilyDailyReportScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<FamilyDailyReportScreen> createState() => _FamilyDailyReportScreenState();
}

class _FamilyDailyReportScreenState extends State<FamilyDailyReportScreen> {
  final _symptomsController = TextEditingController();
  final _homeNotesController = TextEditingController();
  final _today = DateTime.now();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRequired = false;
  FamilyDailyReport? _report;
  double? _temperature;
  TimeOfDay? _measuredAt;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _symptomsController.dispose();
    _homeNotesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.guardianService.fetchFamilyDailyReport(widget.child.childId, _today),
      widget.guardianService.isFamilyDailyReportRequired(widget.child.childId, _today),
    ]);
    if (!mounted) return;
    final report = results[0] as FamilyDailyReport?;
    setState(() {
      _report = report;
      _isRequired = results[1] as bool;
      _temperature = report?.temperature;
      _measuredAt = _parseTime(report?.temperatureMeasuredAt);
      _symptomsController.text = report?.symptoms ?? '';
      _homeNotesController.text = report?.homeNotes ?? '';
      _isLoading = false;
    });
  }

  static final List<double> _temperatureOptions = List.generate(
    71,
    (i) => double.parse((35.0 + i * 0.1).toStringAsFixed(1)),
  );
  static const List<int> _hourOptions = <int>[
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
  ];
  static const List<int> _minuteOptions = <int>[0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55];

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _isEditable => _report == null || _report!.isDraft;

  void _setHour(int hour) {
    setState(() => _measuredAt = TimeOfDay(hour: hour, minute: _measuredAt?.minute ?? 0));
  }

  void _setMinute(int minute) {
    setState(() => _measuredAt = TimeOfDay(hour: _measuredAt?.hour ?? 0, minute: minute));
  }

  Future<void> _save({required bool andSubmit}) async {
    if (andSubmit && (_temperature == null || _measuredAt == null)) {
      setState(() => _errorMessage = '体温と検温時刻を入力してください');
      return;
    }
    if (andSubmit && widget.child.requiresHomeNotes && _homeNotesController.text.trim().isEmpty) {
      setState(() => _errorMessage = '自宅での様子を入力してください');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.guardianService.upsertFamilyDailyReport(
        childId: widget.child.childId,
        businessDate: _today,
        temperature: _temperature,
        temperatureMeasuredAt: _measuredAt == null ? null : _formatTimeOfDay(_measuredAt!),
        symptoms: _symptomsController.text.trim().isEmpty ? null : _symptomsController.text.trim(),
        homeNotes: _homeNotesController.text.trim().isEmpty ? null : _homeNotesController.text.trim(),
      );
      final saved = await widget.guardianService.fetchFamilyDailyReport(widget.child.childId, _today);
      if (andSubmit && saved != null) {
        await widget.guardianService.submitFamilyDailyReport(saved.id);
      }
      if (!mounted) return;
      await _load();
      if (mounted && andSubmit) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('家庭連絡帳を提出しました')));
      }
    } on GuardianServiceException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.child.nameLabel}の家庭連絡帳'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: '過去の記録',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => FamilyDailyReportHistoryScreen(
                  guardianService: widget.guardianService,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_isRequired && (_report == null || !_report!.isSubmitted))
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.warmOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '登園には本日の家庭連絡帳の提出が必要です',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (_report?.isSubmitted ?? false)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.leafGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppColors.leafGreen),
                        SizedBox(width: 8),
                        Text('本日分は提出済みです', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                const Text('体温', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                DropdownButtonFormField<double>(
                  initialValue: _temperature,
                  isExpanded: true,
                  hint: const Text('体温を選択'),
                  decoration: const InputDecoration(suffixText: '℃'),
                  items: [
                    for (final t in _temperatureOptions)
                      DropdownMenuItem(value: t, child: Text('${t.toStringAsFixed(1)}℃')),
                  ],
                  onChanged: _isEditable ? (v) => setState(() => _temperature = v) : null,
                ),
                if (_temperature != null && _temperature! >= 37.5)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '37.5℃以上です。本日の保育園の受け入れはできません。',
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text('検温時刻', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _measuredAt?.hour,
                        isExpanded: true,
                        hint: const Text('時'),
                        decoration: const InputDecoration(suffixText: '時'),
                        items: [
                          for (final h in _hourOptions)
                            DropdownMenuItem(value: h, child: Text(h.toString().padLeft(2, '0'))),
                        ],
                        onChanged: _isEditable ? (v) => _setHour(v!) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _measuredAt?.minute,
                        isExpanded: true,
                        hint: const Text('分'),
                        decoration: const InputDecoration(suffixText: '分'),
                        items: [
                          for (final m in _minuteOptions)
                            DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0'))),
                        ],
                        onChanged: _isEditable ? (v) => _setMinute(v!) : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('本日の体調・症状など(任意)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _symptomsController,
                  enabled: _isEditable,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: '例: 鼻水、咳など'),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.child.requiresHomeNotes ? '自宅での様子(必須)' : '自宅での様子(任意)',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _homeNotesController,
                  enabled: _isEditable,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: '例: 食欲・睡眠・機嫌など'),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
                ],
                if (_isEditable) ...[
                  const SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => _save(andSubmit: false),
                    child: const Text('下書き保存'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : () => _save(andSubmit: true),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('提出する'),
                  ),
                ],
              ],
            ),
    );
  }
}
