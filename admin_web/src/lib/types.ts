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
  nap_periods: { start: string; end: string }[];
  toileting_records: { time: string; type: string }[];
  meal_completion_pct: 100 | 75 | 50 | 25 | 0 | null;
  meal_free_note: string | null;
  temperature: number | null;
  temperature_measured_at: string | null;
  bath_taken: boolean | null;
};

export const TOILETING_TYPES = ["普通", "軟便", "硬便", "下痢便"] as const;
export const MEAL_COMPLETION_OPTIONS = [100, 75, 50, 25, 0] as const;

export type ChildForAssignment = {
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  class_name: string | null;
  current_assignee_employee_id: string | null;
  current_assignee_name: string | null;
  enrollment_status: string;
};

// --- 保護者アプリ Phase A ---

export type DailyBoardRow = {
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  class_name: string;
  status: "not_arrived" | "present" | "picked_up" | "absent";
  last_event_type: string | null;
  last_event_at: string | null;
};

export const DAILY_BOARD_STATUS_LABELS: Record<DailyBoardRow["status"], string> = {
  not_arrived: "未登園",
  present: "在園中",
  picked_up: "降園済み",
  absent: "欠席",
};

export type GuardianRow = {
  guardian_id: string;
  name: string;
  phone: string | null;
  email: string | null;
  status: "active" | "suspended";
  linked_children: string | null;
};

export type GuardianInvitationRow = {
  invitation_id: string;
  child_id: string;
  child_display_name: string;
  role: "primary" | "additional";
  expires_at: string;
  status: "pending" | "accepted" | "expired" | "revoked";
};

export const GUARDIAN_INVITATION_STATUS_LABELS: Record<GuardianInvitationRow["status"], string> = {
  pending: "招待中",
  accepted: "受諾済み",
  expired: "期限切れ",
  revoked: "取消済み",
};

export type ParentRequestRow = {
  request_id: string;
  child_id: string;
  child_display_name: string;
  guardian_name: string;
  request_type: "absence" | "tardiness" | "early_leave" | "infectious_disease" | "pickup_person_change";
  target_date: string;
  details: Record<string, unknown>;
  created_at: string;
};

export const PARENT_REQUEST_TYPE_LABELS: Record<ParentRequestRow["request_type"], string> = {
  absence: "欠席",
  tardiness: "遅刻",
  early_leave: "早退",
  infectious_disease: "感染症",
  pickup_person_change: "送迎者変更",
};

export type ClassDailyPhoto = {
  id: string;
  class_id: string;
  business_date: string;
  storage_path: string;
  status: "draft" | "checked" | "published";
  checked_at: string | null;
  published_at: string | null;
  created_at: string;
};

export type EmergencyContact = {
  id: string;
  child_id: string;
  name: string;
  phone: string;
  relationship: string | null;
  sort_order: number;
  duplicate_approved_by: string | null;
  duplicate_approved_reason: string | null;
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
