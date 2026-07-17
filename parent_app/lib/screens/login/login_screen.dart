import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// メール+パスワードでのログイン・新規登録。
/// Sign in with Apple / Googleは、Apple Developer・Google Cloud側のOAuth設定完了後に追加する
/// (v0.4 §7 Phase A確認事項1。現時点では未設定のためボタンは表示しない)。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUpMode = false;
  bool _isBusy = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      if (_isSignUpMode) {
        await widget.authService.signUpWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) {
          setState(() {
            _infoMessage = '確認メールを送信しました。メール内のリンクからアカウントを有効化してください';
          });
        }
      } else {
        await widget.authService.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on GuardianAuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.family_restroom_rounded, size: 64, color: AppColors.skyBlue),
                  const SizedBox(height: 16),
                  const Text(
                    'Ohana Works\nfor Family',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'メールアドレス'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'メールアドレスを入力してください' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'パスワード'),
                    validator: (v) => (v == null || v.length < 6) ? '6文字以上で入力してください' : null,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(_errorMessage!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
                  ],
                  if (_infoMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(_infoMessage!, style: const TextStyle(color: AppColors.leafGreen), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isBusy ? null : _submit,
                    child: _isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isSignUpMode ? '新規登録' : 'ログイン'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isBusy
                        ? null
                        : () => setState(() {
                              _isSignUpMode = !_isSignUpMode;
                              _errorMessage = null;
                              _infoMessage = null;
                            }),
                    child: Text(_isSignUpMode ? 'ログインはこちら' : '初めての方はこちら(新規登録)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
