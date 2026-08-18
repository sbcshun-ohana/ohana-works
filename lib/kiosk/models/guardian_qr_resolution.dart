/// 兄弟一括登降園(234)の候補1件。
class FamilyCheckinCandidate {
  const FamilyCheckinCandidate({
    required this.childId,
    required this.childName,
    this.className,
    required this.todayStatus,
    required this.isAbsentToday,
    required this.defaultSelected,
    this.note,
  });

  factory FamilyCheckinCandidate.fromJson(Map<String, dynamic> json) {
    return FamilyCheckinCandidate(
      childId: json['child_id'] as String,
      childName: json['child_name'] as String,
      className: json['class_name'] as String?,
      todayStatus: json['today_status'] as String? ?? 'not_arrived',
      isAbsentToday: json['is_absent_today'] as bool? ?? false,
      defaultSelected: json['default_selected'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }

  final String childId;
  final String childName;
  final String? className;
  final String todayStatus; // not_arrived / present / picked_up / absent
  final bool isAbsentToday;
  final bool defaultSelected;
  final String? note;
}

/// 保護者QR読取(resolve-guardian-qr)の結果。
/// mode='family' のときは兄弟一括登降園の確認画面へ分岐する(session/candidates を持つ)。
class GuardianQrResolution {
  const GuardianQrResolution({
    required this.accepted,
    this.eventType,
    this.childName,
    this.honorificSuffix,
    this.reason,
    this.message,
    this.mode,
    this.sessionId,
    this.direction,
    this.candidates = const [],
  });

  factory GuardianQrResolution.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'] as String?;
    if (mode == 'family') {
      return GuardianQrResolution(
        accepted: false,
        mode: 'family',
        sessionId: json['session_id'] as String?,
        direction: json['direction'] as String?,
        candidates: ((json['candidates'] as List?) ?? const [])
            .map((e) => FamilyCheckinCandidate.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }
    return GuardianQrResolution(
      accepted: json['accepted'] as bool? ?? false,
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

  final String? mode; // 'family' のとき兄弟一括
  final String? sessionId;
  final String? direction; // 'arrival' / 'departure'
  final List<FamilyCheckinCandidate> candidates;

  bool get isFamily => mode == 'family';
  String get nameLabel => '${childName ?? ''}${honorificSuffix ?? ''}';
}
