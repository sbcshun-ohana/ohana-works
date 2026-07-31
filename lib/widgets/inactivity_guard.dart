import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ohana Kids(保育業務iPad)の自動ログアウト。共有端末で前の人がログインしたまま
/// 別の人が操作する事故を防ぐ。最後の操作から [timeout] 無操作で自動ログアウトし、
/// [warningBefore] 前に予告ダイアログを出してタップで延長できる。
///
/// タイムアウトはアプリ定数(既定10分・下限5分)。DB設定化はしない。
/// showDialog は Navigator の上(builder)から呼ぶため [navigatorKey] のcontextを使う。
class InactivityGuard extends StatefulWidget {
  const InactivityGuard({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.timeout = const Duration(minutes: 10),
    this.warningBefore = const Duration(minutes: 1),
  }) : assert(timeout >= const Duration(minutes: 5), '自動ログアウトは5分以下に設定できない');

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final Duration timeout;
  final Duration warningBefore;

  @override
  State<InactivityGuard> createState() => _InactivityGuardState();
}

class _InactivityGuardState extends State<InactivityGuard> {
  Timer? _warnTimer;
  Timer? _logoutTimer;
  bool _warningOpen = false;

  bool get _loggedIn => Supabase.instance.client.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void dispose() {
    _warnTimer?.cancel();
    _logoutTimer?.cancel();
    super.dispose();
  }

  void _reset() {
    _warnTimer?.cancel();
    _logoutTimer?.cancel();
    if (!_loggedIn) return;
    _warnTimer = Timer(widget.timeout - widget.warningBefore, _showWarning);
    _logoutTimer = Timer(widget.timeout, _logout);
  }

  void _onActivity([PointerEvent? _]) {
    // 予告ダイアログ表示中はダイアログのボタンで延長/ログアウトを決めるため、
    // 背後の操作ではタイマーをリセットしない。
    if (_warningOpen) return;
    _reset();
  }

  Future<void> _showWarning() async {
    final ctx = widget.navigatorKey.currentContext;
    if (!_loggedIn || ctx == null) return;
    _warningOpen = true;
    final extend = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('まもなく自動ログアウトします'),
        content: const Text('操作がないため、まもなく自動ログアウトします。続けるにはタップしてください。\n(入力途中の内容は下書きとして保存されています)'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: const Text('ログアウト')),
          ElevatedButton(onPressed: () => Navigator.of(dialogCtx).pop(true), child: const Text('続ける')),
        ],
      ),
    );
    _warningOpen = false;
    if (extend == true) {
      _reset();
    } else {
      await _logout();
    }
  }

  Future<void> _logout() async {
    _warnTimer?.cancel();
    _logoutTimer?.cancel();
    // 予告ダイアログが残っていれば閉じる。
    if (_warningOpen) {
      widget.navigatorKey.currentState?.maybePop();
      _warningOpen = false;
    }
    if (_loggedIn) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onActivity,
      onPointerMove: _onActivity,
      child: widget.child,
    );
  }
}
