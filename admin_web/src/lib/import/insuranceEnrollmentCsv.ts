// 社会保険・雇用保険加入状況の一括CSV取込。ヘッダー: employee_number,
// insurance_type,enrolled,acquisition_date,loss_date

export const EXPECTED_HEADERS = [
  "employee_number",
  "insurance_type",
  "enrolled",
  "acquisition_date",
  "loss_date",
] as const;

const VALID_INSURANCE_TYPES = new Set(["健康保険", "厚生年金", "雇用保険"]);

export type EnrollmentRow = {
  employee_number: string;
  employee_name: string;
  insurance_type: string;
  enrolled: boolean;
  acquisition_date: string | null;
  loss_date: string | null;
};

export type ParseResult = { rows: EnrollmentRow[]; errors: string[]; warnings: string[] };

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function parseInsuranceEnrollmentCsv(
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

  const rows: EnrollmentRow[] = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [employeeNumber, insuranceType, enrolledStr, acqDate, lossDate] = cols;

    const employeeName = employeeByNumber.get(employeeNumber);
    if (!employeeName) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})に一致する職員がいません`);
      continue;
    }
    if (!VALID_INSURANCE_TYPES.has(insuranceType)) {
      errors.push(`${lineNo}行目: insurance_type(${insuranceType})は健康保険・厚生年金・雇用保険のいずれかで指定してください`);
      continue;
    }
    const enrolledLower = enrolledStr.toLowerCase();
    if (enrolledLower !== "true" && enrolledLower !== "false") {
      errors.push(`${lineNo}行目: enrolled(${enrolledStr})はtrueまたはfalseで指定してください`);
      continue;
    }
    if (acqDate && !DATE_RE.test(acqDate)) {
      errors.push(`${lineNo}行目: acquisition_date(${acqDate})はYYYY-MM-DD形式または空欄で指定してください`);
      continue;
    }
    if (lossDate && !DATE_RE.test(lossDate)) {
      errors.push(`${lineNo}行目: loss_date(${lossDate})はYYYY-MM-DD形式または空欄で指定してください`);
      continue;
    }

    rows.push({
      employee_number: employeeNumber,
      employee_name: employeeName,
      insurance_type: insuranceType,
      enrolled: enrolledLower === "true",
      acquisition_date: acqDate || null,
      loss_date: lossDate || null,
    });
  }

  if (rows.length === 0 && errors.length === 0) warnings.push("取込対象の行がありません");
  return { rows, errors, warnings };
}
