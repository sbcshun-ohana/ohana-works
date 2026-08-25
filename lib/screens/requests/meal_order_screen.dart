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

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

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
      if (!mounted) return;
      setState(() {
        _days = rows;
        _defaultEats = rows.isNotEmpty ? (rows.first['default_eats'] as bool? ?? true) : true;
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
