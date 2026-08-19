import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// ヒヤリハット・事故報告の共通ラベル/色(3区分・状態・反応など)。
class IncidentLabels {
  static const reportTypes = <String, String>{
    'hiyari': 'ヒヤリハット',
    'minor': '事故報告書・園内対応(軽症)',
    'hospital': '事故報告書・病院搬送(重大事故)',
  };
  static const reportTypesShort = <String, String>{
    'hiyari': 'ヒヤリハット',
    'minor': '園内対応(軽症)',
    'hospital': '病院搬送(重大事故)',
  };
  static const statuses = <String, String>{
    'draft': '下書き',
    'submitted': '申請中(主任承認待ち)',
    'chief_approved': '主任承認済(園長承認待ち)',
    'approved': '承認済',
  };
  static const reactionKinds = <String, String>{
    'understood': '状況をご説明しご理解いただけた',
    'other': 'その他',
  };
  static const progressKinds = <String, String>{
    'ok': '大丈夫です',
    'other': 'その他',
  };
  static const doctorInstructions = <String, String>{
    'can_attend': '今後の登園可',
    'cannot_attend': '登園不可',
  };
  static const causeKeys = <String, String>{
    'child_behavior': '子どもの状況・行動',
    'environment': '環境・設備',
    'objects': '物・遊具',
    'care_rules': '保育・対応・ルール',
  };

  static String reportType(String? v) => reportTypes[v] ?? (v ?? '');
  static String status(String? v) => statuses[v] ?? (v ?? '');

  static Color reportTypeColor(String? v) {
    switch (v) {
      case 'hospital':
        return AppColors.punchClockOut;
      case 'minor':
        return AppColors.warmOrange;
      default:
        return AppColors.skyBlue;
    }
  }

  static Color statusColor(String? v) {
    switch (v) {
      case 'approved':
        return AppColors.leafGreen;
      case 'submitted':
      case 'chief_approved':
        return AppColors.warmOrange;
      default:
        return AppColors.textSecondary;
    }
  }
}

/// 状態バッジ。
class IncidentStatusBadge extends StatelessWidget {
  const IncidentStatusBadge({super.key, required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final c = IncidentLabels.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(IncidentLabels.status(status),
          style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

/// 種別バッジ。
class IncidentTypeBadge extends StatelessWidget {
  const IncidentTypeBadge({super.key, required this.reportType, this.short = false});
  final String? reportType;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final c = IncidentLabels.reportTypeColor(reportType);
    final label = short
        ? (IncidentLabels.reportTypesShort[reportType] ?? (reportType ?? ''))
        : IncidentLabels.reportType(reportType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}
