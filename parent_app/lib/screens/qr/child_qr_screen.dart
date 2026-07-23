import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/guardian_qr_token.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/child_context_app_bar_title.dart';

/// 登降園用の動的QR(90秒有効)。期限が近づくと自動更新し、
/// 施設側のiPadで読み取られる(消費される)とリアルタイムに検知して即座に再発行する。
class ChildQrScreen extends StatefulWidget {
  const ChildQrScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<ChildQrScreen> createState() => _ChildQrScreenState();
}

class _ChildQrScreenState extends State<ChildQrScreen> {
  GuardianQrToken? _token;
  String? _errorMessage;
  bool _isLoading = true;
  RealtimeChannel? _channel;
  Timer? _autoRefreshTimer;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _channel = widget.guardianService.watchQrTokenUsage(
      childId: widget.child.childId,
      onTokenUsed: _refreshToken,
    );
    _refreshToken();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _autoRefreshTimer?.cancel();
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _refreshToken() async {
    _autoRefreshTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = await widget.guardianService.issueChildQrToken(widget.child.childId);
      if (!mounted) return;
      setState(() {
        _token = token;
        _isLoading = false;
      });
      final untilRefresh = token.remaining - const Duration(seconds: 10);
      _autoRefreshTimer = Timer(untilRefresh.isNegative ? Duration.zero : untilRefresh, _refreshToken);
    } on GuardianServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    final isExpired = token?.isExpired ?? false;

    return Scaffold(
      appBar: AppBar(
        title: ChildContextAppBarTitle(title: '${widget.child.nameLabel}のQR', officeName: widget.child.officeName),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '施設のiPadにQRをかざしてください',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '現在の状態: ${childStatusLabel(widget.child.todayStatus)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(width: 240, height: 240, child: _buildQrArea(token, isExpired)),
                  const SizedBox(height: 16),
                  if (token != null && !_isLoading && _errorMessage == null)
                    Text(
                      isExpired ? '更新中です…' : '残り${token.remaining.inSeconds}秒で自動更新',
                      style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _refreshToken,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('今すぐ更新'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrArea(GuardianQrToken? token, bool isExpired) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (token == null || _errorMessage != null) {
      return const Center(child: Icon(Icons.qr_code_2_rounded, size: 88, color: AppColors.textSecondary));
    }
    return Opacity(
      opacity: isExpired ? 0.3 : 1,
      child: QrImageView(data: token.token, version: QrVersions.auto, size: 240, backgroundColor: Colors.white),
    );
  }
}
