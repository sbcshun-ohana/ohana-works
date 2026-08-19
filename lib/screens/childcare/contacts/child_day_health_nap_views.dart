import 'package:flutter/material.dart';

import '../../../models/guardian_app.dart';
import '../../../models/nap.dart';
import '../../../services/childcare_service.dart';
import '../../../theme/app_theme.dart';

String _hm(DateTime? dt) => dt == null
    ? '--:--'
    : '${dt.toLocal().hour.toString().padLeft(2, '0')}:${dt.toLocal().minute.toString().padLeft(2, '0')}';

const _mealSlotLabels = {'am_snack': '午前おやつ', 'lunch': '昼食', 'pm_snack': '午後おやつ'};

/// 連絡帳分割ビューの「健康」タブ: その子・その日の 検温/排便/ミルク/食事 を閲覧(読み取り)。
class ChildDayHealthView extends StatefulWidget {
  const ChildDayHealthView({
    super.key,
    required this.service,
    required this.officeId,
    required this.childId,
    required this.businessDate,
    this.ageGroup,
  });

  final ChildcareService service;
  final String officeId;
  final String childId;
  final DateTime businessDate;
  final String? ageGroup; // クラスの年齢('0歳'..)。ミルクの出し分けに使用

  @override
  State<ChildDayHealthView> createState() => _ChildDayHealthViewState();
}

class _ChildDayHealthViewState extends State<ChildDayHealthView> {
  bool _loading = true;
  String? _error;
  List<ChildTemperatureRecord> _temps = const [];
  List<({String time, String type})> _toileting = const [];
  List<({String time, int amountMl})> _milk = const [];
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 年度年齢(4/1基準の満年齢)。ageGroup が無い場合のフォールバック。
  int _fiscalAge(DateTime birth, DateTime ref) {
    final fyStart = ref.month >= 4 ? ref.year : ref.year - 1;
    var age = fyStart - birth.year;
    if (birth.month > 4 || (birth.month == 4 && birth.day > 1)) age--;
    return age;
  }

  /// クラスの年齢('0歳'→0)。基準はクラス(はな=0歳のみミルク)。生年月日はフォールバック。
  int? _age() {
    final g = int.tryParse((widget.ageGroup ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
    if (g != null) return g;
    return _birthDate == null ? null : _fiscalAge(_birthDate!, widget.businessDate);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final temps = await widget.service.fetchChildTemperaturesForOffice(widget.officeId, widget.businessDate);
      final health = await widget.service.fetchHealthCheckForOffice(widget.officeId, widget.businessDate);
      final entry = health[widget.childId];
      if (!mounted) return;
      setState(() {
        _temps = temps.where((t) => t.childId == widget.childId).toList();
        _toileting = entry?.toileting ?? const [];
        _milk = entry?.milk ?? const [];
        _birthDate = entry?.birthDate;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '健康情報の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.leafGreen)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  Widget _empty() => const Text('記録なし', style: TextStyle(color: AppColors.textSecondary, fontSize: 13));

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section(
            '検温',
            _temps.isEmpty
                ? _empty()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final t in _temps)
                        Text('${t.measuredAt.length >= 5 ? t.measuredAt.substring(0, 5) : t.measuredAt}  '
                            '${t.temperature.toStringAsFixed(1)}℃'),
                    ],
                  ),
          ),
          _section(
            '排便',
            _toileting.isEmpty
                ? _empty()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final e in _toileting) Text('${e.time}  ${e.type}')],
                  ),
          ),
          // ミルクは0歳児(はな組)のみ表示。1歳児クラス以上(そら〜にじ)では非表示。
          if (_age() == 0)
            _section(
              'ミルク',
              _milk.isEmpty
                  ? _empty()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final e in _milk) Text('${e.time}  ${e.amountMl}ml')],
                    ),
            ),
        ],
      ),
    );
  }
}

/// 連絡帳分割ビューの「食事」タブ: その子・その日の食事(午前おやつ/昼食/午後おやつ)分量を閲覧(読み取り)。
class ChildDayMealView extends StatefulWidget {
  const ChildDayMealView({
    super.key,
    required this.service,
    required this.officeId,
    required this.childId,
    required this.businessDate,
    this.ageGroup,
  });

  final ChildcareService service;
  final String officeId;
  final String childId;
  final DateTime businessDate;
  final String? ageGroup; // クラスの年齢('0歳'..'5歳')。午前おやつの出し分けに使用

  @override
  State<ChildDayMealView> createState() => _ChildDayMealViewState();
}

class _ChildDayMealViewState extends State<ChildDayMealView> {
  bool _loading = true;
  String? _error;
  Map<String, String> _meals = const {};
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final health = await widget.service.fetchHealthCheckForOffice(widget.officeId, widget.businessDate);
      if (!mounted) return;
      setState(() {
        _meals = health[widget.childId]?.meals ?? const {};
        _birthDate = health[widget.childId]?.birthDate;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '食事情報の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  /// 年度年齢(4/1基準の満年齢)。ageGroup が無い場合のフォールバック。
  int _fiscalAge(DateTime birth, DateTime ref) {
    final fyStart = ref.month >= 4 ? ref.year : ref.year - 1;
    var age = fyStart - birth.year;
    if (birth.month > 4 || (birth.month == 4 && birth.day > 1)) age--;
    return age;
  }

  /// クラスの年齢('2歳'→2)。基準はクラス(はな/そら/かぜ=午前おやつ)。生年月日はフォールバック。
  int? _age() {
    final g = int.tryParse((widget.ageGroup ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
    if (g != null) return g;
    return _birthDate == null ? null : _fiscalAge(_birthDate!, widget.businessDate);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    // 3歳児クラス以上は午前おやつが無いため非表示(0・1・2歳=はな/そら/かぜのみ。年齢不明時は安全側で表示)。
    final age = _age();
    final showAmSnack = age == null || age < 3;
    final slots = _mealSlotLabels.entries.where((e) => e.key != 'am_snack' || showAmSnack);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final slot in slots)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(slot.value,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.leafGreen)),
                  ),
                  Expanded(
                    child: Text(
                      (_meals[slot.key] != null && _meals[slot.key]!.isNotEmpty) ? _meals[slot.key]! : '記録なし',
                      style: TextStyle(
                        color: (_meals[slot.key] != null && _meals[slot.key]!.isNotEmpty)
                            ? null
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 連絡帳分割ビューの「午睡」タブ: その子・その日の午睡区間とチェックを閲覧(読み取り)。
class ChildDayNapView extends StatefulWidget {
  const ChildDayNapView({
    super.key,
    required this.service,
    required this.officeId,
    required this.childId,
    required this.businessDate,
  });

  final ChildcareService service;
  final String officeId;
  final String childId;
  final DateTime businessDate;

  @override
  State<ChildDayNapView> createState() => _ChildDayNapViewState();
}

class _ChildDayNapViewState extends State<ChildDayNapView> {
  bool _loading = true;
  String? _error;
  List<NapSessionRow> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final board = await widget.service.fetchNapBoard(widget.officeId, widget.businessDate);
      if (!mounted) return;
      setState(() {
        _sessions = board.where((s) => s.childId == widget.childId).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '午睡情報の取得に失敗しました';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    final allChecks = [
      for (final s in _sessions) ...s.checks,
    ]..sort((a, b) => a.slotAt.compareTo(b.slotAt));
    final intervals = [for (final s in _sessions) ...s.intervals];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('午睡区間', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.leafGreen)),
          const SizedBox(height: 6),
          if (intervals.isEmpty)
            const Text('午睡の記録がありません', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else
            for (final iv in intervals)
              Text('${_hm(iv.sleepStartAt)} 〜 ${iv.wakeUpAt != null ? _hm(iv.wakeUpAt) : '就寝中'}'),
          const SizedBox(height: 20),
          const Text('午睡チェック', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.leafGreen)),
          const SizedBox(height: 6),
          if (allChecks.isEmpty)
            const Text('チェックの記録がありません', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else
            for (final c in allChecks)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${_hm(c.slotAt)}  ${napBodyPositions[c.bodyPosition] ?? c.bodyPosition}'
                  '  呼吸${c.breathing ? '○' : '×'} 顔色${c.complexion ? '○' : '×'} 寝具${c.bedding ? '○' : '×'}'
                  '${c.checkedByName != null ? '  (${c.checkedByName})' : ''}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
        ],
      ),
    );
  }
}
