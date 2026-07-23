import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 園児を選択した後の画面共通のAppBarタイトル。本文(例:「○○ちゃんの家庭連絡帳」)の下に
/// 所属施設名を小さく表示し、複数施設に通う園児がいても迷わないようにする。
class ChildContextAppBarTitle extends StatelessWidget {
  const ChildContextAppBarTitle({super.key, required this.title, this.officeName});

  final String title;
  final String? officeName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, overflow: TextOverflow.ellipsis),
        if (officeName != null)
          Text(
            officeName!,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
