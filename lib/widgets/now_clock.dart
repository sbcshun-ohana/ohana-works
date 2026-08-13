import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 画面端(AppBar・上部コントロール行)に現在の日付・時刻をリアルタイム表示する時計(1秒更新)。
/// デイリーボードで導入したものを共通化(連絡帳/クラス活動/午睡/健康チェック等でも表示)。
class NowClock extends StatefulWidget {
  const NowClock({super.key});

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
        '${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      ),
    );
  }
}
