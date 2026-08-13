import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 現在の日付・時刻(分まで)をリアルタイム表示する時計。
/// 黒帯(SessionBanner)のログアウト横に常時表示する(俊指示: 秒は不要・分まで)。
class NowClock extends StatefulWidget {
  const NowClock({super.key, this.color});

  /// 文字色。未指定は textSecondary(明るい背景用)。黒帯では白を渡す。
  final Color? color;

  @override
  State<NowClock> createState() => _NowClockState();
}

class _NowClockState extends State<NowClock> {
  DateTime _now = DateTime.now();
  Timer? _timer;
  static const _wd = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _now;
    String two(int v) => v.toString().padLeft(2, '0');
    final text = '${n.year}/${two(n.month)}/${two(n.day)}(${_wd[n.weekday - 1]}) '
        '${two(n.hour)}:${two(n.minute)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: widget.color ?? AppColors.textSecondary)),
      ),
    );
  }
}
