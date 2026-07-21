/// 保護者に紐づく園児(guardian_child_links + children + 当日のdaily_child_status)。
class LinkedChild {
  const LinkedChild({
    required this.childId,
    required this.officeId,
    required this.displayName,
    this.honorificSuffix,
    required this.role,
    this.classId,
    this.className,
    this.ageGroup,
    this.todayStatus,
  });

  factory LinkedChild.fromJson(Map<String, dynamic> json, {String? todayStatus}) {
    final children = json['children'] as Map<String, dynamic>?;
    final enrollments = children?['child_class_enrollments'] as List<dynamic>?;
    final activeEnrollment = enrollments?.cast<Map<String, dynamic>>().where(
          (e) => e['effective_end_date'] == null,
        ).firstOrNull;
    final classInfo = activeEnrollment?['childcare_classes'] as Map<String, dynamic>?;

    return LinkedChild(
      childId: json['child_id'] as String,
      officeId: children?['office_id'] as String? ?? '',
      displayName: children?['display_name'] as String? ?? '',
      honorificSuffix: children?['honorific_suffix'] as String?,
      role: json['role'] as String,
      classId: activeEnrollment?['class_id'] as String?,
      className: classInfo?['class_name'] as String?,
      ageGroup: classInfo?['age_group'] as String?,
      todayStatus: todayStatus,
    );
  }

  final String childId;
  final String officeId;
  final String displayName;
  final String? honorificSuffix;
  final String role;
  final String? classId;
  final String? className;
  final String? ageGroup;
  final String? todayStatus;

  String get nameLabel => '$displayName${honorificSuffix ?? ''}';
  bool get isPrimary => role == 'primary';

  /// age_groupは「クラス名／◯歳児」形式(例: 「はな組／0歳児」)。「／」の後ろの歳児部分から
  /// 数字を取り出す。取得できない・想定外の書式の場合はnull(安全側に倒し必須化しない)。
  int? get ageGroupYears {
    final source = ageGroup;
    if (source == null) return null;
    final match = RegExp(r'／\s*(\d+)\s*歳児').firstMatch(source);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  /// 0〜2歳児クラスのみ、家庭連絡帳の「自宅での様子」入力を必須とする。
  bool get requiresHomeNotes {
    final years = ageGroupYears;
    return years != null && years <= 2;
  }
}

String childStatusLabel(String? status) {
  switch (status) {
    case 'present':
      return '在園中';
    case 'picked_up':
      return '降園済み';
    case 'absent':
      return '欠席';
    case 'not_arrived':
    default:
      return '未登園';
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
