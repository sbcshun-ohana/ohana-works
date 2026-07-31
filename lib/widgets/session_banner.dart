import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/role_display.dart';
import '../services/session_identity.dart';
import '../theme/app_theme.dart';

/// 全画面の最上部に常時表示する「ログイン中: 氏名(役職)」バナー＋ログアウト導線。
/// MaterialApp の builder で Navigator の上に差し込み、どの画面でも見えるようにする。
/// 未ログイン時は何も表示しない(ログイン画面ではバナーを出さない)。
class SessionBanner extends StatefulWidget {
  const SessionBanner({super.key});

  @override
  State<SessionBanner> createState() => _SessionBannerState();
}

class _SessionBannerState extends State<SessionBanner> {
  SessionIdentity? _identity;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final identity = await fetchMySessionIdentity();
    if (mounted) setState(() => _identity = identity);
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final identity = _identity;
    if (Supabase.instance.client.auth.currentUser == null || identity == null) {
      return const SizedBox.shrink();
    }
    return Material(
      color: AppColors.textPrimary,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.account_circle_rounded, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ログイン中: ${identity.name}(${roleDisplayName(identity.roleCode)})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded, size: 16, color: Colors.white),
              label: const Text('ログアウト', style: TextStyle(color: Colors.white, fontSize: 13)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
          ],
        ),
      ),
    );
  }
}
