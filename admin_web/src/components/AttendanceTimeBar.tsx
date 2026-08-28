"use client";

// 登降園タイムバー(K6・コドモン準拠)。
// 予定(薄青: scheduled_start→end)の上に実績(濃青: arrival→departure)を重ね、
// 日中の外出(out→return)は紫セグメントで表現(俊指示 2026-08-28: iPad と同じ
// 青→外出で紫→戻りで青。旧仕様の白抜きは色抜けに見えるため廃止)。
// 両端に実績(無ければ予定)の時刻を表示。
// 時刻はすべて JST(Asia/Tokyo)基準。timestamptz は JST の壁時計へ、time文字列はそのまま。

const DAY_START_MIN = 7 * 60; // 07:00
const DAY_END_MIN = 19 * 60; // 19:00
const DAY_SPAN = DAY_END_MIN - DAY_START_MIN;

// timestamptz(ISO)を JST の分(0-1439)へ。null は null。
function tzToJstMinutes(iso: string | null): number | null {
  if (!iso) return null;
  const hm = new Date(iso).toLocaleTimeString("en-GB", {
    timeZone: "Asia/Tokyo",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const [h, m] = hm.split(":").map(Number);
  return h * 60 + m;
}

// "HH:MM[:SS]" の time 文字列を分へ。
function timeToMinutes(t: string | null): number | null {
  if (!t) return null;
  const [h, m] = t.split(":").map(Number);
  return h * 60 + m;
}

// 分(JST)→ "HH:MM" 表示。
function fmt(min: number | null): string {
  if (min == null) return "";
  const h = Math.floor(min / 60);
  const m = min % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

// 分を日窓(07:00-19:00)内の 0-100% へクランプ。
function pct(min: number): number {
  const clamped = Math.min(Math.max(min, DAY_START_MIN), DAY_END_MIN);
  return ((clamped - DAY_START_MIN) / DAY_SPAN) * 100;
}

export type AttendanceTimeBarProps = {
  arrivalAt: string | null;
  departureAt: string | null;
  outAt: string | null;
  returnAt: string | null;
  scheduledStartAt: string | null; // "HH:MM:SS"
  scheduledEndAt: string | null;
};

export function AttendanceTimeBar({
  arrivalAt,
  departureAt,
  outAt,
  returnAt,
  scheduledStartAt,
  scheduledEndAt,
}: AttendanceTimeBarProps) {
  const schedStart = timeToMinutes(scheduledStartAt);
  const schedEnd = timeToMinutes(scheduledEndAt);
  const arr = tzToJstMinutes(arrivalAt);
  const dep = tzToJstMinutes(departureAt);
  const out = tzToJstMinutes(outAt);
  const ret = tzToJstMinutes(returnAt);

  const hasSchedule = schedStart != null && schedEnd != null && schedEnd > schedStart;
  const hasActual = arr != null; // 登園していれば実績あり(降園前は現在進行)

  if (!hasSchedule && !hasActual) {
    return <span className="text-xs text-slate-300">—</span>;
  }

  // 実績の右端: 降園済みなら departure、未降園(進行中)なら現在時刻(JST)まで伸ばす
  // (俊確定: K6再設計。日窓右端19:00で固定せず「今どこまで在園中か」を絶対軸で示す)。19:00でクランプ。
  const nowMin = tzToJstMinutes(new Date().toISOString()) ?? DAY_END_MIN;
  const actualEnd = dep ?? Math.min(nowMin, DAY_END_MIN);

  // 外出(out→戻り)の紫区間。戻り未登録なら実績右端(=現在)まで外出中。
  const gapStart = out;
  const gapEnd = out != null ? (ret ?? actualEnd) : null;
  const outNow = out != null && ret == null && dep == null; // 外出中(戻り・降園なし)

  return (
    <div className="flex items-center gap-2">
      <span className="w-9 shrink-0 text-right text-[10px] tabular-nums text-slate-500">
        {fmt(arr ?? schedStart)}
      </span>
      <div className="relative h-3 w-32 shrink-0 rounded-full bg-slate-100">
        {/* 予定(薄青) */}
        {hasSchedule && (
          <div
            className="absolute top-0 h-3 rounded-full bg-sky-200"
            style={{ left: `${pct(schedStart!)}%`, width: `${pct(schedEnd!) - pct(schedStart!)}%` }}
          />
        )}
        {/* 実績(濃青) */}
        {hasActual && (
          <div
            className="absolute top-0 h-3 rounded-full bg-sky-600"
            style={{ left: `${pct(arr!)}%`, width: `${Math.max(pct(actualEnd) - pct(arr!), 1)}%` }}
          />
        )}
        {/* 外出(紫・iPadの #7A5FC0 と同色)。外出中は現在時刻まで紫が伸びる */}
        {gapStart != null && gapEnd != null && gapEnd > gapStart && (
          <div
            className="absolute top-0 h-3"
            style={{ left: `${pct(gapStart)}%`, width: `${pct(gapEnd) - pct(gapStart)}%`, backgroundColor: "#7A5FC0" }}
            title={outNow ? `外出中 ${fmt(gapStart)}〜` : `外出 ${fmt(gapStart)}〜${fmt(ret)}`}
          />
        )}
      </div>
      <span className="w-9 shrink-0 text-left text-[10px] tabular-nums text-slate-500">
        {fmt(dep ?? schedEnd)}
      </span>
    </div>
  );
}
