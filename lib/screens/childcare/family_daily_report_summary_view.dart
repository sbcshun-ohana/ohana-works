import 'package:flutter/material.dart';

import '../../models/guardian_app.dart';
import '../../theme/app_theme.dart';

/// 家庭連絡帳(保護者記入)の職員向け参照パネル。デイリーボードの詳細表示・
/// 園連絡帳の入力画面いずれからも同じ表示ロジックを使う。
class FamilyDailyReportSummaryView extends StatelessWidget {
  const FamilyDailyReportSummaryView({super.key, required this.report});

  final FamilyDailyReportSummary? report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r == null) {
      return const Text('本日分の家庭連絡帳はまだ提出されていません', style: TextStyle(color: AppColors.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!r.isSubmitted)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('※下書き中(未提出)の内容です', style: TextStyle(color: AppColors.warmOrange, fontSize: 12)),
          ),
        _row('体温', r.temperature == null ? '--' : '${r.temperature!.toStringAsFixed(1)}℃(${r.temperatureMeasuredAt ?? '--'})'),
        if (r.temperature != null && r.temperature! >= 37.5)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('37.5℃以上です', style: TextStyle(color: AppColors.punchClockOut, fontWeight: FontWeight.w600)),
          ),
        _row('症状', r.symptoms?.isNotEmpty == true ? r.symptoms! : '--'),
        _row('自宅での様子', r.homeNotes?.isNotEmpty == true ? r.homeNotes! : '--'),
        _row(
          '機嫌(夜/朝)',
          '${familyMoodLabels[r.nightMood] ?? '--'} / ${familyMoodLabels[r.morningMood] ?? '--'}',
        ),
        _row(
          '排便(夜/朝)',
          '${_bowelText(r.nightBowelCount, r.nightBowelCondition)} / ${_bowelText(r.morningBowelCount, r.morningBowelCondition)}',
        ),
        _row('睡眠', '${r.sleepStartAt ?? '--'} 〜 ${r.sleepEndAt ?? '--'}'),
        _row('夕食', '${r.dinnerContent?.isNotEmpty == true ? r.dinnerContent! : '--'}(${r.dinnerAt ?? '--'})'),
        _row('朝食', '${r.breakfastContent?.isNotEmpty == true ? r.breakfastContent! : '--'}(${r.breakfastAt ?? '--'})'),
        if (r.pickupPersonName?.isNotEmpty == true || r.pickupTimeFrom != null || r.pickupTimeTo != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warmOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person_pin_circle_rounded, color: AppColors.warmOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ('${r.pickupPersonName?.isNotEmpty == true ? 'お迎え変更あり: ${r.pickupPersonName}(${r.pickupPersonRelationship ?? '続柄未記入'})' : ''}'
                            ' 登園${r.pickupTimeFrom ?? '--'} / お迎え${r.pickupTimeTo ?? '--'}')
                        .trim(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _bowelText(int? count, String? condition) {
    if (count == null) return '--';
    if (count == 0) return '0回';
    return '$count回(${familyBowelConditionLabels[condition] ?? '--'})';
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 96, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
