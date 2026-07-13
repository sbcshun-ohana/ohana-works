/// 端末のローカル時刻(=設置施設の現地時刻)基準で "HH:mm" 表示に整形する。
String formatClockTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
