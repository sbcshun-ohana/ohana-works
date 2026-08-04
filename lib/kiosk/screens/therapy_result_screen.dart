import 'dart:async';

import 'package:flutter/material.dart';

import '../models/therapy_qr_resolution.dart';

/// 療育QR読取結果の確認表示(数秒で自動的に閉じてスキャンに戻る)。§3.3。
class TherapyResultScreen extends StatefulWidget {
  const TherapyResultScreen({super.key, required this.resolution});

  final TherapyQrResolution resolution;

  @override
  State<TherapyResultScreen> createState() => _TherapyResultScreenState();
}

class _TherapyResultScreenState extends State<TherapyResultScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.resolution;
    final Color bg;
    final IconData icon;
    if (!r.accepted) {
      bg = const Color(0xFFE0645F);
      icon = Icons.error_outline_rounded;
    } else if (r.eventType == 'out') {
      bg = const Color(0xFF7A5FC0);
      icon = Icons.directions_walk_rounded;
    } else {
      bg = const Color(0xFF4CAF7D);
      icon = Icons.home_rounded;
    }
    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 96, color: Colors.white),
                const SizedBox(height: 24),
                Text(
                  r.displayMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 32),
                const Text('画面をタッチすると戻ります', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
