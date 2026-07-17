import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../models/guardian_qr_resolution.dart';

const _autoReturnDelayAccepted = Duration(seconds: 3);
const _autoReturnDelayRejected = Duration(seconds: 6);

/// 保護者QR読取の結果表示(登園/降園、または拒否理由)。
/// 拒否時(家庭連絡帳未提出等)は保護者アプリへの入力導線をその場で促すメッセージを表示する。
class GuardianCheckInResultScreen extends StatefulWidget {
  const GuardianCheckInResultScreen({super.key, required this.resolution});

  final GuardianQrResolution resolution;

  @override
  State<GuardianCheckInResultScreen> createState() => _GuardianCheckInResultScreenState();
}

class _GuardianCheckInResultScreenState extends State<GuardianCheckInResultScreen> {
  @override
  void initState() {
    super.initState();
    final delay = widget.resolution.accepted ? _autoReturnDelayAccepted : _autoReturnDelayRejected;
    Timer(delay, () {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolution = widget.resolution;
    final isPickUp = resolution.eventType == 'pick_up';
    final backgroundColor = !resolution.accepted
        ? AppColors.punchWarning
        : (isPickUp ? AppColors.punchClockOut : AppColors.punchClockIn);
    final icon = !resolution.accepted
        ? Icons.warning_amber_rounded
        : (isPickUp ? Icons.logout_rounded : Icons.login_rounded);
    final headline = !resolution.accepted
        ? '受付できません'
        : (isPickUp ? '降園しました' : '登園しました');

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 96, color: Colors.white),
              const SizedBox(height: 24),
              if (resolution.nameLabel.isNotEmpty)
                Text(
                  resolution.nameLabel,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              if (resolution.message != null) ...[
                const SizedBox(height: 16),
                Text(
                  resolution.message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
