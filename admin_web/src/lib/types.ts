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

export type ChildcareOffice = {
  office_id: string;
  office_name: string;
  is_manager: boolean;
};

export type ChildcareClass = {
  class_id: string;
  class_name: string;
  age_group: string;
  school_year: number;
};

export type ChildcareStaff = {
  employee_id: string;
  name: string;
};

export type ClassChild = {
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  gender: string;
  enrollment_status: string;
  is_absent: boolean;
  absence_reason: string | null;
};

export type ClassActivityRow = {
  activity_id: string | null;
  class_id: string;
  class_name: string;
  assignee_employee_id: string | null;
  assignee_name: string | null;
  status: "draft" | "submitted" | "approved" | "rejected" | null;
  today_theme: string | null;
  activity_content: string | null;
  class_overview: string | null;
  class_announcement: string | null;
  other_notes: string | null;
  submitted_at: string | null;
  rejected_reason: string | null;
};

export type DailyContactRow = {
  contact_id: string | null;
  child_id: string;
  child_display_name: string;
  child_honorific_suffix: string | null;
  class_name: string | null;
  assignee_employee_id: string | null;
  assignee_name: string | null;
  status: "draft" | "submitted" | "approved" | "rejected" | null;
  guardian_message: string | null;
  child_today_notes: string | null;
  free_notes: string | null;
  ai_generated_text: string | null;
  current_text: string | null;
  admin_comment: string | null;
  rejected_reason: string | null;
  submitted_at: string | null;
  approved_at: string | null;
  copied_at: string | null;
  is_absent: boolean;
};

export type ChildForAssignment = {
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  class_name: string | null;
  current_assignee_employee_id: string | null;
  current_assignee_name: string | null;
  enrollment_status: string;
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
