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
      // AppBar leading は leadingWidth(各画面 148 等)で幅が制限されるため、内容がわずかに
      // はみ出すと全画面で横方向のオーバーフロー縞が出る(Y3)。FittedBox(scaleDown)で
      // 与えられた幅に必ず収める(不足時のみ縮小、通常は原寸)。
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.spa_rounded, size: 20, color: AppColors.leafGreen),
            SizedBox(width: 6),
            Text(
              'Ohana Works',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下層画面(Navigator.push で開かれた2階層以上深い画面)の AppBar leading。
/// 「戻る矢印(1つ前へ)」＋「Ohana Works ロゴ(ホームへ)」を併設する。
/// OhanaLogoHomeButton 単体だと popUntil でホームまで戻ってしまい、1つ前へ戻れず
/// 袋小路になるため、下層画面ではこちらを使う(leadingWidth は 200 目安)。
class OhanaBackHomeLeading extends StatelessWidget {
  const OhanaBackHomeLeading({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
          tooltip: '戻る',
          color: AppColors.textPrimary,
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const Flexible(child: OhanaLogoHomeButton()),
      ],
    );
  }
}
