import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCMデバイストークンの登録(push_device_tokens、20260714000101)。
/// 送信自体(Edge Function send-push-notification)はサーバー側に既に実装済み。
/// このサービスは「どの端末に送ってよいか」をサーバーへ伝える登録処理のみを担う。
class PushService {
  PushService(this._client);

  final SupabaseClient _client;

  Future<void> registerDeviceToken(String guardianId) async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token == null) return;

    await _upsertToken(guardianId, token);

    messaging.onTokenRefresh.listen((newToken) => _upsertToken(guardianId, newToken));
  }

  Future<void> _upsertToken(String guardianId, String token) async {
    await _client.from('push_device_tokens').upsert(
      {
        'guardian_id': guardianId,
        'fcm_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'last_seen_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'fcm_token',
    );
  }
}
