/// 保護者向け一斉配信お知らせ(guardian_notices)。園児横断で時系列表示する。
/// 宛先は保護者自身の recipient 行から導出: child_id=null→園全体 / 非null→園児(名+クラス)。
/// 兄弟児で同一お知らせが複数園児に届く場合も 1通=1行に集約し、園児バッジを複数持つ。
class GuardianBroadcastNotice {
  const GuardianBroadcastNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.sentAt,
    required this.isRead,
    required this.isWholeSchool,
    required this.childIds,
  });

  final String id;
  final String title;
  final String body;
  final DateTime sentAt;
  final bool isRead;

  /// office/all 宛て(recipient.child_id=null)を含む=「園全体」バッジを出す。
  final bool isWholeSchool;

  /// class/child 宛ての対象園児id(重複なし)。バッジ解決は画面側で linkedChildren を用いる。
  final List<String> childIds;
}
