/// 入園時基本情報フォームの状態(fetch_my_enrollment_form の1行)。
/// form_data はセクション別JSONB(basic/address/guardians/... )をそのまま保持する。
class EnrollmentFormState {
  const EnrollmentFormState({
    required this.formId,
    required this.status,
    required this.currentStep,
    required this.formData,
    this.lastSavedAt,
    this.latestVersion,
    this.latestReviewStatus,
    this.latestReviewMessage,
    this.latestSubmittedAt,
  });

  final String formId;

  /// draft / submitted / sent_back / approved / cancelled
  final String status;
  final int currentStep;
  final Map<String, dynamic> formData;
  final DateTime? lastSavedAt;
  final int? latestVersion;
  final String? latestReviewStatus;
  final String? latestReviewMessage;
  final DateTime? latestSubmittedAt;

  bool get isEditable => status == 'draft' || status == 'sent_back';

  factory EnrollmentFormState.fromJson(Map<String, dynamic> json) {
    return EnrollmentFormState(
      formId: json['form_id'] as String,
      status: json['status'] as String,
      currentStep: (json['current_step'] as num?)?.toInt() ?? 1,
      formData: (json['form_data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      lastSavedAt: json['last_saved_at'] != null ? DateTime.parse(json['last_saved_at'] as String).toLocal() : null,
      latestVersion: (json['latest_version'] as num?)?.toInt(),
      latestReviewStatus: json['latest_review_status'] as String?,
      latestReviewMessage: json['latest_review_message'] as String?,
      latestSubmittedAt: json['latest_submitted_at'] != null
          ? DateTime.parse(json['latest_submitted_at'] as String).toLocal()
          : null,
    );
  }
}
