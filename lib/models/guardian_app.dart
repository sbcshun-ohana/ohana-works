/// 保護者アプリ・後続保育機能(Phase A)の職員側で使うモデル群。
/// バックエンドはsupabase/migrations/20260714000074以降で定義された
/// 保護者ドメイン専用テーブル・RPC(admin_web側と共通)。
library;

class DailyBoardRow {
  const DailyBoardRow({
    required this.childId,
    required this.displayName,
    this.honorificSuffix,
    required this.className,
    required this.status,
    this.lastEventType,
    this.lastEventAt,
  });

  factory DailyBoardRow.fromJson(Map<String, dynamic> json) => DailyBoardRow(
        childId: json['child_id'] as String,
        displayName: json['display_name'] as String,
        honorificSuffix: json['honorific_suffix'] as String?,
        className: json['class_name'] as String,
        status: json['status'] as String,
        lastEventType: json['last_event_type'] as String?,
        lastEventAt:
            json['last_event_at'] != null ? DateTime.parse(json['last_event_at'] as String) : null,
      );

  final String childId;
  final String displayName;
  final String? honorificSuffix;
  final String className;
  final String status;
  final String? lastEventType;
  final DateTime? lastEventAt;

  String get nameLabel => '$displayName${honorificSuffix ?? ''}';
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
