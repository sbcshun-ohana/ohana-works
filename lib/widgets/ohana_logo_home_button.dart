import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 全画面共通: 左上に配置する「Ohana Works」ロゴ兼ホームボタン。
/// タップでルート(ホーム/メニュー)まで戻る(どの画面からでもワンタップでホームへ)。
/// ※ 画像ロゴアセットが未整備のため現状はテキストロゴ。アセット導入時はここだけ差し替える。
class OhanaLogoHomeButton extends StatelessWidget {
  const OhanaLogoHomeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundColor: AppColors.skyBlue,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.spa_rounded, size: 20, color: AppColors.leafGreen),
          SizedBox(width: 6),
          Text(
            'Ohana Works',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
