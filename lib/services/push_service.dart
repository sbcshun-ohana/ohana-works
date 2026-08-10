import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 職員個人スマホ(Ohana Staff=既定モード)のFCMデバイストークン登録。
/// push_device_tokens(20260714000101、employee_id列)へ upsert する。送信自体
/// (Edge Function send-push-notification)と検出/配信cron(139/192)はサーバ側に実装済みで、
/// このサービスは「どの端末に送ってよいか」をサーバへ伝える登録処理のみを担う。
///
/// iOSの罠(2026-08-07 実機ログで確定):
///   APNsトークン設定前に getToken() を呼ぶと [firebase_messaging/apns-token-not-set] で失敗する。
///   本実装は (1) getAPNSToken() が非nullになるまでリトライしてから getToken()、
///   (2) onTokenRefresh 購読でも登録(初回競合やトークン更新の取りこぼし防止)、
///   (3) 失敗時は false を返し、呼び出し側(AuthGate)がフォアグラウンド復帰/次回ログインで再試行、
///   の三重で登録漏れを防ぐ。
///
/// 設計方針(承認済み):
///   ・登録は staff 既定モードのログイン後のみ(共有iPad=childcare/kiosk では登録しない)。
///   ・DB変更なし。employee_id は既存 employees_select_self RLS で自分の行から取得し、
///     push_device_tokens の self ポリシー(employee_id = my_employee_id())で upsert/delete する。
///   ・Firebase未初期化(GoogleService-Info.plist 未配置など)でも例外を握りつぶし、
///     アプリ動作を止めない(push無効で継続)。
class PushService {
  PushService(this._client);

  final SupabaseClient _client;

  /// onTokenRefresh は多重購読を避けるためアプリ内で一度だけ張る。
  static bool _tokenRefreshWired = false;

  /// 成功時にログへ出す目印(俊の実機確認用にgrepする文字列)。
  static const String _successLog = '[push] device token registered';

  /// ログイン中職員の端末トークンを登録する。
  /// 戻り値: 登録できたら true。false のときは呼び出し側が復帰時/次回ログインで再試行する。
  /// 例外は投げない(push無効で継続)。
  Future<bool> registerDeviceToken() async {
    try {
      final employeeId = await _currentEmployeeId();
      if (employeeId == null) return false;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] permission denied');
        return false;
      }

      // 初回競合やトークン更新を取りこぼさないため、getToken の成否によらず先に購読を張る。
      // APNs設定完了後にトークンが生成されると onTokenRefresh 経由でも登録される。
      _wireTokenRefresh(messaging);

      // iOS: APNsトークン設定前の getToken() は apns-token-not-set で失敗するため待つ。
      if (Platform.isIOS) {
        var apns = await messaging.getAPNSToken();
        for (var i = 0; apns == null && i < 20; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          apns = await messaging.getAPNSToken();
        }
        if (apns == null) {
          // ここで諦めても onTokenRefresh か、復帰時/次回ログインの再試行で拾う。
          debugPrint('[push] APNS token not ready after wait (will retry on resume/next login)');
          return false;
        }
      }

      final token = await messaging.getToken();
      if (token == null) return false;

      await _upsert(employeeId, token);
      debugPrint('$_successLog (employee=$employeeId)');
      return true;
    } catch (e) {
      debugPrint('[push] registerDeviceToken skipped: $e');
      return false;
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
      debugPrint('[push] unregisterCurrentDevice skipped: $e');
    }
  }

  /// トークン更新(および初回競合後の生成)を取りこぼさないための購読。アプリ内で一度だけ張る。
  void _wireTokenRefresh(FirebaseMessaging messaging) {
    if (_tokenRefreshWired) return;
    _tokenRefreshWired = true;
    messaging.onTokenRefresh.listen((newToken) async {
      try {
        final employeeId = await _currentEmployeeId();
        if (employeeId == null) return;
        await _upsert(employeeId, newToken);
        debugPrint('$_successLog (onTokenRefresh, employee=$employeeId)');
      } catch (e) {
        debugPrint('[push] onTokenRefresh upsert skipped: $e');
      }
    });
  }

  /// ログイン中職員の employee_id。employees_select_self RLS で取得(DB変更不要)。
  Future<String?> _currentEmployeeId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _client
        .from('employees')
        .select('id')
        .eq('auth_user_id', userId)
        .maybeSingle();
    return row?['id'] as String?;
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
