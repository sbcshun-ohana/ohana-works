/// 午睡チェック(Phase 3)のモデル群。バックエンドは migration 168〜170。
library;

/// 身体の向き(§3.2)。
const napBodyPositions = <String, String>{
  'right': '右',
  'left': '左',
  'supine': '仰向け',
  'prone_corrected': 'うつ伏せ直し',
};

class NapCheck {
  const NapCheck({
    required this.slotAt,
    required this.bodyPosition,
    required this.breathing,
    required this.complexion,
    required this.bedding,
    required this.source,
  });

  factory NapCheck.fromJson(Map<String, dynamic> json) => NapCheck(
        slotAt: DateTime.parse(json['slot_at'] as String),
        bodyPosition: json['body_position'] as String,
        breathing: json['breathing'] as bool? ?? false,
        complexion: json['complexion'] as bool? ?? false,
        bedding: json['bedding'] as bool? ?? false,
        source: json['source'] as String? ?? 'realtime',
      );

  final DateTime slotAt;
  final String bodyPosition;
  final bool breathing;
  final bool complexion;
  final bool bedding;
  final String source;
}

class NapSessionRow {
  const NapSessionRow({
    required this.sessionId,
    required this.childId,
    required this.displayName,
    this.honorificSuffix,
    required this.classId,
    required this.className,
    required this.isRequired,
    this.sleepStartAt,
    this.wakeUpAt,
    required this.checks,
  });

  factory NapSessionRow.fromJson(Map<String, dynamic> json) => NapSessionRow(
        sessionId: json['session_id'] as String,
        childId: json['child_id'] as String,
        displayName: json['display_name'] as String,
        honorificSuffix: json['honorific_suffix'] as String?,
        classId: json['class_id'] as String,
        className: json['class_name'] as String,
        isRequired: json['is_required'] as bool? ?? false,
        sleepStartAt:
            json['sleep_start_at'] != null ? DateTime.parse(json['sleep_start_at'] as String) : null,
        wakeUpAt: json['wake_up_at'] != null ? DateTime.parse(json['wake_up_at'] as String) : null,
        checks: ((json['checks'] as List?) ?? const [])
            .map((e) => NapCheck.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String sessionId;
  final String childId;
  final String displayName;
  final String? honorificSuffix;
  final String classId;
  final String className;
  final bool isRequired;
  final DateTime? sleepStartAt;
  final DateTime? wakeUpAt;
  final List<NapCheck> checks;

  String get nameLabel => '$displayName${honorificSuffix ?? ''}';

  NapCheck? checkAt(DateTime slot) {
    for (final c in checks) {
      if (c.slotAt.isAtSameMomentAs(slot)) return c;
    }
    return null;
  }
}

class NapMissing {
  const NapMissing({
    required this.sessionId,
    required this.childId,
    required this.displayName,
    required this.className,
    required this.missingCount,
  });

  factory NapMissing.fromJson(Map<String, dynamic> json) => NapMissing(
        sessionId: json['session_id'] as String,
        childId: json['child_id'] as String,
        displayName: json['display_name'] as String,
        className: json['class_name'] as String,
        missingCount: json['missing_count'] as int? ?? 0,
      );

  final String sessionId;
  final String childId;
  final String displayName;
  final String className;
  final int missingCount;
}
