import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../services/push_service.dart';

/// 認証状態を監視し、ログイン済みならホーム画面、未ログインならログイン画面を表示する。
/// ログイン確立時に一度だけFCMトークンを登録する(staff既定モードのみ。共有iPadの
/// childcare/kioskアプリはこのAuthGateを使わないため登録されない)。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// 同一userで多重登録しないためのガード。ログアウトでnullに戻す。
  String? _registeredForUserId;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, auth.currentSession),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session != null) {
          // ログイン確立後に一度だけトークン登録(画面表示はブロックしない)。
          if (_registeredForUserId != session.user.id) {
            _registeredForUserId = session.user.id;
            PushService(Supabase.instance.client).registerDeviceToken();
          }
          return const HomeScreen();
        }
        _registeredForUserId = null;
        return const LoginScreen();
      },
    );
  }
}
