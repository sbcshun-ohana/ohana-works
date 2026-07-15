import ExcelJS from "exceljs";
import { createClient } from "@/lib/supabase/client";
import {
  dayOfWeekLabel,
  diffMinutes,
  formatClockTime,
  formatDurationMinutes,
  formatTimeOnly,
  monthRange,
} from "@/lib/datetime";
import { shiftTypeLabel } from "@/lib/export/shiftTypeLabels";
import type { AttendanceExportRow } from "@/lib/types";

const COLUMNS = [
  { header: "日付", width: 12 },
  { header: "曜日", width: 6 },
  { header: "シフト開始", width: 10 },
  { header: "シフト終了", width: 10 },
  { header: "実出勤時刻", width: 10 },
  { header: "承認済み出勤時刻", width: 14 },
  { header: "実退勤時刻", width: 10 },
  { header: "承認済み退勤時刻", width: 14 },
  { header: "休憩開始", width: 10 },
  { header: "休憩終了", width: 10 },
  { header: "実休憩時間", width: 10 },
  { header: "承認済み休憩時間(分)", width: 16 },
  { header: "実労働時間", width: 10 },
  { header: "給与計算対象時間", width: 14 },
  { header: "有給", width: 6 },
  { header: "欠勤", width: 6 },
  { header: "遅刻", width: 6 },
  { header: "早退", width: 6 },
  { header: "時間外", width: 10 },
  { header: "勤務区分", width: 16 },
  { header: "アラート", width: 20 },
  { header: "備考", width: 20 },
];

// 8時間(法定の日次時間外基準)。シフトが未登録の日はこの値を暫定所定時間として扱う
// (11.6の簡易近似。正式な時間外はattendance_summariesを正とする)。
const DEFAULT_DAILY_PRESCRIBED_MINUTES = 480;

function shiftPrescribedMinutes(
  startTime: string | null,
  endTime: string | null,
  breakMinutes: number | null,
): number | null {
  if (!startTime || !endTime) return null;
  const toMinutes = (t: string) => {
    const [h, m] = t.split(":").map(Number);
    return h * 60 + m;
  };
  const start = toMinutes(startTime);
  let end = toMinutes(endTime);
  if (end < start) end += 24 * 60;
  return end - start - (breakMinutes ?? 0);
}

function sanitizeSheetName(name: string): string {
  // Excelシート名の禁止文字(: \ / ? * [ ])を除去し、31文字に切り詰める。
  const cleaned = name.replace(/[:\\/?*[\]]/g, "");
  return cleaned.slice(0, 31) || "sheet";
}

function buildRow(row: AttendanceExportRow): (string | number)[] {
  const actualBreakMinutes = diffMinutes(row.actual_break_start_at, row.actual_break_end_at);
  const actualWorkedMinutesRaw = diffMinutes(row.actual_clock_in_at, row.actual_clock_out_at);
  const actualWorkedMinutes =
    actualWorkedMinutesRaw === null ? null : actualWorkedMinutesRaw - (actualBreakMinutes ?? 0);

  const payrollMinutesRaw = diffMinutes(row.approved_work_start_at, row.approved_work_end_at);
  const payrollMinutes =
    payrollMinutesRaw === null ? null : payrollMinutesRaw - (row.approved_break_minutes ?? 0);

  const isSunday = dayOfWeekLabel(row.work_date) === "日";
  const prescribed =
    shiftPrescribedMinutes(row.shift_start_time, row.shift_end_time, row.shift_break_minutes) ??
    DEFAULT_DAILY_PRESCRIBED_MINUTES;
  const overtimeMinutes =
    payrollMinutes === null || isSunday
      ? null
      : Math.max(payrollMinutes - Math.max(prescribed, DEFAULT_DAILY_PRESCRIBED_MINUTES), 0);

  return [
    row.work_date,
    dayOfWeekLabel(row.work_date),
    formatTimeOnly(row.shift_start_time),
    formatTimeOnly(row.shift_end_time),
    formatClockTime(row.actual_clock_in_at),
    formatClockTime(row.approved_work_start_at),
    formatClockTime(row.actual_clock_out_at),
    formatClockTime(row.approved_work_end_at),
    formatClockTime(row.actual_break_start_at),
    formatClockTime(row.actual_break_end_at),
    formatDurationMinutes(actualBreakMinutes),
    row.approved_break_minutes ?? "",
    formatDurationMinutes(actualWorkedMinutes),
    formatDurationMinutes(payrollMinutes),
    row.has_paid_leave ? "○" : "",
    row.has_absence ? "○" : "",
    row.has_tardiness ? "○" : "",
    row.has_early_leave ? "○" : "",
    formatDurationMinutes(overtimeMinutes),
    shiftTypeLabel(row.shift_type),
    row.alert_codes.join(", "),
    "",
  ];
}

export async function exportAttendanceExcel({
  officeId,
  yearMonth,
}: {
  officeId: string | null;
  yearMonth: string;
}): Promise<void> {
  const supabase = createClient();
  const { start, end } = monthRange(yearMonth);

  const { data, error } = await supabase.rpc("fetch_attendance_export_by_office", {
    p_office_id: officeId,
    p_month_start: start,
    p_month_end: end,
  });
  if (error) throw new Error(error.message);

  const rows = (data ?? []) as AttendanceExportRow[];

  // 2.3: 勤務した施設ごと(職員×施設)にシートを分割する。
  const groups = new Map<string, { employeeName: string; officeName: string; rows: AttendanceExportRow[] }>();
  for (const row of rows) {
    const key = `${row.employee_id}::${row.office_id}`;
    if (!groups.has(key)) {
      groups.set(key, { employeeName: row.employee_name, officeName: row.office_name, rows: [] });
    }
    groups.get(key)!.rows.push(row);
  }

  const workbook = new ExcelJS.Workbook();
  const usedSheetNames = new Set<string>();

  for (const [key, group] of Array.from(groups.entries()).sort(([, a], [, b]) =>
    a.employeeName.localeCompare(b.employeeName, "ja"),
  )) {
    let sheetName = sanitizeSheetName(`${group.employeeName}(${group.officeName})`);
    if (usedSheetNames.has(sheetName)) {
      sheetName = sanitizeSheetName(`${sheetName}_${key.slice(0, 4)}`);
    }
    usedSheetNames.add(sheetName);

    const sheet = workbook.addWorksheet(sheetName);
    sheet.columns = COLUMNS.map((c) => ({ header: c.header, width: c.width }));
    sheet.getRow(1).font = { bold: true };

    for (const row of group.rows.sort((a, b) => a.work_date.localeCompare(b.work_date))) {
      sheet.addRow(buildRow(row));
    }
  }

  if (workbook.worksheets.length === 0) {
    workbook.addWorksheet("該当データなし");
  }

  const buffer = await workbook.xlsx.writeBuffer();
  const blob = new Blob([buffer], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `勤怠_${yearMonth}.xlsx`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
