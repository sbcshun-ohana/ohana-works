/// 保護者アプリ・後続保育機能(Phase A)の職員側で使うモデル群。
/// バックエンドはsupabase/migrations/20260714000074以降で定義された
/// 保護者ドメイン専用テーブル・RPC(admin_web側と共通)。
library;

class DailyBoardRow {
  const DailyBoardRow({
    required this.childId,
    required this.displayName,
    this.honorificSuffix,
    required this.classId,
    required this.className,
    required this.status,
    this.lastEventType,
    this.lastEventAt,
    this.familyDailyReportStatus,
    this.temperature,
    this.hasPickupChange = false,
    this.pickupPersonName,
    this.pickupPersonRelationship,
    this.pickupTimeFrom,
    this.pickupTimeTo,
  });

  factory DailyBoardRow.fromJson(Map<String, dynamic> json) => DailyBoardRow(
        childId: json['child_id'] as String,
        displayName: json['display_name'] as String,
        honorificSuffix: json['honorific_suffix'] as String?,
        classId: json['class_id'] as String,
        className: json['class_name'] as String,
        status: json['status'] as String,
        lastEventType: json['last_event_type'] as String?,
        lastEventAt:
            json['last_event_at'] != null ? DateTime.parse(json['last_event_at'] as String) : null,
        familyDailyReportStatus: json['family_daily_report_status'] as String?,
        temperature: json['temperature'] == null ? null : double.parse(json['temperature'].toString()),
        hasPickupChange: json['has_pickup_change'] as bool? ?? false,
        pickupPersonName: json['pickup_person_name'] as String?,
        pickupPersonRelationship: json['pickup_person_relationship'] as String?,
        pickupTimeFrom: json['pickup_time_from'] as String?,
        pickupTimeTo: json['pickup_time_to'] as String?,
      );

  final String childId;
  final String displayName;
  final String? honorificSuffix;
  final String classId;
  final String className;
  final String status;
  final String? lastEventType;
  final DateTime? lastEventAt;
  final String? familyDailyReportStatus;
  final double? temperature;
  final bool hasPickupChange;
  final String? pickupPersonName;
  final String? pickupPersonRelationship;
  final String? pickupTimeFrom;
  final String? pickupTimeTo;

  String get nameLabel => '$displayName${honorificSuffix ?? ''}';
}

/// 在籍登園状況サマリー(fetch_daily_board_summary_for_office の1行)。
/// 数字はRPC側集計を正とし、クライアントで再集計しない(admin_webと一致させるため)。
class DailyBoardSummary {
  const DailyBoardSummary({
    required this.enrolled,
    required this.expected,
    required this.attended,
    required this.absent,
    required this.presentNow,
  });

  factory DailyBoardSummary.fromJson(Map<String, dynamic> json) => DailyBoardSummary(
        enrolled: json['enrolled'] as int? ?? 0,
        expected: json['expected'] as int? ?? 0,
        attended: json['attended'] as int? ?? 0,
        absent: json['absent'] as int? ?? 0,
        presentNow: json['present_now'] as int? ?? 0,
      );

  final int enrolled;
  final int expected;
  final int attended;
  final int absent;
  final int presentNow;
}

/// 天気記録(daily_weather_records の1行)。施設×日で1行。
class WeatherRecord {
  const WeatherRecord({required this.weather, this.temperature, this.humidity});

  factory WeatherRecord.fromJson(Map<String, dynamic> json) => WeatherRecord(
        weather: json['weather'] as String,
        temperature: json['temperature'] == null ? null : double.parse(json['temperature'].toString()),
        humidity: json['humidity'] == null ? null : double.parse(json['humidity'].toString()),
      );

  final String weather;
  final double? temperature;
  final double? humidity;
}

const weatherOptions = ['晴れ', '曇り', '雨', '雪', 'その他'];

const familyMoodLabels = {'good': '良い', 'normal': '普通', 'bad': '悪い'};
const familyBowelConditionLabels = {'normal': '普通', 'soft': '軟便', 'hard': '硬便', 'small': '少量便'};

/// 家庭連絡帳(family_daily_reports)の職員側閲覧用サマリー。保護者アプリの
/// FamilyDailyReportモデルと同じテーブルを参照する(職員アプリ・保護者アプリは別Flutter
/// プロジェクトのためモデルクラスは重複定義)。
class FamilyDailyReportSummary {
  const FamilyDailyReportSummary({
    required this.status,
    this.temperature,
    this.temperatureMeasuredAt,
    this.symptoms,
    this.homeNotes,
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
  });

  factory FamilyDailyReportSummary.fromJson(Map<String, dynamic> json) => FamilyDailyReportSummary(
        status: json['status'] as String,
        temperature: json['temperature'] == null ? null : double.parse(json['temperature'].toString()),
        temperatureMeasuredAt: json['temperature_measured_at'] as String?,
        symptoms: json['symptoms'] as String?,
        homeNotes: json['home_notes'] as String?,
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
      );

  final String status;
  final double? temperature;
  final String? temperatureMeasuredAt;
  final String? symptoms;
  final String? homeNotes;
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

  bool get isSubmitted => status == 'submitted';
}

String dailyBoardStatusLabel(String status) {
  switch (status) {
    case 'not_arrived':
      return '未登園';
    case 'present':
      return '在園中';
    case 'picked_up':
      return '降園済み';
    case 'absent':
      return '欠席';
    default:
      return status;
  }
}

class GuardianRow {
  const GuardianRow({
    required this.guardianId,
    required this.name,
    this.phone,
    this.email,
    required this.status,
    this.linkedChildren,
  });

  factory GuardianRow.fromJson(Map<String, dynamic> json) => GuardianRow(
        guardianId: json['guardian_id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        status: json['status'] as String,
        linkedChildren: json['linked_children'] as String?,
      );

  final String guardianId;
  final String name;
  final String? phone;
  final String? email;
  final String status;
  final String? linkedChildren;
}

class GuardianInvitationRow {
  const GuardianInvitationRow({
    required this.invitationId,
    required this.childId,
    required this.childDisplayName,
    required this.role,
    required this.expiresAt,
    required this.status,
  });

  factory GuardianInvitationRow.fromJson(Map<String, dynamic> json) => GuardianInvitationRow(
        invitationId: json['invitation_id'] as String,
        childId: json['child_id'] as String,
        childDisplayName: json['child_display_name'] as String,
        role: json['role'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        status: json['status'] as String,
      );

  final String invitationId;
  final String childId;
  final String childDisplayName;
  final String role;
  final DateTime expiresAt;
  final String status;
}

String guardianInvitationStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return '招待中';
    case 'accepted':
      return '受諾済み';
    case 'expired':
      return '期限切れ';
    case 'revoked':
      return '取消済み';
    default:
      return status;
  }
}

/// 招待発行時の園児選択に使う(既存のfetch_children_for_office RPCと同じ形)。
class ChildForInvitation {
  const ChildForInvitation({
    required this.childId,
    required this.displayName,
    this.honorificSuffix,
    this.className,
  });

  factory ChildForInvitation.fromJson(Map<String, dynamic> json) => ChildForInvitation(
        childId: json['child_id'] as String,
        displayName: json['display_name'] as String,
        honorificSuffix: json['honorific_suffix'] as String?,
        className: json['class_name'] as String?,
      );

  final String childId;
  final String displayName;
  final String? honorificSuffix;
  final String? className;

  String get nameLabel => '$displayName${honorificSuffix ?? ''}';
}
