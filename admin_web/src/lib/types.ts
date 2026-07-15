export type ManageableOffice = {
  id: string;
  name: string;
  can_select_all: boolean;
};

export type AttendanceRow = {
  employee_id: string;
  employee_name: string;
  work_date: string;
  office_id: string;
  office_name: string;
  actual_clock_in_at: string | null;
  approved_work_start_at: string | null;
  actual_clock_out_at: string | null;
  approved_work_end_at: string | null;
  actual_break_start_at: string | null;
  actual_break_end_at: string | null;
  approved_break_minutes: number | null;
  shift_type: string | null;
  alert_codes: string[];
};

export type AttendanceExportRow = {
  employee_id: string;
  employee_name: string;
  work_date: string;
  office_id: string;
  office_name: string;
  shift_start_time: string | null;
  shift_end_time: string | null;
  shift_break_minutes: number | null;
  shift_type: string | null;
  actual_clock_in_at: string | null;
  approved_work_start_at: string | null;
  actual_clock_out_at: string | null;
  approved_work_end_at: string | null;
  actual_break_start_at: string | null;
  actual_break_end_at: string | null;
  approved_break_minutes: number | null;
  has_paid_leave: boolean;
  has_absence: boolean;
  has_tardiness: boolean;
  has_early_leave: boolean;
  alert_codes: string[];
};

export const CORRECTABLE_FIELDS = [
  { key: "actual_clock_in_at", label: "実出勤時刻", kind: "timestamp" },
  { key: "approved_work_start_at", label: "承認済み出勤時刻", kind: "timestamp" },
  { key: "actual_clock_out_at", label: "実退勤時刻", kind: "timestamp" },
  { key: "approved_work_end_at", label: "承認済み退勤時刻", kind: "timestamp" },
  { key: "actual_break_start_at", label: "実休憩開始", kind: "timestamp" },
  { key: "actual_break_end_at", label: "実休憩終了", kind: "timestamp" },
  { key: "approved_break_minutes", label: "承認済み休憩時間(分)", kind: "int" },
] as const;

export type CorrectableFieldKey = (typeof CORRECTABLE_FIELDS)[number]["key"];
