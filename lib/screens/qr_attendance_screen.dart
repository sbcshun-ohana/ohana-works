import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/qr_token.dart';
import '../services/qr_attendance_service.dart';
import '../theme/app_theme.dart';

/// 9.2 職員が打刻用に提示するワンタイムQR。
/// 8時間有効・single-use消費で、使用されると自動的に新しいQRを取得・表示する。
class QrAttendanceScreen extends StatefulWidget {
  const QrAttendanceScreen({super.key});

  @override
  State<QrAttendanceScreen> createState() => _QrAttendanceScreenState();
}

class _QrAttendanceScreenState extends State<QrAttendanceScreen> {
  final _service = QrAttendanceService(Supabase.instance.client);

  QrToken? _token;
  String? _errorMessage;
  bool _isLoading = true;
  RealtimeChannel? _channel;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _init();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _init() async {
    await _refreshToken();
    final employeeId = await _service.fetchOwnEmployeeId();
    if (employeeId != null && mounted) {
      _channel = _service.watchTokenUsage(
        employeeId: employeeId,
        onTokenUsed: _refreshToken,
      );
    }
  }

  Future<void> _refreshToken() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final token = await _service.issueToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _isLoading = false;
      });
    } on QrAttendanceException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    }
  }

  String _formatRemaining(Duration d) {
    if (d.isNegative) return '期限切れ';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    return '有効期限まで あと$hours時間$minutes分';
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    final isExpired = token?.isExpired ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('勤怠QR')),
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
                    'iPadにQRをかざしてください',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: _buildQrArea(token, isExpired),
                  ),
                  const SizedBox(height: 20),
                  if (token != null && !_isLoading && _errorMessage == null)
                    Text(
                      isExpired ? '期限切れです。更新してください' : _formatRemaining(token.remaining),
                      style: TextStyle(
                        color: isExpired
                            ? Colors.redAccent
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _refreshToken,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('QRを更新'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrArea(QrToken? token, bool isExpired) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (token == null || _errorMessage != null) {
      return const Center(
        child: Icon(
          Icons.qr_code_2_rounded,
          size: 96,
          color: AppColors.textSecondary,
        ),
      );
    }
    return Opacity(
      opacity: isExpired ? 0.3 : 1,
      child: QrImageView(
        data: token.token,
        version: QrVersions.auto,
        size: 260,
        backgroundColor: Colors.white,
      ),
    );
  }
}
