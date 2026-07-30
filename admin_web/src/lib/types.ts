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
  family_daily_report_required: boolean;
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

export type ChildMasterRow = {
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  full_name: string;
  name_kana: string | null;
  gender: string;
  birth_date: string;
  enrollment_status: string;
  withdrawal_date: string | null;
  class_id: string | null;
  class_name: string | null;
  class_family_daily_report_required: boolean | null;
  family_daily_report_required_from: string | null;
  family_daily_report_required_until: string | null;
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

// --- 保護者アプリ Phase A ---

export type DailyBoardRow = {
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  class_name: string;
  status: "not_arrived" | "present" | "picked_up" | "absent";
  last_event_type: string | null;
  last_event_at: string | null;
  family_daily_report_status: "draft" | "submitted" | null;
  temperature: number | null;
  has_pickup_change: boolean;
  pickup_person_name: string | null;
  pickup_person_relationship: string | null;
  pickup_time_from: string | null;
  pickup_time_to: string | null;
};

export const FAMILY_MOOD_LABELS: Record<string, string> = { good: "良い", normal: "普通", bad: "悪い" };
export const FAMILY_BOWEL_CONDITION_LABELS: Record<string, string> = {
  normal: "普通",
  soft: "軟便",
  hard: "硬便",
  small: "少量便",
};

export type FamilyDailyReportSummary = {
  status: "draft" | "submitted";
  temperature: number | null;
  temperature_measured_at: string | null;
  symptoms: string | null;
  home_notes: string | null;
  night_mood: string | null;
  morning_mood: string | null;
  night_bowel_count: number | null;
  night_bowel_condition: string | null;
  morning_bowel_count: number | null;
  morning_bowel_condition: string | null;
  sleep_start_at: string | null;
  sleep_end_at: string | null;
  dinner_content: string | null;
  dinner_at: string | null;
  breakfast_content: string | null;
  breakfast_at: string | null;
  pickup_person_name: string | null;
  pickup_person_relationship: string | null;
  pickup_time_from: string | null;
  pickup_time_to: string | null;
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
  request_type: "absence" | "tardiness" | "early_leave" | "pickup_person_change" | "other";
  target_date: string;
  details: Record<string, unknown>;
  created_at: string;
};

export const PARENT_REQUEST_TYPE_LABELS: Record<ParentRequestRow["request_type"], string> = {
  absence: "欠席",
  tardiness: "遅刻",
  early_leave: "早退",
  pickup_person_change: "お迎えの方の変更",
  other: "その他連絡",
};

export type PunchType = "clock_in" | "break_start" | "break_end" | "clock_out";

export const PUNCH_TYPE_LABELS: Record<PunchType, string> = {
  clock_in: "出勤",
  break_start: "休憩開始",
  break_end: "休憩再開",
  clock_out: "退勤",
};

export type ProxyPunchLogRow = {
  id: string;
  employee_id: string;
  employee_name: string;
  punch_type: PunchType;
  punched_at: string;
  proxy_operator_id: string;
  proxy_operator_name: string;
  source_label: string;
  note: string | null;
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

// --- Phase 1 C: シフト週次テンプレート・イレギュラー例外 ---

export type OfficeEmployee = {
  employee_id: string;
  name: string;
};

export const WEEKDAY_LABELS = ["月", "火", "水", "木", "金", "土", "日"] as const;

export type ShiftWeeklyTemplateRow = {
  id: string;
  employee_id: string;
  office_id: string;
  weekday: number; // 0=月 〜 6=日
  start_time: string;
  end_time: string;
  break_minutes: number;
};

export type ShiftExceptionRow = {
  id: string;
  employee_id: string;
  work_date: string;
  is_day_off: boolean;
  office_id: string | null;
  start_time: string | null;
  end_time: string | null;
  break_minutes: number | null;
  note: string | null;
};

// --- Phase 1 E: お知らせ・個別連絡・グループ連絡 ---

export type NoticeCategory = "会社一斉" | "園単位" | "個別" | "役職別" | "勤務交代関連" | "災害モード" | "グループ";

// create_notice RPCが作成に対応するカテゴリ(勤務交代関連・災害モードは専用フロー経由のため対象外)。
export const COMPOSABLE_NOTICE_CATEGORIES = [
  { value: "会社一斉", label: "会社一斉", requiresLaborManager: true },
  { value: "園単位", label: "園単位", requiresLaborManager: false },
  { value: "役職別", label: "役職別", requiresLaborManager: true },
  { value: "個別", label: "個別", requiresLaborManager: false },
  { value: "グループ", label: "グループ", requiresLaborManager: false },
] as const satisfies readonly { value: NoticeCategory; label: string; requiresLaborManager: boolean }[];

export type ComposableNoticeCategory = (typeof COMPOSABLE_NOTICE_CATEGORIES)[number]["value"];

export const STANDARD_REPLY_OPTION_CHOICES = ["確認しました", "対応します", "対応できません", "管理者に確認してください"] as const;

export type NoticeRow = {
  id: string;
  category: NoticeCategory;
  title: string;
  body: string;
  target_office_id: string | null;
  target_position_id: string | null;
  target_group_id: string | null;
  requires_read_confirmation: boolean;
  standard_reply_options: string[] | null;
  created_at: string;
};

export type PositionRow = {
  id: string;
  name: string;
};

export type StaffGroupType = "class_team" | "project_team" | "custom";

export const STAFF_GROUP_TYPE_LABELS: Record<StaffGroupType, string> = {
  class_team: "クラス担当",
  project_team: "プロジェクトチーム",
  custom: "その他",
};

export type StaffGroupRow = {
  id: string;
  office_id: string;
  group_type: StaffGroupType;
  name: string;
  related_class_id: string | null;
  is_active: boolean;
  created_at: string;
  archived_at: string | null;
};

export type StaffGroupMemberRow = {
  id: string;
  group_id: string;
  employee_id: string;
  added_at: string;
  removed_at: string | null;
};

// ---- 支援保育事業(Phase 3) ----

export type SupportChildcareApplicationStatus =
  | "draft"
  | "ai_draft"
  | "in_review"
  | "returned"
  | "approved"
  | "finalized"
  | "released"
  | "superseded"
  | "archived";

export type SupportChildcareCandidacyStatus = "candidate" | "under_review" | "submission_target" | "excluded";

export type SupportChildcareApplicationRow = {
  application_id: string | null;
  child_id: string;
  child_name: string;
  candidacy_status: SupportChildcareCandidacyStatus;
  status: SupportChildcareApplicationStatus | null;
  author_name: string | null;
  approver_name: string | null;
  finalized_at: string | null;
};

export type SupportChildcareCandidatePoolRow = {
  child_id: string;
  child_name: string;
  class_id: string | null;
  class_name: string | null;
  age_group: string | null;
};

export type SupportChildcareApplicationDetail = {
  application_id: string;
  status: SupportChildcareApplicationStatus;
  child_name: string;
  form1_id: string;
  form1_recorded_on: string | null;
  form1_class_size_3: number | null;
  form1_class_size_4: number | null;
  form1_class_size_5: number | null;
  form1_extra_staff_count_3: number | null;
  form1_extra_staff_count_4: number | null;
  form1_extra_staff_count_5: number | null;
  form1_staff_count: number | null;
  form1_notes: string | null;
  form1_policy_stance_item_id: string | null;
  form1_policy_target_month: string | null;
  form1_policy_no_extra_staff_reason: string | null;
  form1_policy_no_application_reason: string | null;
  form1_subsidy_expected_effect: string | null;
  form2_id: string;
  form2_annual_goal: string | null;
};

export type SupportChildcareCheckItem = {
  id: string;
  check_group: "policy_stance" | "subsidy_use" | "child_behavior";
  category: string | null;
  label: string;
  is_other_option: boolean;
  sort_order: number;
};

export type SupportChildcareForm2Term = {
  id: string;
  form2_id: string;
  form1_id: string;
  term_number: number;
  term_goal: string | null;
  child_behavior: string | null;
  considered_factors: string | null;
  support_measures: string | null;
  evaluation: string | null;
};

export type SupportChildcareGuardianMeeting = {
  id: string;
  meeting_date: string;
  meeting_type: "formal" | "pickup_dropoff_note";
  attendee: string | null;
  content: string | null;
  guardian_intention: string | null;
};

export type SupportChildcareAgencyLink = {
  id: string;
  agency_type: "patrol_consultation" | "developmental_consultation" | "child_development_support_office" | "facility_visit_support";
  contact_person: string | null;
  consultation_date: string | null;
  enrollment_start_date: string | null;
  frequency: string | null;
  content: string | null;
  support_outcome: string | null;
};

export type SupportChildcareApplicationReview = {
  id: string;
  reviewer_id: string;
  review_type: "chief_check" | "multi_person_confirm";
  action: "approved" | "returned";
  comment: string | null;
  reviewed_at: string;
};

export type SupportChildcareSubmissionSummary = {
  age_3_count: number;
  age_4_count: number;
  age_5_count: number;
  total_count: number;
};

export type SupportChildcareAiDraftResult = {
  ai_run_id: string;
  output_text: string;
  evidence_count: number;
  low_evidence: boolean;
};
