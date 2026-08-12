import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../kiosk/models/paired_device.dart';
import '../kiosk/services/device_pairing_service.dart';
import '../screens/childcare/childcare_home_screen.dart';
import '../screens/childcare/childcare_menu_screen.dart';
import '../screens/childcare/pin_login_screen.dart';
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
            // 上部SafeAreaが消費したtop insetを子から除去(二重計上によるY1オーバーフロー回避。
            // staffアプリ main.dart と同一対処)。
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
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
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;
        if (session != null) {
          return _ChildcareRootRouter(
            service: ChildcareService(Supabase.instance.client),
          );
        }
        return const _ChildcareLoginRouter();
      },
    );
  }
}

/// ログイン後のルート分岐: childcare_home_enabled がいずれかの施設で有効ならホーム画面、
/// そうでなければ従来の保育業務メニュー。取得失敗/フラグOFFは安全側=従来メニュー。
class _ChildcareRootRouter extends StatefulWidget {
  const _ChildcareRootRouter({required this.service});

  final ChildcareService service;

  @override
  State<_ChildcareRootRouter> createState() => _ChildcareRootRouterState();
}

class _ChildcareRootRouterState extends State<_ChildcareRootRouter> {
  late Future<bool> _homeEnabledFuture;

  @override
  void initState() {
    super.initState();
    _homeEnabledFuture = _resolveHomeEnabled();
  }

  Future<bool> _resolveHomeEnabled() async {
    try {
      final offices = await widget.service.fetchMyChildcareOffices();
      for (final office in offices) {
        if (await widget.service.isChildcareHomeEnabled(office.officeId)) {
          return true;
        }
      }
    } catch (_) {
      // 取得失敗は安全側=従来メニュー。
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _homeEnabledFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) {
          return ChildcareHomeScreen(service: widget.service);
        }
        return ChildcareMenuScreen(service: widget.service);
      },
    );
  }
}

/// 未ログイン時のルーティング: 登録端末なら職員ピッカー+PIN、未登録端末は
/// メール+パスワード(+この端末を登録)。「メール+パスワードでログイン」への切替も可能。
class _ChildcareLoginRouter extends StatefulWidget {
  const _ChildcareLoginRouter();

  @override
  State<_ChildcareLoginRouter> createState() => _ChildcareLoginRouterState();
}

class _ChildcareLoginRouterState extends State<_ChildcareLoginRouter> {
  final _pairingService = DevicePairingService(Supabase.instance.client);
  late Future<PairedDevice?> _deviceFuture;
  bool _forceEmail = false;

  @override
  void initState() {
    super.initState();
    _deviceFuture = _pairingService.loadPairedDevice();
  }

  Future<void> _pairDevice() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('この端末を保育業務端末として登録'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '管理者から受け取った端末コードを入力してください。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: '端末コード'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('登録'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      await _pairingService.pairDevice(code);
      if (mounted) {
        setState(() {
          _deviceFuture = _pairingService.loadPairedDevice();
          _forceEmail = false;
        });
      }
    } on DevicePairingException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PairedDevice?>(
      future: _deviceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final device = snapshot.data;
        if (device != null && !_forceEmail) {
          return PinLoginScreen(
            device: device,
            onUsePassword: () => setState(() => _forceEmail = true),
          );
        }
        // メール+パスワード。未登録端末は「この端末を登録」、登録端末は「PINログインに戻る」を出す。
        return LoginScreen(
          footer: TextButton(
            onPressed: device != null
                ? () => setState(() => _forceEmail = false)
                : _pairDevice,
            child: Text(device != null ? '← PINログインに戻る' : 'この端末を保育業務端末として登録'),
          ),
        );
      },
    );
  }
}
