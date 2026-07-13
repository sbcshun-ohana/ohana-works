// deno-lint-ignore-file no-explicit-any
import { tokyoDayBounds } from "./tokyo.ts";

const ACTUAL_COLUMN_BY_PUNCH_TYPE: Record<string, string> = {
  clock_in: "actual_clock_in_at",
  break_start: "actual_break_start_at",
  break_end: "actual_break_end_at",
  clock_out: "actual_clock_out_at",
};

// 9.4/11.1: time_punches(実打刻の不変ログ)へINSERTし、daily_attendancesの
// actual_*列を同期する。丸め処理は行わない(11.2: 丸めは給与算定用の承認済み時間のみ)。
export async function recordPunch(
  adminClient: any,
  params: {
    employeeId: string;
    deviceId: string;
    officeId: string;
    punchType: "clock_in" | "break_start" | "break_end" | "clock_out";
    source: "qr" | "proxy";
    qrTokenId?: string | null;
  },
) {
  const punchedAt = new Date();

  const { error: insertError } = await adminClient.from("time_punches")
    .insert({
      employee_id: params.employeeId,
      device_id: params.deviceId,
      punch_type: params.punchType,
      punched_at: punchedAt.toISOString(),
      source: params.source,
      office_id: params.officeId,
      qr_token_id: params.qrTokenId ?? null,
    });
  if (insertError) throw insertError;

  const { dateStr } = tokyoDayBounds(punchedAt);
  const column = ACTUAL_COLUMN_BY_PUNCH_TYPE[params.punchType];

  const { error: upsertError } = await adminClient.from("daily_attendances")
    .upsert(
      {
        employee_id: params.employeeId,
        work_date: dateStr,
        [column]: punchedAt.toISOString(),
      },
      { onConflict: "employee_id,work_date" },
    );
  if (upsertError) throw upsertError;

  return { punchedAt };
}
