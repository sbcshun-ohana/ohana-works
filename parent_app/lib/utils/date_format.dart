const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// "2026年7月23日(木)"形式の日本語日付表記。
String formatJapaneseDate(DateTime date, {bool withWeekday = true}) {
  final base = '${date.year}年${date.month}月${date.day}日';
  if (!withWeekday) return base;
  return '$base(${_weekdayLabels[date.weekday - 1]})';
}
