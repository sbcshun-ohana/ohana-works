/// キオスク(玄関設置・他の保護者の目に触れる)の療育QR表示文言。
///
/// プライバシー方針(俊承認 2026-08-12): キオスク画面には「療育」の語・事業所名・
/// 拒否理由を一切出さない。療育利用は機微情報のため、外部に利用の事実や理由が
/// 推測される手がかりを残さない。園児名+時刻のみ表示する。
/// ※データ・職員用画面(デイリーボードのバッジ/療育記録一覧/CSV/PDF)は不変。
class TherapyKioskStrings {
  TherapyKioskStrings._();

  /// 外出(out)成功。「◯◯ちゃん 外出 HH:MM」
  static const String outAction = '外出';

  /// 戻り(return)成功。「◯◯ちゃん おかえりなさい HH:MM」
  static const String returnAction = 'おかえりなさい';

  /// 拒否時の統一文言。reason の値(既知5種・将来の未知reasonを含む)に関わらず、
  /// 常にこれを表示する。生のサーバメッセージ(reason別message)を画面に出さない。
  static const String rejected = 'このQRは現在ご利用いただけません。職員にお声がけください';
}
