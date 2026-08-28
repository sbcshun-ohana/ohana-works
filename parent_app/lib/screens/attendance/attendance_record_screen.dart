import 'package:flutter/material.dart';

import '../../models/attendance_record_day.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// 登降園実績(保護者向け・326)。お子さまの月間 出欠+登降園時刻を表で確認する(閲覧のみ)。
class AttendanceRecordScreen extends StatefulWidget {
  const AttendanceRecordScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<AttendanceRecordScreen> createState() => _AttendanceRecordScreenState();
}

class _AttendanceRecordScreenState extends State<AttendanceRecordScreen> {
  late int _year;
  late int _month;
  bool _loading = true;
  String? _error;
  Map<int, AttendanceRecordDay> _byDay = const {};

  static const _weekdays = ["日", "月", "火", "水", "木", "金", "土"];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final days = await widget.guardianService.fetchChildAttendanceMonth(widget.child.childId, _year, _month);
      final map = {for (final d in days) d.date.day: d};
      if (mounted) setState(() { _byDay = map; _loading = false; });
    } catch (e) {
      // 原因特定用(RPC未適用・権限・パース等を握りつぶさない)。UI文言は変えない。
      debugPrint('attendance month fetch error: $e');
      if (mounted) setState(() { _error = '登降園実績の取得に失敗しました'; _loading = false; });
    }
  }

  void _shiftMonth(int delta) {
    var y = _year, m = _month + delta;
    if (m < 1) { m = 12; y--; } else if (m > 12) { m = 1; y++; }
    setState(() { _year = y; _month = m; });
    _load();
  }

  String _hm(String? t) => t == null ? '' : (t.length >= 5 ? t.substring(0, 5) : t);
  String? _absLabel(AttendanceRecordDay d) =>
      d.absenceKind == 'sick_absence' ? '病欠' : d.absenceKind == 'personal_absence' ? '都合欠' : (d.isAbsent ? '欠席' : null);

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    // 月合計(出席=登降園記録あり / 病欠 / 都合欠)。
    int present = 0, sick = 0, personal = 0;
    for (final d in _byDay.values) {
      if (d.isAbsent) {
        if (d.absenceKind == 'sick_absence') {
          sick++;
        } else if (d.absenceKind == 'personal_absence') {
          personal++;
        }
      } else if (d.inTime != null || d.departTime != null) {
        present++;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('登降園実績')),
      body: Column(
        children: [
          // 月切替 + お子さま名
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: AppColors.surface,
            child: Row(
              children: [
                IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Expanded(
                  child: Column(
                    children: [
                      Text('$_year年 $_month月', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(widget.child.displayName, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
          ),
          // 月合計サマリー
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                _summaryChip('出席', present, AppColors.leafGreen),
                const SizedBox(width: 8),
                _summaryChip('病欠', sick, AppColors.warmOrange),
                const SizedBox(width: 8),
                _summaryChip('都合欠', personal, AppColors.textSecondary),
              ],
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: daysInMonth + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) return _headerRow();
                      final day = i;
                      final g = DateTime(_year, _month, day).weekday % 7; // 0=日
                      final d = _byDay[day];
                      return _dayRow(day, g, d);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int count, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text('$label $count日', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _headerRow() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFECEFF3)))),
        child: const Row(
          children: [
            SizedBox(width: 56, child: Text('日', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
            Expanded(child: Text('登園', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
            Expanded(child: Text('降園', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
            SizedBox(width: 64, child: Text('状態', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary))),
          ],
        ),
      );

  Widget _dayRow(int day, int g, AttendanceRecordDay? d) {
    final dowColor = g == 0 ? AppColors.danger : g == 6 ? AppColors.skyBlue : AppColors.textPrimary;
    final abs = d != null ? _absLabel(d) : null;
    final bg = g == 0
        ? AppColors.danger.withValues(alpha: 0.05)
        : g == 6
            ? AppColors.skyBlue.withValues(alpha: 0.05)
            : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      // color と decoration は併用不可(Flutter assert)。色は decoration 側に含める。
      decoration: BoxDecoration(color: bg, border: const Border(bottom: BorderSide(color: Color(0xFFECEFF3)))),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Row(
              children: [
                SizedBox(width: 24, child: Text('$day', style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(_weekdays[g], style: TextStyle(fontSize: 12, color: dowColor)),
              ],
            ),
          ),
          Expanded(child: Text(d != null ? _hm(d.inTime) : '', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(d != null ? _hm(d.departTime) : '', style: const TextStyle(fontWeight: FontWeight.w600))),
          SizedBox(
            width: 64,
            child: abs != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.warmOrange.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                    child: Text(abs, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warmOrange)),
                  )
                : (d != null && (d.inTime != null || d.departTime != null))
                    ? const Text('出席', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.leafGreen))
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
