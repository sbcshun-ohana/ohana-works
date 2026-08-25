import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 時刻入力を Material標準の時計ダイアログ(showTimePicker)ではなく「時」「分」のプルダウン
/// 選択に統一する共通ピッカー(俊確定 2026-08-12・Ohana Kids と同一挙動)。
///
/// showTimePicker と同じ呼び出し形(context / initialTime)・同じ戻り値(`Future<TimeOfDay?>`)の
/// ドロップイン置換。分は既定で1分刻み。
Future<TimeOfDay?> showTimeDropdownPicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  int minuteStep = 1,
}) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) {
      int hour = initialTime.hour;
      int minute = initialTime.minute - (initialTime.minute % minuteStep);
      final minutes = <int>[for (var m = 0; m < 60; m += minuteStep) m];
      String two(int v) => v.toString().padLeft(2, '0');
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('時刻を選択'),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: hour,
                items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text(two(h)))],
                onChanged: (v) => setState(() => hour = v ?? hour),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('時', style: TextStyle(fontSize: 16))),
              DropdownButton<int>(
                value: minutes.contains(minute) ? minute : minutes.first,
                items: [for (final m in minutes) DropdownMenuItem(value: m, child: Text(two(m)))],
                onChanged: (v) => setState(() => minute = v ?? minute),
              ),
              const Padding(padding: EdgeInsets.only(left: 8), child: Text('分', style: TextStyle(fontSize: 16))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('キャンセル')),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(TimeOfDay(hour: hour, minute: minute)),
              style: TextButton.styleFrom(foregroundColor: AppColors.skyBlue),
              child: const Text('決定'),
            ),
          ],
        ),
      );
    },
  );
}
