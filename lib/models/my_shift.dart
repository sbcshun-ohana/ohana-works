/// 13.5 自分のシフト(shiftsを自己SELECT、officesを埋め込みで取得)。
class MyShift {
  const MyShift({
    required this.workDate,
    required this.officeId,
    required this.officeName,
    this.startTime,
    this.endTime,
    this.breakMinutes,
    this.shiftType,
    required this.status,
  });

  factory MyShift.fromJson(Map<String, dynamic> json) {
    final office = json['offices'] as Map<String, dynamic>?;
    return MyShift(
      workDate: DateTime.parse(json['work_date'] as String),
      officeId: json['office_id'] as String,
      officeName: office?['name'] as String? ?? '(施設不明)',
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      breakMinutes: json['break_minutes'] as int?,
      shiftType: json['shift_type'] as String?,
      status: json['status'] as String,
    );
  }

  final DateTime workDate;
  final String officeId;
  final String officeName;
  final String? startTime;
  final String? endTime;
  final int? breakMinutes;
  final String? shiftType;
  final String status;

  bool get isConfirmed => status == 'confirmed';
}

/// 13.5 シフト区分(コード化)の表示ラベル。admin_webのshiftTypeLabels.tsと同じ対応。
const Map<String, String> shiftTypeLabels = {
  'normal_work': '通常勤務',
  'holiday_substitute_saturday_work': '祝日代替土曜勤務',
  'distributed_holiday_substitute_work': '分散祝日代替勤務',
  'statutory_holiday_work': '法定休日労働',
  'non_statutory_holiday_work': '法定外休日勤務',
  'event_work': '行事出勤',
  'paid_leave': '有給',
  'absence': '欠勤',
  'company_holiday': '会社所定休日',
  'national_holiday': '国民の祝日',
  'year_end_new_year_holiday': '年末年始休日',
  'requires_admin_review': '管理者確認対象',
};

String shiftTypeLabel(String? code) {
  if (code == null) return '';
  return shiftTypeLabels[code] ?? code;
}

/// "09:00:00" 形式の time 文字列を "09:00" に整形する。
String formatShiftTime(String? time) {
  if (time == null) return '--:--';
  final parts = time.split(':');
  if (parts.length < 2) return time;
  return '${parts[0]}:${parts[1]}';
}
