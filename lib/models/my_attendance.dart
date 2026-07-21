/// 自分の勤怠(fetch_my_attendance RPCの結果)。月次集計テーブルではなく
/// daily_attendances(生データ)から都度組み立てられる。施設帰属は当日最初の
/// time_punches.office_idを採用し、無ければhome_office_idを使う(admin側の
/// fetch_attendance_by_officeと同じロジック)。
class MyAttendanceDay {
  const MyAttendanceDay({
    required this.workDate,
    required this.officeId,
    required this.officeName,
    this.actualClockInAt,
    this.approvedWorkStartAt,
    this.actualClockOutAt,
    this.approvedWorkEndAt,
    this.actualBreakStartAt,
    this.actualBreakEndAt,
    this.approvedBreakMinutes,
    this.shiftType,
    this.alertCodes = const [],
  });

  factory MyAttendanceDay.fromJson(Map<String, dynamic> json) => MyAttendanceDay(
        workDate: DateTime.parse(json['work_date'] as String),
        officeId: json['office_id'] as String,
        officeName: json['office_name'] as String,
        actualClockInAt: _parseNullable(json['actual_clock_in_at']),
        approvedWorkStartAt: _parseNullable(json['approved_work_start_at']),
        actualClockOutAt: _parseNullable(json['actual_clock_out_at']),
        approvedWorkEndAt: _parseNullable(json['approved_work_end_at']),
        actualBreakStartAt: _parseNullable(json['actual_break_start_at']),
        actualBreakEndAt: _parseNullable(json['actual_break_end_at']),
        approvedBreakMinutes: json['approved_break_minutes'] as int?,
        shiftType: json['shift_type'] as String?,
        alertCodes: (json['alert_codes'] as List?)?.cast<String>() ?? const [],
      );

  static DateTime? _parseNullable(dynamic value) => value == null ? null : DateTime.parse(value as String);

  final DateTime workDate;
  final String officeId;
  final String officeName;
  final DateTime? actualClockInAt;
  final DateTime? approvedWorkStartAt;
  final DateTime? actualClockOutAt;
  final DateTime? approvedWorkEndAt;
  final DateTime? actualBreakStartAt;
  final DateTime? actualBreakEndAt;
  final int? approvedBreakMinutes;
  final String? shiftType;
  final List<String> alertCodes;
}
