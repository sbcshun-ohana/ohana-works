import 'package:flutter/material.dart';

import '../../services/my_data_service.dart';
import '../../theme/app_theme.dart';

/// 給食の注文(自己注文モデル・365-371)。
/// ① 曜日テンプレ(毎週の既定=これに従い自動で注文が入る)
/// ② 月カレンダー(各日の◯/×を個別に上書き・当日は8:55締め・施設休は表示のみ)
class MealOrderScreen extends StatefulWidget {
  const MealOrderScreen({super.key, required this.service});

  final MyDataService service;

  @override
  State<MealOrderScreen> createState() => _MealOrderScreenState();
}

class _MealOrderScreenState extends State<MealOrderScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  late DateTime _month; // 表示中の月(1日)
  final List<bool> _template = List.filled(7, false); // weekday 0=月..6=日
  Map<String, Map<String, dynamic>> _days = const {}; // 'YYYY-MM-DD' -> 行
  String? _todayLunch;
  String? _tomorrowLunch;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // 公開献立の行から昼食メニュー(以上児→未満児→最初の昼食)。
  String? _lunchOf(List<Map<String, dynamic>> rows) {
    String? pick(String ft) => rows
        .where((r) => r['meal_slot'] == 'lunch' && r['food_type'] == ft && (r['menu_text'] as String?)?.trim().isNotEmpty == true)
        .map((r) => (r['menu_text'] as String).trim())
        .firstOrNull;
    return pick('regular_over3') ??
        pick('regular_under3') ??
        rows
            .where((r) => r['meal_slot'] == 'lunch' && (r['menu_text'] as String?)?.trim().isNotEmpty == true)
            .map((r) => (r['menu_text'] as String).trim())
            .firstOrNull;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tmpl = await widget.service.fetchStaffMealWeeklyTemplate();
      for (var i = 0; i < 7; i++) {
        _template[i] = false;
      }
      for (final r in tmpl) {
        final wd = (r['weekday'] as num?)?.toInt();
        if (wd != null && wd >= 0 && wd < 7) _template[wd] = (r['will_eat'] as bool?) ?? false;
      }
      final rows = await widget.service.fetchStaffMealMonth(_month.year, _month.month);
      final days = <String, Map<String, dynamic>>{};
      for (final r in rows) {
        days[r['business_date'] as String] = r;
      }
      String? todayLunch, tomorrowLunch;
      try {
        final today = DateTime.now();
        final t0 = DateTime(today.year, today.month, today.day);
        todayLunch = _lunchOf(await widget.service.fetchMyOfficeMenuDay(t0));
        tomorrowLunch = _lunchOf(await widget.service.fetchMyOfficeMenuDay(t0.add(const Duration(days: 1))));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _days = days;
        _todayLunch = todayLunch;
        _tomorrowLunch = tomorrowLunch;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '読み込みに失敗しました'; });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('締め切り') ? '当日分の締め切り(8:55)を過ぎています' : '操作できませんでした';
        setState(() => _error = msg);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('給食の注文')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: AppColors.punchClockOut)),
                    ),
                  if (_todayLunch != null || _tomorrowLunch != null) ...[
                    _lunchCard(),
                    const SizedBox(height: 12),
                  ],
                  _templateCard(),
                  const SizedBox(height: 16),
                  _monthHeader(),
                  const SizedBox(height: 4),
                  ..._monthDays().map(_dayTile),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _lunchCard() => Card(
        color: AppColors.leafGreen.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('昼食メニュー', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 6),
              if (_todayLunch != null) Text('本日: $_todayLunch', style: const TextStyle(fontSize: 13)),
              if (_tomorrowLunch != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('明日: $_tomorrowLunch', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ),
            ],
          ),
        ),
      );

  // ① 曜日テンプレ(毎週の既定)
  Widget _templateCard() => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Text('曜日ごとの予定(毎週)', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text('ここで「食べる」にした曜日は毎週自動で注文されます。個別の変更は下のカレンダーで。',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
              for (var wd = 0; wd < 7; wd++)
                SwitchListTile(
                  dense: true,
                  value: _template[wd],
                  onChanged: _busy ? null : (v) => _run(() => widget.service.setStaffMealWeeklyTemplate(wd, v)),
                  title: Text('${_weekdays[wd]}曜日', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  secondary: Text(_template[wd] ? '食べる' : '食べない',
                      style: TextStyle(fontSize: 12, color: _template[wd] ? AppColors.leafGreen : AppColors.textSecondary)),
                ),
            ],
          ),
        ),
      );

  Widget _monthHeader() => Row(
        children: [
          IconButton(onPressed: _busy ? null : () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text('${_month.year}年${_month.month}月',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          IconButton(onPressed: _busy ? null : () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
        ],
      );

  List<DateTime> _monthDays() {
    final last = DateTime(_month.year, _month.month + 1, 0).day;
    return [for (var d = 1; d <= last; d++) DateTime(_month.year, _month.month, d)];
  }

  Widget _dayTile(DateTime date) {
    final row = _days[_fmt(date)];
    final willEat = (row?['will_eat'] as bool?) ?? false;
    final locked = (row?['locked'] as bool?) ?? false;
    final blocked = row?['blocked_reason'] as String?;
    final wd = _weekdays[date.weekday - 1];
    final isSun = date.weekday == DateTime.sunday;
    final isSat = date.weekday == DateTime.saturday;
    final label = '${date.month}/${date.day}($wd)';

    // 状態表示
    String status;
    Color statusColor;
    if (blocked == 'no_service') {
      status = '施設休(給食なし)';
      statusColor = AppColors.textSecondary;
    } else if (blocked == 'absence') {
      status = '欠勤・休暇';
      statusColor = AppColors.textSecondary;
    } else if (willEat) {
      status = '食べる';
      statusColor = AppColors.leafGreen;
    } else {
      status = '食べない';
      statusColor = AppColors.textSecondary;
    }

    final canToggle = !locked && blocked == null && !_busy;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        title: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isSun ? AppColors.punchClockOut : (isSat ? AppColors.skyBlue : AppColors.textPrimary))),
            const SizedBox(width: 10),
            Text(status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
            if (locked) ...[
              const SizedBox(width: 8),
              const Icon(Icons.lock_outline, size: 13, color: AppColors.textSecondary),
            ],
          ],
        ),
        trailing: Switch(
          value: willEat,
          onChanged: canToggle ? (v) => _run(() => widget.service.setStaffMealEntry(date, v)) : null,
        ),
      ),
    );
  }
}
