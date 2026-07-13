import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../models/paired_device.dart';
import '../models/punch_resolution.dart';
import '../punch_type_display.dart';
import '../services/kiosk_punch_service.dart';
import 'punch_success_screen.dart';

const _inactivityTimeout = Duration(seconds: 15);

/// 10章: 自動判定 → 確認画面 → 職員がタップ → 打刻確定。
class PunchConfirmScreen extends StatefulWidget {
  const PunchConfirmScreen({
    super.key,
    required this.resolution,
    required this.device,
    required this.punchService,
  });

  final PunchResolution resolution;
  final PairedDevice device;
  final KioskPunchService punchService;

  @override
  State<PunchConfirmScreen> createState() => _PunchConfirmScreenState();
}

class _PunchConfirmScreenState extends State<PunchConfirmScreen> {
  bool _isSubmitting = false;
  String? _errorMessage;
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _select(String punchType) async {
    _inactivityTimer?.cancel();

    if (punchType == 'mistake') {
      // トークンは既に消費済みのため、再スキャンしてもらうだけでよい(サーバー呼び出し不要)。
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.punchService.confirmPunch(
        confirmationToken: widget.resolution.confirmationToken,
        punchType: punchType,
        deviceId: widget.device.deviceId,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(builder: (_) => PunchSuccessScreen(result: result)),
      );
    } on KioskPunchException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isSubmitting = false;
      });
      _resetInactivityTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.resolution.employeeName,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '打刻内容を選んでください',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_isSubmitting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(),
                    )
                  else
                    Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      alignment: WrapAlignment.center,
                      children: widget.resolution.candidates
                          .map(_buildCandidateButton)
                          .toList(),
                    ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('キャンセル'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateButton(String punchType) {
    final display = PunchTypeDisplay.of(punchType);
    return SizedBox(
      width: 200,
      height: 140,
      child: ElevatedButton(
        onPressed: () {
          _resetInactivityTimer();
          _select(punchType);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: display.color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(display.icon, size: 40),
            const SizedBox(height: 12),
            Text(
              display.label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
