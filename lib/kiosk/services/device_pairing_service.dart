import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/secure_device_store.dart';
import '../models/paired_device.dart';

class DevicePairingException implements Exception {
  DevicePairingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 9.1 端末マスタとのペアリング状態をローカル(端末内)に保持するサービス。
/// 保管は SecureDeviceStore(iOS Keychain・ThisDeviceOnly。旧shared_preferencesからは自動移送)。
class DevicePairingService {
  DevicePairingService(this._client);

  final SupabaseClient _client;
  final _store = SecureDeviceStore();

  Future<PairedDevice?> loadPairedDevice() => _store.load();

  Future<PairedDevice> pairDevice(String deviceCode) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'pair-device',
        body: {'device_code': deviceCode},
      );
    } catch (_) {
      throw DevicePairingException('通信に失敗しました。ネットワークを確認してください。');
    }

    if (response.status != 200) {
      final data = response.data;
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : '端末登録に失敗しました。';
      throw DevicePairingException(message);
    }

    final data = response.data as Map<String, dynamic>;
    final device = PairedDevice(
      deviceId: data['device_id'] as String,
      officeId: data['office_id'] as String,
      officeName: data['office_name'] as String?,
    );

    await _store.save(device);
    return device;
  }

  Future<void> clearPairing() => _store.clear();
}
