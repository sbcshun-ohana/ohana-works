import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'models/paired_device.dart';
import 'screens/device_pairing_screen.dart';
import 'screens/kiosk_scan_screen.dart';
import 'services/device_pairing_service.dart';

/// iPad勤怠キオスクアプリ(9.1/9.2/9.3/10章)。
/// 職員アプリと同一コードベースの別モードとして起動する(--dart-define=APP_MODE=kiosk)。
class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ohana Works キオスク',
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
      home: const _KioskRoot(),
    );
  }
}

class _KioskRoot extends StatefulWidget {
  const _KioskRoot();

  @override
  State<_KioskRoot> createState() => _KioskRootState();
}

class _KioskRootState extends State<_KioskRoot> {
  final _pairingService = DevicePairingService(Supabase.instance.client);

  late Future<PairedDevice?> _pairedDeviceFuture;

  @override
  void initState() {
    super.initState();
    _pairedDeviceFuture = _pairingService.loadPairedDevice();
  }

  void _onPaired(PairedDevice device) {
    setState(() {
      _pairedDeviceFuture = Future.value(device);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PairedDevice?>(
      future: _pairedDeviceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final device = snapshot.data;
        if (device == null) {
          return DevicePairingScreen(
            pairingService: _pairingService,
            onPaired: _onPaired,
          );
        }
        return KioskScanScreen(device: device);
      },
    );
  }
}
