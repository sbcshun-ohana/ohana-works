/// 家庭連絡帳(保護者→園、family_daily_reports)。
/// 体温は35.0〜42.0℃・0.1℃刻み。37.5℃以上は警告表示するが提出はブロックしない。
class FamilyDailyReport {
  const FamilyDailyReport({
    required this.id,
    required this.childId,
    required this.businessDate,
    this.temperature,
    this.temperatureMeasuredAt,
    this.symptoms,
    this.homeNotes,
    required this.status,
  });

  factory FamilyDailyReport.fromJson(Map<String, dynamic> json) => FamilyDailyReport(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        businessDate: DateTime.parse(json['business_date'] as String),
        temperature: json['temperature'] == null ? null : double.parse(json['temperature'].toString()),
        temperatureMeasuredAt: json['temperature_measured_at'] as String?,
        symptoms: json['symptoms'] as String?,
        homeNotes: json['home_notes'] as String?,
        status: json['status'] as String,
      );

  final String id;
  final String childId;
  final DateTime businessDate;
  final double? temperature;
  final String? temperatureMeasuredAt;
  final String? symptoms;
  final String? homeNotes;
  final String status;

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';
  bool get hasFeverWarning => temperature != null && temperature! >= 37.5;
}
