/// 保育業務(Phase1: 連絡帳ワークフロー)共通モデル群。
/// バックエンドはsupabase/migrations/20260714000055以降で定義された
/// 保育業務専用テーブル・RPC(admin_web側と共通)。
library;

class ChildcareOffice {
  const ChildcareOffice({
    required this.officeId,
    required this.officeName,
    required this.isManager,
  });

  factory ChildcareOffice.fromJson(Map<String, dynamic> json) => ChildcareOffice(
        officeId: json['office_id'] as String,
        officeName: json['office_name'] as String,
        isManager: json['is_manager'] as bool? ?? false,
      );

  final String officeId;
  final String officeName;
  final bool isManager;
}

class ChildcareClass {
  const ChildcareClass({
    required this.classId,
    required this.className,
    required this.ageGroup,
    required this.schoolYear,
  });

  factory ChildcareClass.fromJson(Map<String, dynamic> json) => ChildcareClass(
        classId: json['class_id'] as String,
        className: json['class_name'] as String,
        ageGroup: json['age_group'] as String,
        schoolYear: json['school_year'] as int,
      );

  final String classId;
  final String className;
  final String ageGroup;
  final int schoolYear;
}

class ChildcareStaffMember {
  const ChildcareStaffMember({required this.employeeId, required this.name});

  factory ChildcareStaffMember.fromJson(Map<String, dynamic> json) => ChildcareStaffMember(
        employeeId: json['employee_id'] as String,
        name: json['name'] as String,
      );

  final String employeeId;
  final String name;
}

class ClassChild {
  const ClassChild({
    required this.childId,
    required this.displayName,
    this.honorificSuffix,
    required this.gender,
    required this.enrollmentStatus,
    required this.isAbsent,
    this.absenceReason,
  });

  factory ClassChild.fromJson(Map<String, dynamic> json) => ClassChild(
        childId: json['child_id'] as String,
        displayName: json['display_name'] as String,
        honorificSuffix: json['honorific_suffix'] as String?,
        gender: json['gender'] as String,
        enrollmentStatus: json['enrollment_status'] as String,
        isAbsent: json['is_absent'] as bool? ?? false,
        absenceReason: json['absence_reason'] as String?,
      );

  final String childId;
  final String displayName;
  final String? honorificSuffix;
  final String gender;
  final String enrollmentStatus;
  final bool isAbsent;
  final String? absenceReason;

  /// honorificSuffixはDB側(honorific_suffix_resolved)で個別設定/性別既定を解決済み。
  String get nameLabel {
    return '$displayName${honorificSuffix ?? ''}';
  }
}

class ClassActivity {
  const ClassActivity({
    this.activityId,
    required this.classId,
    required this.className,
    this.assigneeEmployeeId,
    this.assigneeName,
    this.status,
    this.todayTheme,
    this.activityContent,
    this.classOverview,
    this.classAnnouncement,
    this.otherNotes,
    this.submittedAt,
    this.rejectedReason,
  });

  factory ClassActivity.fromJson(Map<String, dynamic> json) => ClassActivity(
        activityId: json['activity_id'] as String?,
        classId: json['class_id'] as String,
        className: json['class_name'] as String,
        assigneeEmployeeId: json['assignee_employee_id'] as String?,
        assigneeName: json['assignee_name'] as String?,
        status: json['status'] as String?,
        todayTheme: json['today_theme'] as String?,
        activityContent: json['activity_content'] as String?,
        classOverview: json['class_overview'] as String?,
        classAnnouncement: json['class_announcement'] as String?,
        otherNotes: json['other_notes'] as String?,
        submittedAt:
            json['submitted_at'] != null ? DateTime.parse(json['submitted_at'] as String) : null,
        rejectedReason: json['rejected_reason'] as String?,
      );

  final String? activityId;
  final String classId;
  final String className;
  final String? assigneeEmployeeId;
  final String? assigneeName;
  final String? status;
  final String? todayTheme;
  final String? activityContent;
  final String? classOverview;
  final String? classAnnouncement;
  final String? otherNotes;
  final DateTime? submittedAt;
  final String? rejectedReason;
}

class DailyContact {
  const DailyContact({
    this.contactId,
    required this.childId,
    required this.childDisplayName,
    this.childHonorificSuffix,
    this.className,
    this.assigneeEmployeeId,
    this.assigneeName,
    this.status,
    this.guardianMessage,
    this.childTodayNotes,
    this.freeNotes,
    this.aiGeneratedText,
    this.currentText,
    this.adminComment,
    this.rejectedReason,
    this.submittedAt,
    this.approvedAt,
    this.copiedAt,
    required this.isAbsent,
  });

  factory DailyContact.fromJson(Map<String, dynamic> json) => DailyContact(
        contactId: json['contact_id'] as String?,
        childId: json['child_id'] as String,
        childDisplayName: json['child_display_name'] as String,
        childHonorificSuffix: json['child_honorific_suffix'] as String?,
        className: json['class_name'] as String?,
        assigneeEmployeeId: json['assignee_employee_id'] as String?,
        assigneeName: json['assignee_name'] as String?,
        status: json['status'] as String?,
        guardianMessage: json['guardian_message'] as String?,
        childTodayNotes: json['child_today_notes'] as String?,
        freeNotes: json['free_notes'] as String?,
        aiGeneratedText: json['ai_generated_text'] as String?,
        currentText: json['current_text'] as String?,
        adminComment: json['admin_comment'] as String?,
        rejectedReason: json['rejected_reason'] as String?,
        submittedAt:
            json['submitted_at'] != null ? DateTime.parse(json['submitted_at'] as String) : null,
        approvedAt: json['approved_at'] != null ? DateTime.parse(json['approved_at'] as String) : null,
        copiedAt: json['copied_at'] != null ? DateTime.parse(json['copied_at'] as String) : null,
        isAbsent: json['is_absent'] as bool? ?? false,
      );

  final String? contactId;
  final String childId;
  final String childDisplayName;
  final String? childHonorificSuffix;
  final String? className;
  final String? assigneeEmployeeId;
  final String? assigneeName;
  final String? status;
  final String? guardianMessage;
  final String? childTodayNotes;
  final String? freeNotes;
  final String? aiGeneratedText;
  final String? currentText;
  final String? adminComment;
  final String? rejectedReason;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final DateTime? copiedAt;
  final bool isAbsent;

  String get nameLabel => '$childDisplayName${childHonorificSuffix ?? ''}';
}

class NoticeMaster {
  const NoticeMaster({required this.id, required this.label, required this.sortOrder});

  factory NoticeMaster.fromJson(Map<String, dynamic> json) => NoticeMaster(
        id: json['id'] as String,
        label: json['label'] as String,
        sortOrder: json['sort_order'] as int,
      );

  final String id;
  final String label;
  final int sortOrder;
}

/// AI連絡帳生成(§11)のアクション種別。
enum ContactAiAction {
  generate('generate', 'AI生成'),
  shorten('shorten', '短く'),
  lengthen('lengthen', '詳しく'),
  soften('soften', 'やわらかく'),
  addCare('add_care', '気遣い追加'),
  clarify('clarify', '重要事項明確化'),
  regenerate('regenerate', '作り直し');

  const ContactAiAction(this.code, this.label);
  final String code;
  final String label;
}

/// 連絡帳・クラス活動の状態(status)の画面表示ラベル。
String childcareStatusLabel(String? status) {
  switch (status) {
    case 'draft':
      return '下書き';
    case 'submitted':
      return '申請中';
    case 'approved':
      return '承認済み';
    case 'rejected':
      return '差し戻し';
    default:
      return '未着手';
  }
}
