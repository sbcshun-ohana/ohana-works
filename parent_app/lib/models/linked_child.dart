/// 保護者に紐づく園児(guardian_child_links + children + 当日のdaily_child_status)。
class LinkedChild {
  const LinkedChild({
    required this.childId,
    required this.displayName,
    this.honorificSuffix,
    required this.role,
    this.className,
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
      displayName: children?['display_name'] as String? ?? '',
      honorificSuffix: children?['honorific_suffix'] as String?,
      role: json['role'] as String,
      className: classInfo?['class_name'] as String?,
      todayStatus: todayStatus,
    );
  }

  final String childId;
  final String displayName;
  final String? honorificSuffix;
  final String role;
  final String? className;
  final String? todayStatus;

  String get nameLabel => '$displayName${honorificSuffix ?? ''}';
  bool get isPrimary => role == 'primary';
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
