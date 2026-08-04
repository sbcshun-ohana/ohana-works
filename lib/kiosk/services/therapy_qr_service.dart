import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/therapy_qr_resolution.dart';

class TherapyQrException implements Exception {
  TherapyQrException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 療育QR読取→外出/戻り判定を扱うサービス(resolve-therapy-qr Edge Function経由)。
/// resolve-guardian-qr とは別 Function(責務分離)。
class TherapyQrService {
  TherapyQrService(this._client);

  final SupabaseClient _client;

  Future<TherapyQrResolution> resolveTherapyQr({
    required String token,
    required String deviceId,
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'resolve-therapy-qr',
        body: {'token': token, 'device_id': deviceId},
      );
    } catch (_) {
      throw TherapyQrException('通信に失敗しました。ネットワークを確認してください。');
    }

    if (response.status != 200) {
      final data = response.data;
      final message =
          data is Map && data['error'] is String ? data['error'] as String : '処理に失敗しました。';
      throw TherapyQrException(message);
    }

    return TherapyQrResolution.fromJson(response.data as Map<String, dynamic>);
  }
}
