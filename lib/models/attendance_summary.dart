/// 11章/12章 月次勤怠集計。attendance_summaries(20260714000007)に対応。
class AttendanceSummary {
  const AttendanceSummary({
    required this.id,
    required this.employeeId,
    required this.targetMonth,
    required this.attendanceDays,
    required this.prescribedMinutes,
    required this.actualWorkedMinutes,
    required this.dailyOvertimeMinutes,
    required this.weeklyOvertimeMinutes,
    required this.monthlyOvertimeMinutes,
    required this.overtimeMinutes,
    required this.overtimeOver60hMinutes,
    required this.lateNightMinutes,
    required this.statutoryHolidayMinutes,
    required this.absenceDays,
    required this.tardinessEarlyLeaveCount,
    required this.workTimeSystem,
    required this.computedAt,
    this.employeeName,
    this.officeName,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    final employee = json['employees'] as Map<String, dynamic>?;
    final office = employee?['offices'] as Map<String, dynamic>?;
    return AttendanceSummary(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      targetMonth: DateTime.parse(json['target_month'] as String),
      attendanceDays: json['attendance_days'] as int,
      prescribedMinutes: json['prescribed_minutes'] as int,
      actualWorkedMinutes: json['actual_worked_minutes'] as int,
      dailyOvertimeMinutes: json['daily_overtime_minutes'] as int,
      weeklyOvertimeMinutes: json['weekly_overtime_minutes'] as int,
      monthlyOvertimeMinutes: json['monthly_overtime_minutes'] as int,
      overtimeMinutes: json['overtime_minutes'] as int,
      overtimeOver60hMinutes: json['overtime_over_60h_minutes'] as int,
      lateNightMinutes: json['late_night_minutes'] as int,
      statutoryHolidayMinutes: json['statutory_holiday_minutes'] as int,
      absenceDays: json['absence_days'] as int,
      tardinessEarlyLeaveCount: json['tardiness_early_leave_count'] as int,
      workTimeSystem: json['work_time_system'] as String,
      computedAt: DateTime.parse(json['computed_at'] as String),
      employeeName: employee?['name'] as String?,
      officeName: office?['name'] as String?,
    );
  }

  final String id;
  final String employeeId;
  final DateTime targetMonth;
  final int attendanceDays;
  final int prescribedMinutes;
  final int actualWorkedMinutes;
  final int dailyOvertimeMinutes;
  final int weeklyOvertimeMinutes;
  final int monthlyOvertimeMinutes;
  final int overtimeMinutes;
  final int overtimeOver60hMinutes;
  final int lateNightMinutes;
  final int statutoryHolidayMinutes;
  final int absenceDays;
  final int tardinessEarlyLeaveCount;
  final String workTimeSystem;
  final DateTime computedAt;
  final String? employeeName;
  final String? officeName;
}

/// 分を「◯時間◯分」表記に変換する。
String formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return '$hours時間$remainder分';
}

/// 15.1 有給自動付与エンジンと同じ実行履歴パターン。
class AttendanceSummaryRun {
  const AttendanceSummaryRun({
    required this.id,
    required this.targetMonth,
    required this.totalEmployees,
    required this.createdAt,
    this.runByName,
  });

  factory AttendanceSummaryRun.fromJson(Map<String, dynamic> json) {
    final runBy = json['employees'] as Map<String, dynamic>?;
    return AttendanceSummaryRun(
      id: json['id'] as String,
      targetMonth: DateTime.parse(json['target_month'] as String),
      totalEmployees: json['total_employees'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      runByName: runBy?['name'] as String?,
    );
  }

  final String id;
  final DateTime targetMonth;
  final int totalEmployees;
  final DateTime createdAt;
  final String? runByName;
}
