import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kiosk/models/paired_device.dart';

/// 端末登録情報(device_id 等)の保管。要件3(PIN簡易ログイン)の端末縛りの土台。
///
/// device_id はログイン画面などフォアグラウンドからのみ読む(バックグラウンド/プッシュ受信では
/// 読まない — FCMは push_device_tokens を使う)。そのため iOS は
/// **kSecAttrAccessibleWhenUnlockedThisDeviceOnly**(unlocked_this_device)を採用する。
/// ThisDeviceOnly により iCloud Keychain 同期・暗号化バックアップからの別端末復元を防ぐ。
///
/// 旧バージョンで shared_preferences(平文)に保存された device_id は、初回読み込み時に
/// Keychain へ移送し、旧 prefs を削除する(冪等)。
class SecureDeviceStore {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kDeviceId = 'kiosk_device_id';
  static const _kOfficeId = 'kiosk_office_id';
  static const _kOfficeName = 'kiosk_office_name';

  Future<PairedDevice?> load() async {
    await _migrateFromPrefsIfNeeded();
    final deviceId = await _storage.read(key: _kDeviceId);
    final officeId = await _storage.read(key: _kOfficeId);
    if (deviceId == null || officeId == null) return null;
    return PairedDevice(
      deviceId: deviceId,
      officeId: officeId,
      officeName: await _storage.read(key: _kOfficeName),
    );
  }

  Future<void> save(PairedDevice device) async {
    await _storage.write(key: _kDeviceId, value: device.deviceId);
    await _storage.write(key: _kOfficeId, value: device.officeId);
    if (device.officeName != null) {
      await _storage.write(key: _kOfficeName, value: device.officeName!);
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _kDeviceId);
    await _storage.delete(key: _kOfficeId);
    await _storage.delete(key: _kOfficeName);
  }

  /// 旧 shared_preferences → Keychain への一度きりの移送(冪等)。
  Future<void> _migrateFromPrefsIfNeeded() async {
    final alreadyInKeychain = await _storage.read(key: _kDeviceId);
    final prefs = await SharedPreferences.getInstance();
    if (alreadyInKeychain == null) {
      final id = prefs.getString(_kDeviceId);
      final office = prefs.getString(_kOfficeId);
      if (id != null && office != null) {
        await _storage.write(key: _kDeviceId, value: id);
        await _storage.write(key: _kOfficeId, value: office);
        final name = prefs.getString(_kOfficeName);
        if (name != null) await _storage.write(key: _kOfficeName, value: name);
      }
    }
    // 旧平文prefsは常に削除(移送済み or 元々無い)。Keychainのみを正とする。
    await prefs.remove(_kDeviceId);
    await prefs.remove(_kOfficeId);
    await prefs.remove(_kOfficeName);
  }
}
