/// 園連絡帳(園→保護者、child_daily_contacts。承認済み行のみ保護者に公開される)。
/// 公開項目は本文・個別お知らせ・備品利用・午睡時間・排泄・食事・検温・入浴
/// (v0.4 §5.3 変更4)。管理者コメント等の職員内部項目は含まない。
class CommunicationBookEntry {
  const CommunicationBookEntry({
    required this.id,
    required this.childId,
    required this.businessDate,
    this.currentText,
    required this.napPeriods,
    required this.toiletingRecords,
    this.mealCompletionPct,
    this.mealFreeNote,
    this.temperature,
    this.temperatureMeasuredAt,
    this.bathTaken,
    this.noticeLabels = const [],
    this.supplyItems = const [],
  });

  factory CommunicationBookEntry.fromJson(Map<String, dynamic> json) => CommunicationBookEntry(
        id: json['id'] as String,
        childId: json['child_id'] as String,
        businessDate: DateTime.parse(json['business_date'] as String),
        currentText: json['current_text'] as String?,
        napPeriods: (json['nap_periods'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map((e) => NapPeriod(start: e['start'] as String? ?? '', end: e['end'] as String? ?? ''))
            .toList(),
        toiletingRecords: (json['toileting_records'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map((e) => ToiletingRecord(time: e['time'] as String? ?? '', type: e['type'] as String? ?? ''))
            .toList(),
        mealCompletionPct: json['meal_completion_pct'] as int?,
        mealFreeNote: json['meal_free_note'] as String?,
        temperature: json['temperature'] == null ? null : double.parse(json['temperature'].toString()),
        temperatureMeasuredAt: json['temperature_measured_at'] as String?,
        bathTaken: json['bath_taken'] as bool?,
      );

  final String id;
  final String childId;
  final DateTime businessDate;
  final String? currentText;
  final List<NapPeriod> napPeriods;
  final List<ToiletingRecord> toiletingRecords;
  final int? mealCompletionPct;
  final String? mealFreeNote;
  final double? temperature;
  final String? temperatureMeasuredAt;
  final bool? bathTaken;
  final List<String> noticeLabels;
  final List<SupplyItem> supplyItems;

  CommunicationBookEntry copyWith({List<String>? noticeLabels, List<SupplyItem>? supplyItems}) =>
      CommunicationBookEntry(
        id: id,
        childId: childId,
        businessDate: businessDate,
        currentText: currentText,
        napPeriods: napPeriods,
        toiletingRecords: toiletingRecords,
        mealCompletionPct: mealCompletionPct,
        mealFreeNote: mealFreeNote,
        temperature: temperature,
        temperatureMeasuredAt: temperatureMeasuredAt,
        bathTaken: bathTaken,
        noticeLabels: noticeLabels ?? this.noticeLabels,
        supplyItems: supplyItems ?? this.supplyItems,
      );
}

class NapPeriod {
  const NapPeriod({required this.start, required this.end});
  final String start;
  final String end;
}

class ToiletingRecord {
  const ToiletingRecord({required this.time, required this.type});
  final String time;
  final String type;
}

class SupplyItem {
  const SupplyItem({required this.itemName, required this.quantity});
  final String itemName;
  final int quantity;
}
