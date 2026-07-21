/// 9.2 ワンタイムQRトークン(サーバー発行・90秒有効・single-use消費)。
class QrToken {
  const QrToken({
    required this.token,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory QrToken.fromJson(Map<String, dynamic> json) {
    return QrToken(
      token: json['token'] as String,
      issuedAt: DateTime.parse(json['issued_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final String token;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remaining => expiresAt.difference(DateTime.now());
}
