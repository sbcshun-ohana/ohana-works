// 3章: 業務日付判定はAsia/Tokyo固定

export function tokyoDayBounds(
  now: Date = new Date(),
): { dateStr: string; startUtc: Date; endUtc: Date } {
  const dateStr = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tokyo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
  const startUtc = new Date(`${dateStr}T00:00:00+09:00`);
  const endUtc = new Date(startUtc.getTime() + 24 * 60 * 60 * 1000);
  return { dateStr, startUtc, endUtc };
}
