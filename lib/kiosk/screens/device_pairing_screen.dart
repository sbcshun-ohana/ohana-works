import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../models/paired_device.dart';
import '../services/device_pairing_service.dart';

/// 9.1章: 端末マスタとのペアリング(初回セットアップ)。
class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({
    super.key,
    required this.pairingService,
    required this.onPaired,
  });

  final DevicePairingService pairingService;
  final void Function(PairedDevice device) onPaired;

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final device = await widget.pairingService.pairDevice(code);
      if (!mounted) return;
      widget.onPaired(device);
    } on DevicePairingException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.tablet_mac_rounded,
                        size: 56,
                        color: AppColors.skyBlue,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '端末登録',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'この端末の端末コードを入力してください',
                        style: TextStyle(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20),
                        decoration: const InputDecoration(
                          labelText: '端末コード',
                          prefixIcon: Icon(Icons.qr_code_rounded),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('登録する'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
