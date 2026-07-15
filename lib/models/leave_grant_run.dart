/// 15.1 有給自動付与エンジンの実行結果サマリー。
class LeaveGrantRun {
  const LeaveGrantRun({
    required this.id,
    required this.targetDate,
    required this.totalEvaluated,
    required this.totalGranted,
    required this.totalSkipped,
    required this.createdAt,
    this.runByName,
  });

  factory LeaveGrantRun.fromJson(Map<String, dynamic> json) {
    final runBy = json['employees'] as Map<String, dynamic>?;
    return LeaveGrantRun(
      id: json['id'] as String,
      targetDate: DateTime.parse(json['target_date'] as String),
      totalEvaluated: json['total_evaluated'] as int,
      totalGranted: json['total_granted'] as int,
      totalSkipped: json['total_skipped'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      runByName: runBy?['name'] as String?,
    );
  }

  final String id;
  final DateTime targetDate;
  final int totalEvaluated;
  final int totalGranted;
  final int totalSkipped;
  final DateTime createdAt;
  final String? runByName;
}

/// 15.1 有給自動付与エンジンの職員ごとの評価結果(8割出勤要件の判定内訳)。
class LeaveGrantRunResult {
  const LeaveGrantRunResult({
    required this.employeeId,
    required this.milestoneDate,
    required this.prescribedDays,
    required this.attendedDays,
    required this.attendanceRate,
    required this.eligible,
    this.grantedDays,
    this.basis,
    this.skipReason,
    this.employeeName,
  });

  factory LeaveGrantRunResult.fromJson(Map<String, dynamic> json) {
    final employee = json['employees'] as Map<String, dynamic>?;
    return LeaveGrantRunResult(
      employeeId: json['employee_id'] as String,
      milestoneDate: DateTime.parse(json['milestone_date'] as String),
      prescribedDays: json['prescribed_days'] as int,
      attendedDays: json['attended_days'] as int,
      attendanceRate: (json['attendance_rate'] as num).toDouble(),
      eligible: json['eligible'] as bool,
      grantedDays: (json['granted_days'] as num?)?.toDouble(),
      basis: json['basis'] as String?,
      skipReason: json['skip_reason'] as String?,
      employeeName: employee?['name'] as String?,
    );
  }

  final String employeeId;
  final DateTime milestoneDate;
  final int prescribedDays;
  final int attendedDays;
  final double attendanceRate;
  final bool eligible;
  final double? grantedDays;
  final String? basis;
  final String? skipReason;
  final String? employeeName;
}
