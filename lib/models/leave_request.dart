/// 15.1 有給休暇の使用単位。
enum LeaveUsageUnit {
  day('day', '1日'),
  halfDay('half_day', '半日'),
  hour('hour', '時間単位');

  const LeaveUsageUnit(this.code, this.label);

  final String code;
  final String label;

  static LeaveUsageUnit fromCode(String code) {
    return LeaveUsageUnit.values.firstWhere((u) => u.code == code);
  }
}

/// 15.3 遅刻・早退の種別。
enum TardinessSubType {
  tardiness('tardiness', '遅刻'),
  earlyLeave('early_leave', '早退');

  const TardinessSubType(this.code, this.label);

  final String code;
  final String label;

  static TardinessSubType fromCode(String code) {
    return TardinessSubType.values.firstWhere((t) => t.code == code);
  }
}

/// 6.4 情報変更申請で選べる変更項目。
enum InfoChangeField {
  address('address', '住所'),
  phone('phone', '電話番号'),
  bankAccount('bank_account', '振込先口座');

  const InfoChangeField(this.code, this.label);

  final String code;
  final String label;

  static InfoChangeField fromCode(String code) {
    return InfoChangeField.values.firstWhere((f) => f.code == code);
  }
}

/// bank_transfer_accounts.account_type の選択肢。
const bankAccountTypes = ['普通', '当座'];

/// 15.1 残数は「日+時間」の複合で管理する。
class LeaveBalance {
  const LeaveBalance({
    required this.remainingDays,
    required this.remainingHours,
    required this.hoursPerDay,
  });

  final int remainingDays;
  final double remainingHours;
  final double hoursPerDay;

  String get display {
    if (remainingHours == 0) return '$remainingDays日';
    final hoursText = remainingHours % 1 == 0
        ? remainingHours.toStringAsFixed(0)
        : remainingHours.toStringAsFixed(1);
    return '$remainingDays日 $hoursText時間';
  }
}

/// 職員連絡(お知らせ)と同じく単一テーブルrequestsを種別ごとに扱う。
/// 15章/28.4 各種申請(有給/欠勤/遅刻早退/情報変更)の共通モデル。
class AppRequest {
  const AppRequest({
    required this.id,
    required this.employeeId,
    required this.requestType,
    required this.targetDate,
    required this.details,
    required this.status,
    required this.createdAt,
    this.targetEndDate,
    this.approverId,
    this.approvedAt,
    this.decisionReason,
    this.employeeName,
    this.officeName,
  });

  factory AppRequest.fromJson(Map<String, dynamic> json) {
    final employee = json['employees'] as Map<String, dynamic>?;
    final office = employee?['offices'] as Map<String, dynamic>?;
    return AppRequest(
      id: json['id'] as String,
      employeeId: json['employee_id'] as String,
      requestType: json['request_type'] as String,
      targetDate: DateTime.parse(json['target_date'] as String),
      targetEndDate: json['target_end_date'] != null
          ? DateTime.parse(json['target_end_date'] as String)
          : null,
      details: (json['details'] as Map?)?.cast<String, dynamic>() ?? const {},
      status: json['status'] as String,
      approverId: json['approver_id'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      decisionReason: json['decision_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      employeeName: employee?['name'] as String?,
      officeName: office?['name'] as String?,
    );
  }

  final String id;
  final String employeeId;
  final String requestType;
  final DateTime targetDate;
  final DateTime? targetEndDate;
  final Map<String, dynamic> details;
  final String status;
  final String? approverId;
  final DateTime? approvedAt;
  final String? decisionReason;
  final DateTime createdAt;
  final String? employeeName;
  final String? officeName;
}

/// 申請種別コード(request_type)の画面表示ラベル。
String requestTypeLabel(String requestType) {
  switch (requestType) {
    case 'paid_leave':
      return '有給休暇';
    case 'absence':
      return '欠勤連絡';
    case 'tardiness_early_leave':
      return '遅刻・早退';
    case 'info_change':
      return '登録情報変更';
    default:
      return requestType;
  }
}

/// 申請ステータス(request_status)の画面表示ラベル。
String requestStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return '承認待ち';
    case 'approved':
      return '承認済み';
    case 'rejected':
      return '却下';
    case 'cancelled':
      return '取消';
    default:
      return status;
  }
}
