export function formatTime(iso: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getMonth() + 1}/${d.getDate()} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function toDatetimeLocalValue(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function fromDatetimeLocalValue(value: string): string | null {
  if (!value) return null;
  return new Date(value).toISOString();
}

export function currentDate(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

export function currentYearMonth(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

export function monthRange(yearMonth: string): { start: string; end: string } {
  const [year, month] = yearMonth.split("-").map(Number);
  const start = `${yearMonth}-01`;
  const lastDay = new Date(year, month, 0).getDate();
  const end = `${yearMonth}-${String(lastDay).padStart(2, "0")}`;
  return { start, end };
}

const DAY_OF_WEEK_LABELS = ["日", "月", "火", "水", "木", "金", "土"];

export function dayOfWeekLabel(dateStr: string): string {
  // "YYYY-MM-DD"をローカルタイムゾーンのDateとして解釈する(UTC解釈によるずれを防ぐ)。
  const [year, month, day] = dateStr.split("-").map(Number);
  return DAY_OF_WEEK_LABELS[new Date(year, month - 1, day).getDay()];
}

export function formatClockTime(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

// PostgreSQLのtime型("HH:MM:SS")をHH:MM表記にする。
export function formatTimeOnly(time: string | null): string {
  if (!time) return "";
  return time.slice(0, 5);
}

export function diffMinutes(startIso: string | null, endIso: string | null): number | null {
  if (!startIso || !endIso) return null;
  const minutes = (new Date(endIso).getTime() - new Date(startIso).getTime()) / 60000;
  return minutes >= 0 ? Math.round(minutes) : null;
}

export function formatDurationMinutes(minutes: number | null): string {
  if (minutes === null || Number.isNaN(minutes)) return "";
  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  return `${hours}:${String(remainder).padStart(2, "0")}`;
}
