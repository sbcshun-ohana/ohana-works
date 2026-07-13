import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'kiosk/kiosk_app.dart';
import 'theme/app_theme.dart';
import 'widgets/auth_gate.dart';

/// ビルド時に `--dart-define=APP_MODE=kiosk` を指定するとiPadキオスクアプリとして起動する。
/// 未指定時は職員アプリ(既定)。9.1章: 職員アプリと同一コードベースの別flavor相当。
const String _appMode = String.fromEnvironment('APP_MODE', defaultValue: 'staff');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  runApp(_appMode == 'kiosk' ? const KioskApp() : const MyApp());
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
