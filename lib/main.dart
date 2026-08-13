import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'childcare_staff/childcare_staff_app.dart';
import 'config/supabase_config.dart';
import 'kiosk/kiosk_app.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_gate.dart';
import 'widgets/session_banner.dart';

/// ビルド時に `--dart-define=APP_MODE=kiosk` を指定すると受付iPadのキオスクアプリ、
/// `--dart-define=APP_MODE=childcare` を指定すると保育業務専用iPadアプリとして起動する。
/// 未指定時は職員個人スマホ向けアプリ(既定)。職員アプリ・キオスクアプリ・保育業務アプリは
/// 同一コードベースの別flavor相当で、利用シーン(個人スマホ/受付iPad/保育業務iPad)が
/// 異なるため同じ画面には混在させない。
const String _appMode = String.fromEnvironment(
  'APP_MODE',
  defaultValue: 'staff',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // プッシュ通知は staff 既定モード(個人スマホ)のみ。共有iPad(childcare/kiosk)では初期化しない。
  // iOS は GoogleService-Info.plist からネイティブ初期化するため options は渡さない。
  // plist 未配置など初期化失敗時も例外を握りつぶし、アプリ起動は継続する(push無効)。
  if (_appMode == 'staff') {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase init skipped (push disabled): $e');
    }
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(switch (_appMode) {
    'kiosk' => const KioskApp(),
    'childcare' => const ChildcareStaffApp(),
    _ => const MyApp(),
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ohana Works',
      debugShowCheckedModeBanner: false,
      // カレンダー(showDatePicker等)を日本語表示にする(俊指示 2026-08-13)。
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      // 全画面共通の「ログイン中: 氏名(役職)」常時表示(職員個人スマホアプリ=Ohana Staff)。
      // 自動ログアウトは共有iPad(Ohana Kids)側のみ。
      builder: (context, child) => Column(
        children: [
          SafeArea(bottom: false, child: const SessionBanner()),
          // 上部SafeAreaが消費したtop inset(ステータスバー/ダイナミックアイランド)を
          // 子から除去する。除去しないと内側ScaffoldのAppBarが同じtop paddingを二重計上し、
          // その分だけ全画面で下端がはみ出す(Y1: Bottom Overflow)。
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      home: const AuthGate(),
    );
  }
}
