/// 登降園実績の1日分(保護者向け・326)。時刻は 'HH:MM:SS' 文字列(表示側でHH:MMへ整形)。
class AttendanceRecordDay {
  const AttendanceRecordDay({
    required this.date,
    this.inTime,
    this.outTime,
    this.returnTime,
    this.departTime,
    required this.isAbsent,
    this.absenceKind,
  });

  final DateTime date;
  final String? inTime;
  final String? outTime;
  final String? returnTime;
  final String? departTime;
  final bool isAbsent;
  final String? absenceKind; // sick_absence / personal_absence / none / null

  factory AttendanceRecordDay.fromMap(Map<String, dynamic> m) => AttendanceRecordDay(
        date: DateTime.parse(m['business_date'] as String),
        inTime: m['in_time'] as String?,
        outTime: m['out_time'] as String?,
        returnTime: m['return_time'] as String?,
        departTime: m['depart_time'] as String?,
        isAbsent: m['is_absent'] == true,
        absenceKind: m['attendance_kind'] as String?,
      );
}
