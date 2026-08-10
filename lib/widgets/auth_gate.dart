import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../services/push_service.dart';

/// 認証状態を監視し、ログイン済みならホーム画面、未ログインならログイン画面を表示する。
/// ログイン確立時にFCMトークンを登録する(staff既定モードのみ。共有iPadの childcare/kiosk
/// アプリはこのAuthGateを使わないため登録されない)。
///
/// iOSは初回起動直後だとAPNsトークン未設定で登録が失敗しうるため、成功するまで
///  (1)ログイン時 (2)フォアグラウンド復帰時 (3)次回ログイン時 に再試行する。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  /// 登録に「成功した」userId。成功するまでは再試行対象のまま。
  String? _registeredForUserId;

  /// 同時多重登録を避けるためのガード。
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // フォアグラウンド復帰時に、未登録なら再試行(初回のAPNs競合を拾う)。
    if (state == AppLifecycleState.resumed) {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) _maybeRegister(session.user.id);
    }
  }

  void _maybeRegister(String userId) {
    if (_registeredForUserId == userId || _inFlight) return;
    _inFlight = true;
    PushService(Supabase.instance.client).registerDeviceToken().then((ok) {
      _inFlight = false;
      if (ok) _registeredForUserId = userId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, auth.currentSession),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session != null) {
          _maybeRegister(session.user.id); // 成功するまで再試行(画面表示はブロックしない)
          return const HomeScreen();
        }
        _registeredForUserId = null; // ログアウトで次回ログイン時の再登録を許可
        return const LoginScreen();
      },
    );
  }
}
