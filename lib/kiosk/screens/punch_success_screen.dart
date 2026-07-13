import 'dart:async';

import 'package:flutter/material.dart';

import '../models/punch_resolution.dart';
import '../punch_type_display.dart';

const _autoReturnDelay = Duration(seconds: 3);

/// 10章: 完了後「出勤しました」等を大きく表示し、数秒後にスキャン画面へ自動で戻る。
class PunchSuccessScreen extends StatefulWidget {
  const PunchSuccessScreen({super.key, required this.result});

  final PunchResult result;

  @override
  State<PunchSuccessScreen> createState() => _PunchSuccessScreenState();
}

class _PunchSuccessScreenState extends State<PunchSuccessScreen> {
  @override
  void initState() {
    super.initState();
    Timer(_autoReturnDelay, () {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final display = PunchTypeDisplay.of(widget.result.punchType);
    return Scaffold(
      backgroundColor: display.color,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(display.icon, size: 96, color: Colors.white),
            const SizedBox(height: 24),
            Text(
              widget.result.employeeName,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.result.message,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
