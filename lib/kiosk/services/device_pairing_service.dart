import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/paired_device.dart';

class DevicePairingException implements Exception {
  DevicePairingException(this.message);
  final String message;

  @override
  String toString() => message;
}

const _kDeviceIdKey = 'kiosk_device_id';
const _kOfficeIdKey = 'kiosk_office_id';
const _kOfficeNameKey = 'kiosk_office_name';

/// 9.1 端末マスタとのペアリング状態をローカル(端末内)に保持するサービス。
class DevicePairingService {
  DevicePairingService(this._client);

  final SupabaseClient _client;

  Future<PairedDevice?> loadPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_kDeviceIdKey);
    final officeId = prefs.getString(_kOfficeIdKey);
    if (deviceId == null || officeId == null) return null;
    return PairedDevice(
      deviceId: deviceId,
      officeId: officeId,
      officeName: prefs.getString(_kOfficeNameKey),
    );
  }

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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceIdKey, device.deviceId);
    await prefs.setString(_kOfficeIdKey, device.officeId);
    if (device.officeName != null) {
      await prefs.setString(_kOfficeNameKey, device.officeName!);
    }

    return device;
  }

  Future<void> clearPairing() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDeviceIdKey);
    await prefs.remove(_kOfficeIdKey);
    await prefs.remove(_kOfficeNameKey);
  }
}
