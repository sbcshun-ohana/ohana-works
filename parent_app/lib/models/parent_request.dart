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
        details: (json['details'] as Map<String, dynamic>?) ?? const {},
        status: json['status'] as String,
        decisionReason: json['decision_reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String childId;
  final String requestType;
  final DateTime targetDate;
  final Map<String, dynamic> details;
  final String status;
  final String? decisionReason;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}

const parentRequestTypeLabels = {
  'absence': '欠席',
  'tardiness': '遅刻',
  'early_leave': '早退',
  'pickup_person_change': 'お迎えの方の変更',
  'other': 'その他連絡',
};

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
