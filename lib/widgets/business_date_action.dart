import 'package:flutter/material.dart';

/// AppBar 用の対象日ボタン。タップで日付を選択する。既定は各画面で当日を渡す。
/// ホーム画面から対象日選択を撤去したため、対象日は各機能画面がこのボタンで持つ。
class BusinessDateAction extends StatelessWidget {
  const BusinessDateAction({super.key, required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = '${date.year}/${date.month}/${date.day}';
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(date.year - 1),
            lastDate: DateTime(date.year + 1),
          );
          if (picked != null) {
            onChanged(DateTime(picked.year, picked.month, picked.day));
          }
        },
        icon: const Icon(Icons.calendar_today_rounded, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
