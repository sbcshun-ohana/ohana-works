import 'package:flutter/material.dart';

import '../../models/my_shift.dart';
import '../../services/my_data_service.dart';
import '../../theme/app_theme.dart';

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// Phase1 C-2: 自分のシフト確認(月間・施設別)。閲覧のみ(CSV取込・変更申請は
/// 別タスク)。shiftsテーブルへのデータ投入手段がまだ無いため、当面はどの月も
/// 空表示になる。
class MyShiftScreen extends StatefulWidget {
  const MyShiftScreen({super.key, required this.service});

  final MyDataService service;

  @override
  State<MyShiftScreen> createState() => _MyShiftScreenState();
}

class _MyShiftScreenState extends State<MyShiftScreen> {
  DateTime _targetMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late Future<List<MyShift>> _shiftsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final monthStart = DateTime(_targetMonth.year, _targetMonth.month, 1);
    final monthEnd = DateTime(_targetMonth.year, _targetMonth.month + 1, 0);
    _shiftsFuture = widget.service.fetchMyShifts(monthStart: monthStart, monthEnd: monthEnd);
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetMonth,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year, now.month + 2, 1),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() {
        _targetMonth = DateTime(picked.year, picked.month, 1);
        _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自分のシフト'),
        actions: [
          TextButton(
            onPressed: _pickMonth,
            child: Text(
              '${_targetMonth.year}/${_targetMonth.month}',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<MyShift>>(
        future: _shiftsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final shifts = snapshot.data ?? const [];
          if (shifts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'この月のシフトはまだ登録されていません',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }
          final byOffice = <String, List<MyShift>>{};
          for (final shift in shifts) {
            byOffice.putIfAbsent(shift.officeName, () => []).add(shift);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final entry in byOffice.entries) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                ...entry.value.map(
                  (shift) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        '${shift.workDate.month}/${shift.workDate.day}(${_weekdayLabels[shift.workDate.weekday - 1]})',
                      ),
                      subtitle: Text(
                        '${formatShiftTime(shift.startTime)} 〜 ${formatShiftTime(shift.endTime)}'
                        '${shift.shiftType != null ? '  ${shiftTypeLabel(shift.shiftType)}' : ''}',
                      ),
                      trailing: shift.isConfirmed
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.leafGreen)
                          : const Text('未確定', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
