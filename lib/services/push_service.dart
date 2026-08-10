import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 職員個人スマホ(Ohana Staff=既定モード)のFCMデバイストークン登録。
/// push_device_tokens(20260714000101、employee_id列)へ upsert する。送信自体
/// (Edge Function send-push-notification)と検出/配信cron(139/192)はサーバ側に実装済みで、
/// このサービスは「どの端末に送ってよいか」をサーバへ伝える登録処理のみを担う。
///
/// 設計方針(承認済み):
///  ・登録は staff 既定モードのログイン後のみ(共有iPad=childcare/kiosk では登録しない)。
///  ・DB変更なし。employee_id は既存 employees_select_self RLS で自分の行から取得し、
///    push_device_tokens の self ポリシー(employee_id = my_employee_id())で upsert/delete する。
///  ・Firebase未初期化(GoogleService-Info.plist 未配置など)でも例外を握りつぶし、
///    アプリ動作を止めない(push無効で継続)。
class PushService {
  PushService(this._client);

  final SupabaseClient _client;

  /// ログイン中職員の端末トークンを登録する。失敗しても例外は投げない(push無効で継続)。
  Future<void> registerDeviceToken() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      // 自分の employee_id を取得(employees_select_self RLS)。DB変更不要。
      final row = await _client
          .from('employees')
          .select('id')
          .eq('auth_user_id', userId)
          .maybeSingle();
      final employeeId = row?['id'] as String?;
      if (employeeId == null) return;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token == null) return;

      await _upsert(employeeId, token);

      // トークン更新時も同一 fcm_token 行を追従更新する。
      messaging.onTokenRefresh.listen((newToken) => _upsert(employeeId, newToken));
    } catch (e) {
      debugPrint('PushService.registerDeviceToken skipped: $e');
    }
  }

  /// ログアウト前に、この端末のトークン行を削除する(ログアウト済み端末への誤配防止)。
  /// signOut 後は my_employee_id() が null になり RLS で削除できないため、必ず signOut の前に呼ぶ。
  Future<void> unregisterCurrentDevice() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _client.from('push_device_tokens').delete().eq('fcm_token', token);
    } catch (e) {
      debugPrint('PushService.unregisterCurrentDevice skipped: $e');
    }
  }

  Future<void> _upsert(String employeeId, String token) async {
    await _client.from('push_device_tokens').upsert(
      {
        'employee_id': employeeId,
        'fcm_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'last_seen_at': DateTime.now().toIso8601String(),
      },
      // 同一端末で別職員がログインした場合は employee_id が付け替わる(端末単位で fcm_token 不変)。
      onConflict: 'fcm_token',
    );
  }
}
