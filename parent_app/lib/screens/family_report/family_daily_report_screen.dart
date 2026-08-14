import 'package:flutter/material.dart';

import '../../models/family_daily_report.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_format.dart';
import '../../widgets/child_context_app_bar_title.dart';
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
  final _dinnerContentController = TextEditingController();
  final _breakfastContentController = TextEditingController();
  final _pickupNameController = TextEditingController();
  final _pickupRelationshipController = TextEditingController();
  final _today = DateTime.now();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRequired = false;
  FamilyDailyReport? _report;
  double? _temperature;
  TimeOfDay? _measuredAt;
  String? _errorMessage;

  String? _nightMood;
  String? _morningMood;
  int? _nightBowelCount;
  String? _nightBowelCondition;
  int? _morningBowelCount;
  String? _morningBowelCondition;
  String? _sleepStartAt;
  String? _sleepEndAt;
  String? _dinnerAt;
  String? _breakfastAt;
  String? _pickupTimeFrom;
  String? _pickupTimeTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _symptomsController.dispose();
    _homeNotesController.dispose();
    _dinnerContentController.dispose();
    _breakfastContentController.dispose();
    _pickupNameController.dispose();
    _pickupRelationshipController.dispose();
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
      _nightMood = report?.nightMood;
      _morningMood = report?.morningMood;
      _nightBowelCount = report?.nightBowelCount;
      _nightBowelCondition = report?.nightBowelCondition;
      _morningBowelCount = report?.morningBowelCount;
      _morningBowelCondition = report?.morningBowelCondition;
      _sleepStartAt = _matchTimeOption(report?.sleepStartAt, _sleepStartOptions);
      _sleepEndAt = _matchTimeOption(report?.sleepEndAt, _sleepEndOptions);
      _dinnerAt = _matchTimeOption(report?.dinnerAt, _dinnerTimeOptions);
      _breakfastAt = _matchTimeOption(report?.breakfastAt, _breakfastTimeOptions);
      _dinnerContentController.text = report?.dinnerContent ?? '';
      _breakfastContentController.text = report?.breakfastContent ?? '';
      _pickupNameController.text = report?.pickupPersonName ?? '';
      _pickupRelationshipController.text = report?.pickupPersonRelationship ?? '';
      _pickupTimeFrom = _matchTimeOption(report?.pickupTimeFrom, _pickupTimeOptions);
      _pickupTimeTo = _matchTimeOption(report?.pickupTimeTo, _pickupTimeOptions);
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

  /// 15分刻みの"HH:mm"リストを生成する。startがendより後ろの場合は日付をまたぐとみなし、
  /// 24時間表記を超えてラップする(例: 19:00〜翌2:00)。
  static List<String> _timeRange(int startHour, int startMinute, int endHour, int endMinute) {
    final start = startHour * 60 + startMinute;
    var end = endHour * 60 + endMinute;
    if (end <= start) end += 24 * 60;
    final result = <String>[];
    for (var m = start; m <= end; m += 15) {
      final h = (m ~/ 60) % 24;
      final min = m % 60;
      result.add('${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}');
    }
    return result;
  }

  static final List<String> _sleepStartOptions = _timeRange(19, 0, 2, 0);
  static final List<String> _sleepEndOptions = _timeRange(5, 0, 9, 0);
  static final List<String> _dinnerTimeOptions = _timeRange(17, 0, 21, 0);
  static final List<String> _breakfastTimeOptions = _timeRange(6, 0, 9, 0);
  // 登園/お迎え時刻(俊指示 2026-08-14: 「お迎え時間帯(から/まで)」を登園時間とお迎え時間に区別)。
  // DB列は互換のため pickup_time_from=登園時間 / pickup_time_to=お迎え時間 として使う。
  static final List<String> _pickupTimeOptions = _timeRange(7, 0, 19, 0);
  static const List<int> _bowelCountOptions = <int>[0, 1, 2, 3, 4, 5];

  /// DBの"HH:mm:ss"表記を選択肢の"HH:mm"表記に正規化し、選択肢に無ければnullを返す
  /// (範囲外の既存値でDropdownがエラーになるのを防ぐ)。
  String? _matchTimeOption(String? value, List<String> options) {
    if (value == null) return null;
    final normalized = value.length >= 5 ? value.substring(0, 5) : value;
    return options.contains(normalized) ? normalized : null;
  }

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

  /// 提出時のみ検証する必須項目チェック。0〜2歳児クラス、または園児単位で
  /// 必須フラグがONの場合(_isRequired)は機嫌・排便・睡眠・食事も必須とする。
  /// お迎え変更連絡は常に任意(氏名を入力した場合のみ時間帯も合わせて必須にする)。
  String? _validate() {
    if (_temperature == null || _measuredAt == null) {
      return '体温と検温時刻を入力してください';
    }
    if (_isRequired) {
      if (_homeNotesController.text.trim().isEmpty) return '自宅での様子を入力してください';
      if (_nightMood == null || _morningMood == null) return '夜・朝の機嫌を選択してください';
      if (_nightBowelCount == null || _morningBowelCount == null) return '夜・朝の排便回数を選択してください';
      if (_nightBowelCount! > 0 && _nightBowelCondition == null) return '夜の便の状態を選択してください';
      if (_morningBowelCount! > 0 && _morningBowelCondition == null) return '朝の便の状態を選択してください';
      if (_sleepStartAt == null || _sleepEndAt == null) return '入眠・起床時刻を選択してください';
      if (_dinnerContentController.text.trim().isEmpty || _dinnerAt == null) {
        return '夕食の内容・摂取時刻を入力してください';
      }
      if (_breakfastContentController.text.trim().isEmpty || _breakfastAt == null) {
        return '朝食の内容・摂取時刻を入力してください';
      }
    }
    if (_pickupNameController.text.trim().isNotEmpty && _pickupTimeTo == null) {
      return 'お迎え時間を選択してください';
    }
    return null;
  }

  Future<void> _save({required bool andSubmit}) async {
    if (andSubmit) {
      final error = _validate();
      if (error != null) {
        setState(() => _errorMessage = error);
        return;
      }
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
        nightMood: _nightMood,
        morningMood: _morningMood,
        nightBowelCount: _nightBowelCount,
        nightBowelCondition: _nightBowelCount == 0 ? null : _nightBowelCondition,
        morningBowelCount: _morningBowelCount,
        morningBowelCondition: _morningBowelCount == 0 ? null : _morningBowelCondition,
        sleepStartAt: _sleepStartAt,
        sleepEndAt: _sleepEndAt,
        dinnerContent: _dinnerContentController.text.trim().isEmpty ? null : _dinnerContentController.text.trim(),
        dinnerAt: _dinnerAt,
        breakfastContent:
            _breakfastContentController.text.trim().isEmpty ? null : _breakfastContentController.text.trim(),
        breakfastAt: _breakfastAt,
        pickupPersonName: _pickupNameController.text.trim().isEmpty ? null : _pickupNameController.text.trim(),
        pickupPersonRelationship:
            _pickupRelationshipController.text.trim().isEmpty ? null : _pickupRelationshipController.text.trim(),
        pickupTimeFrom: _pickupTimeFrom,
        pickupTimeTo: _pickupTimeTo,
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

  Widget _sectionLabel(String text) => Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14));

  Widget _moodDropdown({required String label, required String? value, required ValueChanged<String?> onChanged}) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final e in familyMoodLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: _isEditable ? onChanged : null,
    );
  }

  Widget _bowelRow({
    required String label,
    required int? count,
    required String? condition,
    required ValueChanged<int?> onCountChanged,
    required ValueChanged<String?> onConditionChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: count,
            isExpanded: true,
            decoration: InputDecoration(labelText: '$labelの排便回数'),
            items: [for (final c in _bowelCountOptions) DropdownMenuItem(value: c, child: Text('$c回'))],
            onChanged: _isEditable ? onCountChanged : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: condition,
            isExpanded: true,
            decoration: InputDecoration(labelText: '$labelの便の状態', enabled: count != null && count > 0),
            items: [
              for (final e in familyBowelConditionLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: _isEditable && count != null && count > 0 ? onConditionChanged : null,
          ),
        ),
      ],
    );
  }

  Widget _timeDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final t in options) DropdownMenuItem(value: t, child: Text(t))],
      onChanged: _isEditable ? onChanged : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ChildContextAppBarTitle(
          title: '${widget.child.nameLabel}の家庭連絡帳',
          officeName: widget.child.officeName,
        ),
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
                Text(
                  '${formatJapaneseDate(_today)}分',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
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
                  _isRequired ? '自宅での様子(必須)' : '自宅での様子(任意)',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _homeNotesController,
                  enabled: _isEditable,
                  maxLines: 4,
                  decoration: const InputDecoration(hintText: '例: 食欲・睡眠・機嫌など'),
                ),
                const SizedBox(height: 24),
                _sectionLabel('機嫌'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _moodDropdown(
                        label: '夜の機嫌',
                        value: _nightMood,
                        onChanged: (v) => setState(() => _nightMood = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _moodDropdown(
                        label: '朝の機嫌',
                        value: _morningMood,
                        onChanged: (v) => setState(() => _morningMood = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionLabel('排便'),
                const SizedBox(height: 8),
                _bowelRow(
                  label: '夜',
                  count: _nightBowelCount,
                  condition: _nightBowelCondition,
                  onCountChanged: (v) => setState(() {
                    _nightBowelCount = v;
                    if (v == 0) _nightBowelCondition = null;
                  }),
                  onConditionChanged: (v) => setState(() => _nightBowelCondition = v),
                ),
                const SizedBox(height: 12),
                _bowelRow(
                  label: '朝',
                  count: _morningBowelCount,
                  condition: _morningBowelCondition,
                  onCountChanged: (v) => setState(() {
                    _morningBowelCount = v;
                    if (v == 0) _morningBowelCondition = null;
                  }),
                  onConditionChanged: (v) => setState(() => _morningBowelCondition = v),
                ),
                const SizedBox(height: 24),
                _sectionLabel('睡眠(入眠〜起床)'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _timeDropdown(
                        label: '入眠(前日夜)',
                        value: _sleepStartAt,
                        options: _sleepStartOptions,
                        onChanged: (v) => setState(() => _sleepStartAt = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _timeDropdown(
                        label: '起床(当日朝)',
                        value: _sleepEndAt,
                        options: _sleepEndOptions,
                        onChanged: (v) => setState(() => _sleepEndAt = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _sectionLabel('食事'),
                const SizedBox(height: 8),
                const Text('夕食(前日夜)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _dinnerContentController,
                  enabled: _isEditable,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: '例: カレーライス、サラダ'),
                ),
                const SizedBox(height: 8),
                _timeDropdown(
                  label: '夕食の時刻',
                  value: _dinnerAt,
                  options: _dinnerTimeOptions,
                  onChanged: (v) => setState(() => _dinnerAt = v),
                ),
                const SizedBox(height: 16),
                const Text('朝食(当日朝)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: _breakfastContentController,
                  enabled: _isEditable,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: '例: パン、ヨーグルト'),
                ),
                const SizedBox(height: 8),
                _timeDropdown(
                  label: '朝食の時刻',
                  value: _breakfastAt,
                  options: _breakfastTimeOptions,
                  onChanged: (v) => setState(() => _breakfastAt = v),
                ),
                const SizedBox(height: 24),
                _sectionLabel('お迎え(変更がある場合のみ・任意)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _pickupNameController,
                  enabled: _isEditable,
                  decoration: const InputDecoration(hintText: 'お迎えに来られる方の氏名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pickupRelationshipController,
                  enabled: _isEditable,
                  decoration: const InputDecoration(hintText: '続柄(例: 祖母、おじ 等)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _timeDropdown(
                        label: '登園時間',
                        value: _pickupTimeFrom,
                        options: _pickupTimeOptions,
                        onChanged: (v) => setState(() => _pickupTimeFrom = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _timeDropdown(
                        label: 'お迎え時間',
                        value: _pickupTimeTo,
                        options: _pickupTimeOptions,
                        onChanged: (v) => setState(() => _pickupTimeTo = v),
                      ),
                    ),
                  ],
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
