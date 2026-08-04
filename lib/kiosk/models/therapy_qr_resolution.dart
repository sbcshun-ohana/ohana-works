/// 療育QR読取(resolve-therapy-qr)の結果。accepted=false のときは message に理由が入る。
class TherapyQrResolution {
  const TherapyQrResolution({
    required this.accepted,
    this.eventType,
    this.childName,
    this.honorificSuffix,
    this.providerName,
    this.occurredAt,
    this.message,
  });

  factory TherapyQrResolution.fromJson(Map<String, dynamic> json) => TherapyQrResolution(
        accepted: json['accepted'] as bool? ?? false,
        eventType: json['event_type'] as String?,
        childName: json['child_name'] as String?,
        honorificSuffix: json['honorific_suffix'] as String?,
        providerName: json['provider_name'] as String?,
        occurredAt: json['occurred_at'] != null ? DateTime.parse(json['occurred_at'] as String) : null,
        message: json['message'] as String?,
      );

  final bool accepted;
  final String? eventType; // 'out' | 'return'
  final String? childName;
  final String? honorificSuffix;
  final String? providerName;
  final DateTime? occurredAt;
  final String? message;

  /// キオスク表示メッセージ(§3.3)。
  String get displayMessage {
    if (!accepted) return message ?? '処理できませんでした';
    final name = '${childName ?? ''}${honorificSuffix ?? ''}';
    final t = occurredAt?.toLocal();
    final hm = t != null
        ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
        : '';
    final action = eventType == 'out' ? '療育外出' : 'おかえりなさい';
    final provider = providerName != null ? '($providerName)' : '';
    return '$name $action $hm $provider';
  }
}
