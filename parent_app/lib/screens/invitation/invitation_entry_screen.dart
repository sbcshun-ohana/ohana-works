import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import 'invitation_qr_scan_screen.dart';

/// 招待コード受諾画面。ログイン済み(auth.uid()がある)ことが前提。
/// 園から口頭・メール等で伝えられた招待コードと氏名を入力し、
/// accept_guardian_invitation RPCで園児との紐付けを作成する。
class InvitationEntryScreen extends StatefulWidget {
  const InvitationEntryScreen({super.key, required this.guardianService, required this.onAccepted});

  final GuardianService guardianService;
  final VoidCallback onAccepted;

  @override
  State<InvitationEntryScreen> createState() => _InvitationEntryScreenState();
}

class _InvitationEntryScreenState extends State<InvitationEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _nameController = TextEditingController();
  final _nameKanaController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isBusy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _tokenController.dispose();
    _nameController.dispose();
    _nameKanaController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await widget.guardianService.acceptInvitation(
        token: _tokenController.text.trim(),
        name: _nameController.text.trim(),
        nameKana: _nameKanaController.text.trim().isEmpty ? null : _nameKanaController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        email: Supabase.instance.client.auth.currentUser?.email,
      );
      if (mounted) widget.onAccepted();
    } on GuardianServiceException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const InvitationQrScanScreen()),
    );
    if (code != null && mounted) {
      setState(() => _tokenController.text = code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('招待コードの入力'),
        actions: [
          IconButton(icon: const Icon(Icons.logout_rounded), tooltip: 'ログアウト', onPressed: _signOut),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '園から発行された招待コードと保護者様のお名前を入力してください',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _tokenController,
                  decoration: const InputDecoration(labelText: '招待コード'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '招待コードを入力してください' : null,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isBusy ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('QRを読み取る'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: '保護者氏名'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'お名前を入力してください' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameKanaController,
                  decoration: const InputDecoration(labelText: '保護者氏名(カナ・任意)'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '電話番号(任意)'),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
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
                      : const Text('登録する'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
