// 標準報酬月額の一括CSV取込。ヘッダー: employee_number,health_insurance_amount,
// health_insurance_grade,pension_amount,pension_grade,effective_year_month,revision_reason

export const EXPECTED_HEADERS = [
  "employee_number",
  "health_insurance_amount",
  "health_insurance_grade",
  "pension_amount",
  "pension_grade",
  "effective_year_month",
  "revision_reason",
] as const;

const VALID_REVISION_REASONS = new Set(["資格取得時決定", "定時決定", "随時改定"]);

export type SmrRow = {
  employee_number: string;
  employee_name: string;
  health_insurance_amount: number;
  health_insurance_grade: number;
  pension_amount: number;
  pension_grade: number;
  effective_year_month: string;
  revision_reason: string;
};

export type ParseResult = { rows: SmrRow[]; errors: string[]; warnings: string[] };

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const YM_RE = /^\d{4}-\d{2}-01$/;

export function parseStandardMonthlyRemunerationCsv(
  text: string,
  employees: { employee_number: string; name: string }[],
): ParseResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const employeeByNumber = new Map(employees.map((e) => [e.employee_number, e.name]));

  const lines = text.split(/\r\n|\n|\r/).map((l) => l.trim()).filter((l) => l.length > 0);
  if (lines.length === 0) return { rows: [], errors: ["ファイルが空です"], warnings: [] };

  const header = splitCsvLine(lines[0]);
  if (header.length !== EXPECTED_HEADERS.length || !EXPECTED_HEADERS.every((h, i) => header[i] === h)) {
    errors.push(`ヘッダー行が想定形式と異なります。期待するヘッダー: ${EXPECTED_HEADERS.join(",")}`);
    return { rows: [], errors, warnings };
  }

  const rows: SmrRow[] = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [employeeNumber, healthAmountStr, healthGradeStr, pensionAmountStr, pensionGradeStr, ym, reason] = cols;

    const employeeName = employeeByNumber.get(employeeNumber);
    if (!employeeName) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})に一致する職員がいません`);
      continue;
    }
    const healthAmount = Number(healthAmountStr);
    const healthGrade = Number(healthGradeStr);
    const pensionAmount = Number(pensionAmountStr);
    const pensionGrade = Number(pensionGradeStr);
    if (!Number.isInteger(healthAmount) || healthAmount <= 0) {
      errors.push(`${lineNo}行目: health_insurance_amount(${healthAmountStr})は正の整数で指定してください`);
      continue;
    }
    if (!Number.isInteger(pensionAmount) || pensionAmount <= 0) {
      errors.push(`${lineNo}行目: pension_amount(${pensionAmountStr})は正の整数で指定してください`);
      continue;
    }
    if (!Number.isInteger(healthGrade) || !Number.isInteger(pensionGrade)) {
      errors.push(`${lineNo}行目: 等級は整数で指定してください`);
      continue;
    }
    if (!YM_RE.test(ym)) {
      errors.push(`${lineNo}行目: effective_year_month(${ym})はYYYY-MM-01形式で指定してください`);
      continue;
    }
    if (!VALID_REVISION_REASONS.has(reason)) {
      errors.push(`${lineNo}行目: revision_reason(${reason})は資格取得時決定・定時決定・随時改定のいずれかで指定してください`);
      continue;
    }

    rows.push({
      employee_number: employeeNumber,
      employee_name: employeeName,
      health_insurance_amount: healthAmount,
      health_insurance_grade: healthGrade,
      pension_amount: pensionAmount,
      pension_grade: pensionGrade,
      effective_year_month: ym,
      revision_reason: reason,
    });
  }

  if (rows.length === 0 && errors.length === 0) warnings.push("取込対象の行がありません");
  return { rows, errors, warnings };
}
