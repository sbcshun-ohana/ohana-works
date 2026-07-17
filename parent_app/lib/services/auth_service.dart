import 'package:supabase_flutter/supabase_flutter.dart';

/// メール+パスワードによるSupabase Auth操作。
/// Sign in with Apple / Googleログインは、Apple Developer側のSign in with Apple設定と
/// Google Cloud側のOAuthクライアント登録(v0.4 §7 Phase A確認事項1)が完了してから追加する。
class GuardianAuthException implements Exception {
  GuardianAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signInWithPassword({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthApiException catch (e) {
      throw GuardianAuthException(_translate(e.message));
    }
  }

  Future<void> signUpWithPassword({required String email, required String password}) async {
    try {
      await _client.auth.signUp(email: email, password: password);
    } on AuthApiException catch (e) {
      throw GuardianAuthException(_translate(e.message));
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  String _translate(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'メールアドレスまたはパスワードが正しくありません';
    }
    if (message.contains('already registered')) {
      return 'このメールアドレスは既に登録されています。ログインしてください';
    }
    if (message.contains('Password should be')) {
      return 'パスワードは6文字以上で入力してください';
    }
    return message;
  }
}
