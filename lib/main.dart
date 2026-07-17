import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'childcare_staff/childcare_staff_app.dart';
import 'config/supabase_config.dart';
import 'kiosk/kiosk_app.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_gate.dart';

/// ビルド時に `--dart-define=APP_MODE=kiosk` を指定すると受付iPadのキオスクアプリ、
/// `--dart-define=APP_MODE=childcare` を指定すると保育業務専用iPadアプリとして起動する。
/// 未指定時は職員個人スマホ向けアプリ(既定)。職員アプリ・キオスクアプリ・保育業務アプリは
/// 同一コードベースの別flavor相当で、利用シーン(個人スマホ/受付iPad/保育業務iPad)が
/// 異なるため同じ画面には混在させない。
const String _appMode = String.fromEnvironment('APP_MODE', defaultValue: 'staff');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}
