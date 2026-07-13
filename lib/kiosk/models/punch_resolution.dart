/// 10章: QR読取直後の自動判定結果(確認画面表示用)。
class PunchResolution {
  const PunchResolution({
    required this.employeeId,
    required this.employeeName,
    required this.candidates,
    required this.confirmationToken,
  });

  factory PunchResolution.fromJson(Map<String, dynamic> json) {
    return PunchResolution(
      employeeId: json['employee_id'] as String,
      employeeName: json['employee_name'] as String,
      candidates: (json['candidates'] as List).cast<String>(),
      confirmationToken: json['confirmation_token'] as String,
    );
  }

  final String employeeId;
  final String employeeName;
  final List<String> candidates;
  final String confirmationToken;
}

/// 打刻確定/代理打刻の結果。
class PunchResult {
  const PunchResult({
    required this.employeeName,
    required this.punchType,
    required this.message,
  });

  factory PunchResult.fromJson(Map<String, dynamic> json) {
    return PunchResult(
      employeeName: json['employee_name'] as String,
      punchType: json['punch_type'] as String,
      message: json['message'] as String,
    );
  }

  final String employeeName;
  final String punchType;
  final String message;
}
