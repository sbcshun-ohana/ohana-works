// 週所定労働時間(weekly_scheduled_hours)の一括CSV取込。
// CSVは1職員=1行(ヘッダー: employee_number,weekly_hours,effective_start_date)。
// 週20時間以上の社会保険加入判定チェック(insurance_eligibility_mismatch)の
// 判定材料として使用する。

export const EXPECTED_HEADERS = ["employee_number", "weekly_hours", "effective_start_date"] as const;

export type WeeklyScheduledHoursRow = {
  employee_number: string;
  employee_name: string;
  weekly_hours: number;
  effective_start_date: string;
};

export type ParseResult = {
  rows: WeeklyScheduledHoursRow[];
  errors: string[];
  warnings: string[];
};

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function parseWeeklyScheduledHoursCsv(
  text: string,
  employees: { employee_number: string; name: string }[],
): ParseResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const employeeByNumber = new Map(employees.map((e) => [e.employee_number, e.name]));

  const lines = text
    .split(/\r\n|\n|\r/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);

  if (lines.length === 0) {
    return { rows: [], errors: ["ファイルが空です"], warnings: [] };
  }

  const header = splitCsvLine(lines[0]);
  const headerOk =
    header.length === EXPECTED_HEADERS.length &&
    EXPECTED_HEADERS.every((h, i) => header[i] === h);
  if (!headerOk) {
    errors.push(`ヘッダー行が想定形式と異なります。期待するヘッダー: ${EXPECTED_HEADERS.join(",")}`);
    return { rows: [], errors, warnings };
  }

  const rows: WeeklyScheduledHoursRow[] = [];
  const seen = new Set<string>();

  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [employeeNumber, weeklyHoursStr, effectiveStartDate] = cols;

    const employeeName = employeeByNumber.get(employeeNumber);
    if (!employeeName) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})に一致する職員がいません`);
      continue;
    }
    if (seen.has(employeeNumber)) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})がファイル内で重複しています`);
      continue;
    }
    const weeklyHours = Number(weeklyHoursStr);
    if (!Number.isFinite(weeklyHours) || weeklyHours < 0) {
      errors.push(`${lineNo}行目: weekly_hours(${weeklyHoursStr})は0以上の数値で指定してください`);
      continue;
    }
    if (!DATE_RE.test(effectiveStartDate)) {
      errors.push(`${lineNo}行目: effective_start_date(${effectiveStartDate})はYYYY-MM-DD形式で指定してください`);
      continue;
    }

    seen.add(employeeNumber);
    rows.push({
      employee_number: employeeNumber,
      employee_name: employeeName,
      weekly_hours: weeklyHours,
      effective_start_date: effectiveStartDate,
    });
  }

  if (rows.length === 0 && errors.length === 0) {
    warnings.push("取込対象の行がありません");
  }

  return { rows, errors, warnings };
}
