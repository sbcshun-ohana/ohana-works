import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/guardian_profile.dart';
import '../services/auth_service.dart';
import '../services/guardian_service.dart';
import '../services/push_service.dart';
import 'home/home_screen.dart';
import 'invitation/invitation_entry_screen.dart';
import 'login/login_screen.dart';

/// ログイン状態と、招待受諾済みかどうかで表示画面を振り分けるルート画面。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _client = Supabase.instance.client;
  late final _authService = AuthService(_client);
  late final _guardianService = GuardianService(_client);

  Future<GuardianProfile?>? _profileFuture;
  String? _profileFutureForUserId;

  void _reloadProfile() {
    setState(() {
      _profileFuture = _guardianService.fetchMyProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authService.onAuthStateChange,
      initialData: AuthState(AuthChangeEvent.initialSession, _authService.currentSession),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? _authService.currentSession;
        if (session == null) {
          _profileFuture = null;
          _profileFutureForUserId = null;
          return LoginScreen(authService: _authService);
        }

        if (_profileFutureForUserId != session.user.id) {
          _profileFutureForUserId = session.user.id;
          _profileFuture = _guardianService.fetchMyProfile();
        }

        return FutureBuilder<GuardianProfile?>(
          future: _profileFuture,
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              return InvitationEntryScreen(
                guardianService: _guardianService,
                onAccepted: _reloadProfile,
              );
            }

            PushService(_client).registerDeviceToken(profile.id);

            return HomeScreen(guardianService: _guardianService, profile: profile);
          },
        );
      },
    );
  }
}
