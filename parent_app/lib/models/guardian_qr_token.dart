/// issue-guardian-qr-token Edge Functionのレスポンス(登降園用の動的QR、90秒有効)。
class GuardianQrToken {
  const GuardianQrToken({
    required this.token,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory GuardianQrToken.fromJson(Map<String, dynamic> json) => GuardianQrToken(
        token: json['token'] as String,
        issuedAt: DateTime.parse(json['issued_at'] as String),
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  final String token;
  final DateTime issuedAt;
  final DateTime expiresAt;

  Duration get remaining => expiresAt.difference(DateTime.now());
  bool get isExpired => remaining.isNegative;
}
