import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/childcare/childcare_menu_screen.dart';
import '../screens/login_screen.dart';
import '../services/childcare_service.dart';
import '../theme/app_theme.dart';
import '../widgets/inactivity_guard.dart';
import '../widgets/session_banner.dart';

/// 保育業務専用iPadアプリ。職員アプリ・キオスクアプリと同一コードベースの別モードとして
/// 起動する(--dart-define=APP_MODE=childcare)。ログイン後はホーム画面を経由せず、
/// 保育業務メニューへ直接遷移する(個人スマホ用のQR勤怠・お知らせ・各種申請は含めない)。
class ChildcareStaffApp extends StatelessWidget {
  const ChildcareStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    final navigatorKey = GlobalKey<NavigatorState>();
    return MaterialApp(
      title: 'Ohana Works 保育業務',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: navigatorKey,
      // 全画面共通の「ログイン中: 氏名(役職)」常時表示 ＋ 共有iPad向けの自動ログアウト。
      builder: (context, child) => InactivityGuard(
        navigatorKey: navigatorKey,
        child: Column(
          children: [
            SafeArea(bottom: false, child: const SessionBanner()),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
      ),
      home: const _ChildcareStaffAuthGate(),
    );
  }
}

/// 認証状態を監視し、ログイン済みなら保育業務メニュー、未ログインならログイン画面を表示する。
class _ChildcareStaffAuthGate extends StatelessWidget {
  const _ChildcareStaffAuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, auth.currentSession),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session != null) {
          return ChildcareMenuScreen(service: ChildcareService(Supabase.instance.client));
        }
        return const LoginScreen();
      },
    );
  }
}
