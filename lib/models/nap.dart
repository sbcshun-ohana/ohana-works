/// 午睡チェック(Phase 3)のモデル群。バックエンドは migration 168〜170。
library;

/// 身体の向き(§3.2)。正式名(入力シート・凡例で使用)。
const napBodyPositions = <String, String>{
  'right': '右',
  'left': '左',
  'supine': '仰向け',
  'prone_corrected': 'うつ伏せ直し',
};

/// グリッドセル内の短縮表記。セル幅を記録内容に依らず固定にするため、
/// 長い「うつ伏せ直し」は「伏直」に略す(正式名はタップ時のシート・凡例で表示)。
const napBodyPositionsShort = <String, String>{
  'right': '右',
  'left': '左',
  'supine': '仰向',
  'prone_corrected': '伏直',
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

/// 午睡区間(nap_intervals)。1セッションに複数(複数回午睡)。
class NapInterval {
  const NapInterval({required this.seq, required this.sleepStartAt, this.wakeUpAt});

  factory NapInterval.fromJson(Map<String, dynamic> json) => NapInterval(
        seq: json['seq'] as int,
        sleepStartAt: DateTime.parse(json['sleep_start_at'] as String),
        wakeUpAt: json['wake_up_at'] != null ? DateTime.parse(json['wake_up_at'] as String) : null,
      );

  final int seq;
  final DateTime sleepStartAt;
  final DateTime? wakeUpAt;
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
    required this.intervals,
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
        intervals: ((json['intervals'] as List?) ?? const [])
            .map((e) => NapInterval.fromJson(e as Map<String, dynamic>))
            .toList(),
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
  final List<NapInterval> intervals;
  final List<NapCheck> checks;

  String get nameLabel => '$displayName${honorificSuffix ?? ''}';

  /// 起床済み(未起床の区間が無い=再入眠できる状態)。区間が1つ以上あり全て閉じている。
  bool get isAllWoken => intervals.isNotEmpty && intervals.every((i) => i.wakeUpAt != null);

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
