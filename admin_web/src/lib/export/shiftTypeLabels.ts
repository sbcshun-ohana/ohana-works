// 13.5 シフト区分(コード化)の表示ラベル。
const SHIFT_TYPE_LABELS: Record<string, string> = {
  normal_work: "通常勤務",
  holiday_substitute_saturday_work: "祝日代替土曜勤務",
  distributed_holiday_substitute_work: "分散祝日代替勤務",
  statutory_holiday_work: "法定休日労働",
  non_statutory_holiday_work: "法定外休日勤務",
  event_work: "行事出勤",
  paid_leave: "有給",
  absence: "欠勤",
  company_holiday: "会社所定休日",
  national_holiday: "国民の祝日",
  year_end_new_year_holiday: "年末年始休日",
  requires_admin_review: "管理者確認対象",
};

export function shiftTypeLabel(code: string | null): string {
  if (!code) return "";
  return SHIFT_TYPE_LABELS[code] ?? code;
}
