/// 発達記録(240 fetch_child_development_records の1行)。
class DevelopmentRecord {
  DevelopmentRecord({
    required this.itemId,
    required this.ageBandCode,
    required this.domainCode,
    required this.itemName,
    required this.observationPoint,
    required this.displayOrder,
    required this.isAchieved,
    required this.achievementId,
    required this.firstAchievedOn,
    required this.method,
    required this.approvedByName,
    required this.targetYearMonth,
    required this.hasPending,
    required this.requestId,
    required this.requestedByName,
    required this.requestNote,
  });

  final String itemId;
  final String ageBandCode;
  final String domainCode;
  final String itemName;
  final String? observationPoint;
  final int displayOrder;
  final bool isAchieved;
  final String? achievementId;
  final String? firstAchievedOn;
  final String? method;
  final String? approvedByName;
  final String? targetYearMonth;
  final bool hasPending;
  final String? requestId;
  final String? requestedByName;
  final String? requestNote;

  factory DevelopmentRecord.fromJson(Map<String, dynamic> json) {
    return DevelopmentRecord(
      itemId: json['item_id'] as String,
      ageBandCode: json['age_band_code'] as String,
      domainCode: json['domain_code'] as String,
      itemName: json['item_name'] as String,
      observationPoint: json['observation_point'] as String?,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isAchieved: json['is_achieved'] as bool? ?? false,
      achievementId: json['achievement_id'] as String?,
      firstAchievedOn: json['first_achieved_on'] as String?,
      method: json['method'] as String?,
      approvedByName: json['approved_by_name'] as String?,
      targetYearMonth: json['target_year_month'] as String?,
      hasPending: json['has_pending'] as bool? ?? false,
      requestId: json['request_id'] as String?,
      requestedByName: json['requested_by_name'] as String?,
      requestNote: json['request_note'] as String?,
    );
  }
}

/// 発達記録画面のヘッダ情報(240 fetch_child_development_header)。
class DevelopmentHeader {
  DevelopmentHeader({
    required this.childName,
    required this.className,
    required this.birthDate,
    required this.applicableBand,
  });

  final String? childName;
  final String? className;
  final String? birthDate;
  final String? applicableBand;

  factory DevelopmentHeader.fromJson(Map<String, dynamic> json) {
    return DevelopmentHeader(
      childName: json['child_name'] as String?,
      className: json['class_name'] as String?,
      birthDate: json['birth_date'] as String?,
      applicableBand: json['applicable_band'] as String?,
    );
  }
}

/// 年齢区分コード → 表示ラベル。
const Map<String, String> kDevelopmentBandLabels = {
  'M00_05': '0〜5か月',
  'M06_14': '6〜14か月',
  'M15_23': '15〜23か月',
  'AGE_2': '2歳児',
  'AGE_3': '3歳児',
  'AGE_4': '4歳児',
  'AGE_5': '5歳児',
};

const List<String> kDevelopmentBandOrder = [
  'M00_05', 'M06_14', 'M15_23', 'AGE_2', 'AGE_3', 'AGE_4', 'AGE_5',
];

/// 5領域コード → 表示ラベル。
const Map<String, String> kDevelopmentDomainLabels = {
  'health': '健康',
  'relations': '人間関係',
  'environment': '環境',
  'language': '言葉',
  'expression': '表現',
};
