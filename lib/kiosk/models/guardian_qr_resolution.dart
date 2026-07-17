/// 保護者QR読取(resolve-guardian-qr)の結果。
class GuardianQrResolution {
  const GuardianQrResolution({
    required this.accepted,
    this.eventType,
    this.childName,
    this.honorificSuffix,
    this.reason,
    this.message,
  });

  factory GuardianQrResolution.fromJson(Map<String, dynamic> json) {
    return GuardianQrResolution(
      accepted: json['accepted'] as bool,
      eventType: json['event_type'] as String?,
      childName: json['child_name'] as String?,
      honorificSuffix: json['honorific_suffix'] as String?,
      reason: json['reason'] as String?,
      message: json['message'] as String?,
    );
  }

  final bool accepted;
  final String? eventType;
  final String? childName;
  final String? honorificSuffix;
  final String? reason;
  final String? message;

  String get nameLabel => '${childName ?? ''}${honorificSuffix ?? ''}';
}
