import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// メール+パスワード・Sign in with Apple・Google SignInによるSupabase Auth操作。
class GuardianAuthException implements Exception {
  GuardianAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  // iOS用OAuthクライアントID (secrets/client_1097006569701-ptki1c15tcbentqsglt3ladgr7t9bdlq.apps.googleusercontent.com.plist)
  static const _googleIosClientId =
      '1097006569701-ptki1c15tcbentqsglt3ladgr7t9bdlq.apps.googleusercontent.com';
  // Web用OAuthクライアントID。Supabase側のGoogle Provider設定と同じ値(idTokenの検証対象)。
  static const _googleServerClientId =
      '1097006569701-9u5eclgh81akaok7c67ijtuhqvrrfvgl.apps.googleusercontent.com';

  bool _googleSignInInitialized = false;
  String? _googleRawNonce;

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

  /// ネイティブSign in with Appleでサインインし、発行されたidentityTokenをSupabaseへ引き渡す。
  /// nonceはリプレイ攻撃対策(Appleへの生の値のハッシュを渡し、Supabase側で生の値を検証させる)。
  Future<void> signInWithApple() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return;
      throw GuardianAuthException('Appleサインインに失敗しました');
    }

    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw GuardianAuthException('Appleサインインに失敗しました(トークンを取得できませんでした)');
    }

    try {
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: identityToken,
        nonce: rawNonce,
      );
    } on AuthApiException catch (e) {
      throw GuardianAuthException(_translate(e.message));
    }
  }

  /// GoogleSignInでサインインし、発行されたidTokenをSupabaseへ引き渡す。
  /// nonceの扱いはsignInWithAppleと同様(生の値のハッシュをGoogleへ渡し、Supabase側で生の値を検証させる)。
  /// GoogleSignIn.instance.initialize()はアプリ内で一度しか呼べないため、
  /// nonceは初回サインイン時に生成し、以降のサインインでも使い回す。
  Future<void> signInWithGoogle() async {
    if (!_googleSignInInitialized) {
      final rawNonce = _generateNonce();
      _googleRawNonce = rawNonce;
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
      await GoogleSignIn.instance.initialize(
        clientId: _googleIosClientId,
        serverClientId: _googleServerClientId,
        nonce: hashedNonce,
      );
      _googleSignInInitialized = true;
    }

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      throw GuardianAuthException('Googleサインインに失敗しました');
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw GuardianAuthException('Googleサインインに失敗しました(トークンを取得できませんでした)');
    }

    try {
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        nonce: _googleRawNonce,
      );
    } on AuthApiException catch (e) {
      throw GuardianAuthException(_translate(e.message));
    }
  }

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
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
