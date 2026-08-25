import 'package:flutter/material.dart';

import '../../services/my_data_service.dart';
import '../../theme/app_theme.dart';

/// 給食の発注(給食管理 Phase3・336)。職員が自分の昼食の要否を日別に登録する。
/// 当日分は9:00締め。フルカバー確定シフトの職員は自動で数えられる旨を表示する。
class MealOrderScreen extends StatefulWidget {
  const MealOrderScreen({super.key, required this.service});

  final MyDataService service;

  @override
  State<MealOrderScreen> createState() => _MealOrderScreenState();
}

class _MealOrderScreenState extends State<MealOrderScreen> {
  List<Map<String, dynamic>> _days = const [];
  bool _loading = true;
  bool _busy = false;
  bool _defaultEats = true;
  String? _error;
  String? _todayLunch; // 当日の昼食メニュー(見て発注できるよう表示・献立管理AC-06)
  String? _tomorrowLunch;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  // 公開献立の行から昼食メニューを取り出す(以上児→未満児→最初の昼食の順)。
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final from = DateTime.now();
      final to = from.add(const Duration(days: 13));
      final rows = await widget.service.fetchStaffMealOrderDays(from, to);
      String? todayLunch, tomorrowLunch;
      try {
        final today = DateTime(from.year, from.month, from.day);
        todayLunch = _lunchOf(await widget.service.fetchMyOfficeMenuDay(today));
        tomorrowLunch = _lunchOf(await widget.service.fetchMyOfficeMenuDay(today.add(const Duration(days: 1))));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _days = rows;
        _defaultEats = rows.isNotEmpty ? (rows.first['default_eats'] as bool? ?? true) : true;
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
        final msg = e.toString().contains('締め切り') ? '当日分の締め切り(9:00)を過ぎています' : '操作できませんでした';
        setState(() => _error = msg);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('給食の発注')),
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
                  if (_todayLunch != null || _tomorrowLunch != null)
                    Card(
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
                    ),
                  if (_todayLunch != null || _tomorrowLunch != null) const SizedBox(height: 8),
                  Card(
                    child: SwitchListTile(
                      value: !_defaultEats,
                      onChanged: _busy ? null : (v) => _run(() => widget.service.setStaffMealDefault(!v)),
                      title: const Text('普段から給食を食べない'),
                      subtitle: const Text('ONにすると既定で対象外になります(食べる日は下で個別にONにできます)'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text('日別の要否(当日は9:00締め)',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                  ),
                  ..._days.map(_dayTile),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _dayTile(Map<String, dynamic> d) {
    final date = DateTime.parse(d['business_date'] as String);
    final auto = d['auto_eligible'] as bool? ?? false;
    final eff = d['will_eat_effective'] as bool? ?? false;
    final locked = d['locked'] as bool? ?? false;
    final wd = _weekdays[date.weekday - 1];
    final label = '${date.month}/${date.day}($wd)';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            if (auto)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.skyBlue.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('自動対象', style: TextStyle(fontSize: 11, color: AppColors.textPrimary)),
              ),
          ],
        ),
        subtitle: Text(
          locked
              ? '締め切り済み'
              : auto
                  ? 'シフトから自動で数えられます(食べない日はOFFに)'
                  : (eff ? '食べる(発注済み)' : '食べない'),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Switch(
          value: eff,
          onChanged: (locked || _busy) ? null : (v) => _run(() => widget.service.setStaffMealEntry(date, v)),
        ),
      ),
    );
  }
}
