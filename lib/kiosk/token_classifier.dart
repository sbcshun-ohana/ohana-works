import 'dart:convert';

/// 読み取ったQRトークンが職員用(issue-qr-token)か保護者用(issue-guardian-qr-token)かを
/// クライアント側で判定する。署名検証は行わず、JWTのペイロード部分(2番目のセグメント)を
/// デコードして中身を覗くだけ(検証自体は各resolve系Edge Functionがサーバー側で行う)。
enum QrTokenKind { staff, guardian, unknown }

QrTokenKind classifyQrToken(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return QrTokenKind.unknown;

  try {
    final normalized = base64Url.normalize(parts[1]);
    final payloadJson = utf8.decode(base64Url.decode(normalized));
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    if (payload['type'] == 'guardian') return QrTokenKind.guardian;
    if (payload.containsKey('employee_id')) return QrTokenKind.staff;
  } catch (_) {
    return QrTokenKind.unknown;
  }
  return QrTokenKind.unknown;
}
