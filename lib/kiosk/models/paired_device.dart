/// 9.1 端末マスタとのペアリング結果(端末ローカルに保存する)。
class PairedDevice {
  const PairedDevice({
    required this.deviceId,
    required this.officeId,
    required this.officeName,
  });

  final String deviceId;
  final String officeId;
  final String? officeName;
}
