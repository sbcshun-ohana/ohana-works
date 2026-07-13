import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 9.4章 打刻種別および10章の選択肢(再出勤/打刻間違い/管理者に確認)の表示情報。
class PunchTypeDisplay {
  const PunchTypeDisplay({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  static const Map<String, PunchTypeDisplay> _values = {
    'clock_in': PunchTypeDisplay(
      label: '出勤',
      color: AppColors.punchClockIn,
      icon: Icons.login_rounded,
    ),
    'break_start': PunchTypeDisplay(
      label: '休憩開始',
      color: AppColors.punchBreakStart,
      icon: Icons.free_breakfast_rounded,
    ),
    'break_end': PunchTypeDisplay(
      label: '休憩終了',
      color: AppColors.punchBreakEnd,
      icon: Icons.restart_alt_rounded,
    ),
    'clock_out': PunchTypeDisplay(
      label: '退勤',
      color: AppColors.punchClockOut,
      icon: Icons.logout_rounded,
    ),
    'mistake': PunchTypeDisplay(
      label: '打刻間違い',
      color: AppColors.punchCancel,
      icon: Icons.undo_rounded,
    ),
    'admin_review': PunchTypeDisplay(
      label: '管理者に確認',
      color: AppColors.punchWarning,
      icon: Icons.support_agent_rounded,
    ),
  };

  static PunchTypeDisplay of(String punchType) {
    return _values[punchType] ??
        const PunchTypeDisplay(
          label: '不明',
          color: AppColors.punchError,
          icon: Icons.error_outline_rounded,
        );
  }
}
