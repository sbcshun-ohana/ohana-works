import 'package:supabase_flutter/supabase_flutter.dart';

/// ピッカーに並べる職員1名。
class PinPickerStaff {
  const PinPickerStaff({
    required this.employeeId,
    required this.name,
    this.roleCode,
    required this.hasPin,
  });

  final String employeeId;
  final String name;
  final String? roleCode;
  final bool hasPin;
}

class PinAuthException implements Exception {
  PinAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 要件3: 職員ピッカー+PIN簡易ログイン。検証・セッション発行はサーバ(Edge Function)。
/// クライアントはPIN照合しない。tokenは受領後即 verifyOTP で消費し、**ログ出力しない**。
class PinAuthService {
  PinAuthService(this._client);
  final SupabaseClient _client;

  Future<List<PinPickerStaff>> fetchPicker(String deviceId) async {
    final res = await _client.functions.invoke('pin-staff-picker', body: {'device_id': deviceId});
    if (res.status != 200) {
      throw PinAuthException(_errorOf(res.data, '職員一覧を取得できませんでした'));
    }
    final list = (res.data as Map<String, dynamic>)['staff'] as List? ?? const [];
    return list
        .map((e) => PinPickerStaff(
              employeeId: e['employee_id'] as String,
              name: e['name'] as String,
              roleCode: e['role_code'] as String?,
              hasPin: e['has_pin'] as bool? ?? false,
            ))
        .toList();
  }

  /// PINログイン。成功時は token_hash を受け取り**即座に** verifyOTP でセッション化する。
  Future<void> loginWithPin({
    required String deviceId,
    required String employeeId,
    required String pin,
  }) async {
    final res = await _client.functions.invoke('pin-login', body: {
      'device_id': deviceId,
      'employee_id': employeeId,
      'pin': pin,
    });
    if (res.status != 200) {
      throw PinAuthException(_errorOf(res.data, 'ログインに失敗しました'));
    }
    final tokenHash = (res.data as Map<String, dynamic>)['token_hash'] as String?;
    if (tokenHash == null) {
      throw PinAuthException('ログインに失敗しました');
    }
    // token はログに残さない。受領後すぐに消費する。
    await _client.auth.verifyOTP(type: OtpType.email, tokenHash: tokenHash);
  }

  /// 本人のPIN設定/変更(メール+パスワードでログイン済みで呼ぶ)。6桁・自明PIN不可はサーバ側検証。
  Future<void> setMyPin(String pin) async {
    await _client.rpc('set_my_pin', params: {'p_pin': pin});
  }

  String _errorOf(dynamic data, String fallback) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    return fallback;
  }
}
