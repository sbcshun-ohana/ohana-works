const familyMoodLabels = {'good': '良い', 'normal': '普通', 'bad': '悪い'};
const familyBowelConditionLabels = {'normal': '普通', 'soft': '軟便', 'hard': '硬便', 'small': '少量便'};

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
    this.nightMood,
    this.morningMood,
    this.nightBowelCount,
    this.nightBowelCondition,
    this.morningBowelCount,
    this.morningBowelCondition,
    this.sleepStartAt,
    this.sleepEndAt,
    this.dinnerContent,
    this.dinnerAt,
    this.breakfastContent,
    this.breakfastAt,
    this.pickupPersonName,
    this.pickupPersonRelationship,
    this.pickupTimeFrom,
    this.pickupTimeTo,
    this.poolParticipation,
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
        nightMood: json['night_mood'] as String?,
        morningMood: json['morning_mood'] as String?,
        nightBowelCount: json['night_bowel_count'] as int?,
        nightBowelCondition: json['night_bowel_condition'] as String?,
        morningBowelCount: json['morning_bowel_count'] as int?,
        morningBowelCondition: json['morning_bowel_condition'] as String?,
        sleepStartAt: json['sleep_start_at'] as String?,
        sleepEndAt: json['sleep_end_at'] as String?,
        dinnerContent: json['dinner_content'] as String?,
        dinnerAt: json['dinner_at'] as String?,
        breakfastContent: json['breakfast_content'] as String?,
        breakfastAt: json['breakfast_at'] as String?,
        pickupPersonName: json['pickup_person_name'] as String?,
        pickupPersonRelationship: json['pickup_person_relationship'] as String?,
        pickupTimeFrom: json['pickup_time_from'] as String?,
        pickupTimeTo: json['pickup_time_to'] as String?,
        poolParticipation: json['pool_participation'] as bool?,
      );

  final String id;
  final String childId;
  final DateTime businessDate;
  final double? temperature;
  final String? temperatureMeasuredAt;
  final String? symptoms;
  final String? homeNotes;
  final String status;
  final String? nightMood;
  final String? morningMood;
  final int? nightBowelCount;
  final String? nightBowelCondition;
  final int? morningBowelCount;
  final String? morningBowelCondition;
  final String? sleepStartAt;
  final String? sleepEndAt;
  final String? dinnerContent;
  final String? dinnerAt;
  final String? breakfastContent;
  final String? breakfastAt;
  final String? pickupPersonName;
  final String? pickupPersonRelationship;
  final String? pickupTimeFrom;
  final String? pickupTimeTo;
  final bool? poolParticipation; // 夏期のプール参加(◯=true / ×=false / null=未回答)

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';
  bool get hasFeverWarning => temperature != null && temperature! >= 37.5;
  bool get hasPickupChange => pickupPersonName != null && pickupPersonName!.isNotEmpty;
}
