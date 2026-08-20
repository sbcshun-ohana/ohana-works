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
    this.createdByEmployeeId,
    this.createdByName,
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
        createdByEmployeeId: json['created_by'] as String?,
        createdByName: json['created_by_name'] as String?,
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
  final String? createdByEmployeeId;
  final String? createdByName;
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

/// 園内記録(職員専用・保護者には非表示)。
class ChildInternalNote {
  const ChildInternalNote({
    required this.id,
    required this.childId,
    required this.officeId,
    required this.noteDate,
    required this.category,
    required this.body,
    required this.aiExcluded,
    required this.authorEmployeeId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChildInternalNote.fromJson(Map<String, dynamic> json) => ChildInternalNote(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        officeId: json['office_id'] as String,
        noteDate: json['note_date'] as String,
        category: json['category'] as String,
        body: json['body'] as String,
        aiExcluded: json['ai_excluded'] as bool? ?? false,
        authorEmployeeId: json['author_employee_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String childId;
  final String officeId;
  final String noteDate;
  final String category;
  final String body;
  final bool aiExcluded;
  final String authorEmployeeId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// 園内記録の区分キー(表示順)。日本語表示名はここ1箇所に集約する
/// (admin_web側の CHILD_INTERNAL_NOTE_CATEGORY_LABELS と同一の対応)。
const List<String> kChildInternalNoteCategories = [
  'handover',
  'observation',
  'guardian_contact',
  'external_agency',
  'other',
];

String childInternalNoteCategoryLabel(String category) {
  switch (category) {
    case 'handover':
      return '申し送り';
    case 'observation':
      return '個人日誌';
    case 'guardian_contact':
      return '保護者との面談記録';
    case 'external_agency':
      return '療育等との連携記録';
    case 'other':
      return 'その他';
    default:
      return category;
  }
}
