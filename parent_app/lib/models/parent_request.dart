import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 保護者申請(欠席/遅刻/早退/お迎えの方の変更/その他連絡)。
/// detailsのキーはadmin_web側の汎用表示(key: value)にそのまま出るため日本語キーで統一する。
/// 感染症は独立した申請種類ではなく、欠席のdetails内(感染症による欠席か・感染症の種類)に統合する。
class ParentRequest {
  const ParentRequest({
    required this.id,
    required this.childId,
    required this.requestType,
    required this.targetDate,
    this.endDate,
    this.absenceKind,
    this.medicationKinds,
    required this.details,
    required this.status,
    this.decisionReason,
    required this.createdAt,
  });

  factory ParentRequest.fromJson(Map<String, dynamic> json) => ParentRequest(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        requestType: json['request_type'] as String,
        targetDate: DateTime.parse(json['target_date'] as String),
        endDate: json['end_date'] != null ? DateTime.parse(json['end_date'] as String) : null,
        absenceKind: json['absence_kind'] as String?,
        medicationKinds: (json['medication_kinds'] as List?)?.cast<String>(),
        details: (json['details'] as Map<String, dynamic>?) ?? const {},
        status: json['status'] as String,
        decisionReason: json['decision_reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String childId;
  final String requestType;
  final DateTime targetDate;

  /// 欠席の期間指定(終了日)。null=単日(target_date のみ)。
  final DateTime? endDate;

  /// 欠席種別。'sick_absence'(病気)/'personal_absence'(家庭の都合)。absence 申請のみ。
  final String? absenceKind;

  /// 服薬連絡(201)の薬の種類(日本語ラベル)。medication以外はnull。
  final List<String>? medicationKinds;
  final Map<String, dynamic> details;
  final String status;
  final String? decisionReason;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}

/// 欠席種別の表示ラベル(absence_kind → 日本語)。
const absenceKindLabels = {
  'sick_absence': '病気',
  'personal_absence': '家庭の都合',
};

const parentRequestTypeLabels = {
  'absence': '欠席',
  'tardiness': '遅刻',
  'early_leave': '早退',
  'pickup_person_change': 'お迎えの方の変更',
  'medication': '服薬連絡',
  'other': 'その他連絡',
};

/// 服薬連絡(201)の薬の種類の選択肢(日本語ラベル・DB medication_kinds にそのまま保存)。
/// 変更・追加はここで一元管理する(文言のハードコード分散禁止)。
const List<String> medicationKindOptions = [
  '風邪薬',
  '咳止め',
  '鼻水・鼻炎の薬',
  '解熱剤',
  '抗生剤',
  '整腸剤・下痢止め',
  '塗り薬(皮膚)',
  '目薬',
  'アレルギーの薬',
  'その他',
];

/// 申請種類ごとの一覧表示用アイコン・色(「一目でわかる」ようにするための視覚的な目印)。
const Map<String, IconData> parentRequestTypeIcons = {
  'absence': Icons.event_busy_rounded,
  'tardiness': Icons.schedule_rounded,
  'early_leave': Icons.logout_rounded,
  'pickup_person_change': Icons.people_alt_rounded,
  'other': Icons.chat_bubble_outline_rounded,
};

const Map<String, Color> parentRequestTypeColors = {
  'absence': AppColors.warmOrange,
  'tardiness': AppColors.skyBlue,
  'early_leave': AppColors.skyBlue,
  'pickup_person_change': AppColors.leafGreen,
  'other': AppColors.leafGreen,
};

String parentRequestStatusLabel(String status) {
  switch (status) {
    case 'approved':
      return '承認済み';
    case 'rejected':
      return '差し戻し';
    case 'pending':
    default:
      return '審査中';
  }
}

/// parent_request_messages(保護者⇔職員のやりとり)。
class ParentRequestMessage {
  const ParentRequestMessage({
    required this.id,
    required this.senderType,
    required this.message,
    required this.createdAt,
  });

  factory ParentRequestMessage.fromJson(Map<String, dynamic> json) => ParentRequestMessage(
        id: json['id'] as String,
        senderType: json['sender_type'] as String,
        message: json['message'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String senderType;
  final String message;
  final DateTime createdAt;

  bool get isFromGuardian => senderType == 'guardian';
}

/// infectious_disease_masters(感染症申請の選択肢)。
class InfectiousDiseaseMaster {
  const InfectiousDiseaseMaster({
    required this.id,
    required this.name,
    required this.category,
    required this.requiresOpinionLetter,
    required this.requiresReturnForm,
  });

  factory InfectiousDiseaseMaster.fromJson(Map<String, dynamic> json) => InfectiousDiseaseMaster(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        requiresOpinionLetter: json['requires_opinion_letter'] as bool,
        requiresReturnForm: json['requires_return_form'] as bool,
      );

  final String id;
  final String name;
  final String category;
  final bool requiresOpinionLetter;
  final bool requiresReturnForm;
}
