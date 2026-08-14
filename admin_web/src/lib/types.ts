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
  class_id: string;
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
  contact_id: string | null;
  contact_status: string | null;
  contact_scheduled_publish_at: string | null;
  contact_published_at: string | null;
  on_therapy_outing: boolean;
  therapy_out_at: string | null;
  therapy_provider_name: string | null;
  // ▼186 追加(登降園バー / 出欠モーダル用)
  arrival_at: string | null; // 実績 登園(最初のdrop系) timestamptz
  departure_at: string | null; // 実績 降園(最後のpick系) timestamptz
  out_at: string | null; // 実績 外出(最後のout) timestamptz
  return_at: string | null; // 実績 戻り(最後のreturn) timestamptz
  scheduled_start_at: string | null; // 予定 登園(日別override優先→週次標準) "HH:MM:SS"
  scheduled_end_at: string | null; // 予定 降園 "HH:MM:SS"
  attendance_kind: AttendanceKind | null;
  attendance_note: string | null;
};

// 出欠種別(184/185)。遅刻/早退は出席側、is_absent同期は sick/personal のみ。
export type AttendanceKind = "none" | "late" | "early_leave" | "sick_absence" | "personal_absence";

export const ATTENDANCE_KIND_LABELS: Record<AttendanceKind, string> = {
  none: "通常",
  late: "遅刻",
  early_leave: "早退",
  sick_absence: "病欠",
  personal_absence: "都合欠",
};

/**
 * 連絡帳(職員→保護者)の公開状態バッジ。列値から導出する。
 * - none: 連絡帳未作成 / draft: 未承認(下書き・提出・差戻し)
 * - scheduled: 承認済み+予約あり+未公開 / published: 公開済み
 * - unscheduled: 承認済みだが予約なし+未公開(予約取消後)=再予約が必要
 */
export type ContactPublishBadge = "none" | "draft" | "scheduled" | "published" | "unscheduled";

export function deriveContactBadge(row: DailyBoardRow): ContactPublishBadge {
  if (!row.contact_id) return "none";
  if (row.contact_status !== "approved") return "draft";
  if (row.contact_published_at != null) return "published";
  if (row.contact_scheduled_publish_at != null) return "scheduled";
  return "unscheduled";
}

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

/** 在籍登園状況サマリー(fetch_daily_board_summary_for_office の1行)。 */
export type DailyBoardSummary = {
  enrolled: number;
  expected: number;
  attended: number;
  absent: number;
  present_now: number;
};

/** 午睡チェック(Phase 3)。 */
export const NAP_BODY_POSITIONS: Record<string, string> = {
  right: "右",
  left: "左",
  supine: "仰向け",
  prone_corrected: "うつ伏せ直し",
};

// グリッドセル内の短縮表記(セル幅を記録内容に依らず固定にするため)。正式名は NAP_BODY_POSITIONS。
export const NAP_BODY_POSITIONS_SHORT: Record<string, string> = {
  right: "右",
  left: "左",
  supine: "仰",
  prone_corrected: "伏直",
};

export type NapCheck = {
  slot_at: string;
  body_position: string;
  breathing: boolean;
  complexion: boolean;
  bedding: boolean;
  source: string;
  checked_by_name?: string | null; // 191で追加。記録者名(セルのツールチップ用)
};

export type NapInterval = {
  id: string;
  seq: number;
  sleep_start_at: string;
  wake_up_at: string | null;
};

export type NapSessionRow = {
  session_id: string;
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  class_id: string;
  class_name: string;
  is_required: boolean;
  sleep_start_at: string | null;
  wake_up_at: string | null;
  intervals: NapInterval[];
  checks: NapCheck[];
};

export type NapMissing = {
  session_id: string;
  child_id: string;
  display_name: string;
  class_id: string;
  class_name: string;
  missing_count: number;
  missing_slots: string[];
};

/** 療育外出(§5)。 */
export type TherapyProvider = { id: string; name: string; is_active: boolean };

export type ChildTherapySetting = {
  id: string;
  provider_id: string;
  start_date: string;
  end_date: string | null;
  therapy_providers: { name: string } | null;
};

export type TherapyRecordRow = {
  event_id: string;
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  provider_id: string;
  provider_name: string;
  event_type: string;
  occurred_at: string;
  source: string;
  correction_note: string | null;
};

/** 天気記録(daily_weather_records の1行)。施設×日で1行。 */
export type WeatherRecord = {
  weather: string;
  temperature: number | null;
  humidity: number | null;
};

export const WEATHER_OPTIONS = ["晴れ", "曇り", "雨", "雪", "その他"] as const;

export const DAILY_BOARD_STATUS_LABELS: Record<DailyBoardRow["status"], string> = {
  not_arrived: "未登園",
  present: "登園中",
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
  request_type: "absence" | "tardiness" | "early_leave" | "pickup_person_change" | "medication" | "other";
  target_date: string;
  end_date: string | null;
  absence_kind: "sick_absence" | "personal_absence" | null;
  // 服薬連絡(201)の薬の種類(日本語ラベル)。medication以外はnull。
  medication_kinds: string[] | null;
  details: Record<string, unknown>;
  created_at: string;
};

export const ABSENCE_KIND_LABELS: Record<"sick_absence" | "personal_absence", string> = {
  sick_absence: "病気",
  personal_absence: "家庭の都合",
};

export const PARENT_REQUEST_TYPE_LABELS: Record<ParentRequestRow["request_type"], string> = {
  absence: "欠席",
  tardiness: "遅刻",
  early_leave: "早退",
  pickup_person_change: "お迎えの方の変更",
  medication: "服薬連絡",
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
  candidate_id: string;
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
  form1_policy_stance_item_id: string | null;
  form1_policy_target_month: string | null;
  form1_policy_no_extra_staff_reason: string | null;
  form1_policy_no_application_reason: string | null;
  form1_subsidy_expected_effect: string | null;
  form2_id: string;
  form2_annual_goal: string | null;
};

export type SupportChildcareClassSetting = {
  age: number;
  extra_staff_count: number | null;
  staff_count: number | null;
  notes: string | null;
  submission_target_candidate_count: number;
};

export type SupportChildcareClassHeadcount = {
  age: number;
  headcount: number;
};

export type SupportChildcareChildHeaderInfo = {
  full_name: string;
  name_kana: string | null;
  birth_date: string;
  gender: string;
  class_name: string | null;
  age_group: string | null;
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
  agency_name: string | null;
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

// ---- 園内記録 ----

export type ChildInternalNoteCategory = "handover" | "observation" | "guardian_contact" | "external_agency" | "other";

// 区分の日本語表示名(定数ファイル1箇所に集約。Ohana Kidsを実装する際もここを参照する)
export const CHILD_INTERNAL_NOTE_CATEGORY_LABELS: Record<ChildInternalNoteCategory, string> = {
  handover: "申し送り",
  observation: "個人日誌",
  guardian_contact: "保護者との面談記録",
  external_agency: "療育等との連携記録",
  other: "その他",
};

// ---- 役職表示名(1箇所集約。マイグレーション147で executive_director/area_manager を追加) ----

export const ROLE_DISPLAY_NAMES: Record<string, string> = {
  system_admin: "システム管理者",
  labor_manager: "労務管理者",
  executive_director: "統括園長",
  director: "園長",
  area_manager: "統括管理者",
  chief: "主任",
  office_manager: "管理者",
  viewer: "閲覧者",
  staff: "一般職員",
};

// 一般職員(staff)は役職行を持たずに運用されることがある(本番実測でstaff割当0名)。
// role_code が null/未知の場合は「一般職員」を既定表示にする。
export function roleDisplayName(roleCode: string | null | undefined): string {
  if (!roleCode) return "一般職員";
  return ROLE_DISPLAY_NAMES[roleCode] ?? "一般職員";
}

export type SessionIdentity = {
  employee_id: string;
  name: string;
  role_code: string | null;
  home_office_name: string | null;
};

export type ChildInternalNote = {
  id: string;
  child_id: string;
  office_id: string;
  note_date: string;
  category: ChildInternalNoteCategory;
  body: string;
  ai_excluded: boolean;
  author_employee_id: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

// ============================================================
// お知らせ(保護者向け一斉配信)Phase C
// ============================================================
export type GuardianNoticeStatus = "draft" | "in_review" | "returned" | "approved";

export const GUARDIAN_NOTICE_STATUS_LABELS: Record<GuardianNoticeStatus, string> = {
  draft: "下書き",
  in_review: "申請中",
  returned: "差し戻し",
  approved: "送信済み",
};

// fetch_guardian_notices_for_staff の1行
export type GuardianNoticeRow = {
  id: string;
  title: string;
  body: string;
  status: GuardianNoticeStatus;
  returned_reason: string | null;
  revoked_at: string | null;
  revoke_reason: string | null;
  created_at: string;
  sent_at: string | null;
  approved_at: string | null;
  created_by_name: string;
  approver_name: string | null;
  target_labels: string[] | null;
  total_guardians: number;
  read_guardians: number;
  can_edit: boolean;
  can_approve: boolean;
};

// 宛先の種別(作成UI・fetch_guardian_notice_targets 共通)
export type GuardianNoticeTargetType = "all" | "office" | "class" | "child";

// fetch_guardian_notice_targets の1行
export type GuardianNoticeTarget = {
  target_type: GuardianNoticeTargetType;
  office_id: string | null;
  class_id: string | null;
  child_id: string | null;
  label: string | null;
};

// create_guardian_notice に渡す p_targets の1要素
export type GuardianNoticeTargetInput = {
  type: GuardianNoticeTargetType;
  office_id?: string;
  class_id?: string;
  child_id?: string;
};

// preview_guardian_notice の戻り(1行)
export type GuardianNoticePreview = {
  office_names: string[] | null;
  guardian_count: number;
  child_count: number;
};

// fetch_guardian_notice_read_summary の戻り(1行)
export type GuardianNoticeReadSummary = {
  total_guardians: number;
  read_guardians: number;
  total_children: number;
  unread_children: number;
};

// fetch_guardian_notice_unread_recipients の1行(未読世帯一覧)
export type GuardianNoticeUnreadRecipient = {
  kind: "child" | "guardian";
  child_id: string | null;
  child_name: string | null;
  class_name: string | null;
  guardian_id: string | null;
  guardian_name: string | null;
};
