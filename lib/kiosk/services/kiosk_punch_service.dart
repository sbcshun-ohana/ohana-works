import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/punch_resolution.dart';

class KioskPunchException implements Exception {
  KioskPunchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 9.2/9.3/10章: QR検証・打刻確定・代理打刻を扱うサービス。
/// いずれもEdge Function(service role)経由で行い、クライアントからテーブルへ直接書込しない。
class KioskPunchService {
  KioskPunchService(this._client);

  final SupabaseClient _client;

  Future<T> _invoke<T>(
    String functionName,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) onSuccess,
  ) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(functionName, body: body);
    } catch (_) {
      throw KioskPunchException('通信に失敗しました。ネットワークを確認してください。');
    }

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : '処理に失敗しました。';
      throw KioskPunchException(message);
    }

    return onSuccess(response.data as Map<String, dynamic>);
  }

  Future<PunchResolution> resolveQrPunch({
    required String token,
    required String deviceId,
  }) {
    return _invoke(
      'resolve-qr-punch',
      {'token': token, 'device_id': deviceId},
      PunchResolution.fromJson,
    );
  }

  Future<PunchResult> confirmPunch({
    required String confirmationToken,
    required String punchType,
    required String deviceId,
  }) {
    return _invoke(
      'confirm-punch',
      {
        'confirmation_token': confirmationToken,
        'punch_type': punchType,
        'device_id': deviceId,
      },
      PunchResult.fromJson,
    );
  }

  Future<PunchResult> proxyPunch({
    required String employeeNumber,
    required String adminPin,
    required String punchType,
    required String deviceId,
  }) {
    return _invoke(
      'proxy-punch',
      {
        'employee_number': employeeNumber,
        'admin_pin': adminPin,
        'punch_type': punchType,
        'device_id': deviceId,
      },
      PunchResult.fromJson,
    );
  }
}
