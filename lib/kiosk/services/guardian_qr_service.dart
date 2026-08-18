import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/guardian_qr_resolution.dart';

class GuardianQrException implements Exception {
  GuardianQrException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 保護者QR読取→登降園判定を扱うサービス(resolve-guardian-qr Edge Function経由)。
class GuardianQrService {
  GuardianQrService(this._client);

  final SupabaseClient _client;

  Future<GuardianQrResolution> resolveGuardianQr({
    required String token,
    required String deviceId,
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'resolve-guardian-qr',
        body: {'token': token, 'device_id': deviceId},
      );
    } catch (_) {
      throw GuardianQrException('通信に失敗しました。ネットワークを確認してください。');
    }

    if (response.status != 200) {
      final data = response.data;
      final message =
          data is Map && data['error'] is String ? data['error'] as String : '処理に失敗しました。';
      throw GuardianQrException(message);
    }

    return GuardianQrResolution.fromJson(response.data as Map<String, dynamic>);
  }

  /// 兄弟一括登降園の確定(234)。session_id と選択(child_id+action)を送る。
  /// 戻り値: 各児の結果 {child_id, result, reason}。
  Future<List<Map<String, dynamic>>> applyFamilyCheckin({
    required String sessionId,
    required List<Map<String, String>> selections,
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'resolve-guardian-qr',
        body: {'session_id': sessionId, 'selections': selections},
      );
    } catch (_) {
      throw GuardianQrException('通信に失敗しました。ネットワークを確認してください。');
    }
    if (response.status != 200) {
      final data = response.data;
      final message =
          data is Map && data['error'] is String ? data['error'] as String : '確定に失敗しました。';
      throw GuardianQrException(message);
    }
    final data = response.data as Map<String, dynamic>;
    return ((data['results'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }
}
