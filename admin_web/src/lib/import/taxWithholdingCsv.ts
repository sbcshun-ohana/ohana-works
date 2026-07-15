// 源泉徴収区分(甲欄/乙欄)・扶養人数の一括CSV取込。
// CSVは1職員=1行(ヘッダー: employee_number,tax_column,
// social_insurance_dependent_count,income_tax_dependent_count,
// submitted_flag,effective_start_year_month)。
// 扶養人数は①社会保険の扶養人数と②所得税の扶養人数(源泉控除対象扶養親族数)を
// 別々に管理する。源泉徴収税額計算に使うのは②のみ。

export const EXPECTED_HEADERS = [
  "employee_number",
  "tax_column",
  "social_insurance_dependent_count",
  "income_tax_dependent_count",
  "submitted_flag",
  "effective_start_year_month",
] as const;

export type TaxWithholdingRow = {
  employee_number: string;
  employee_name: string;
  tax_column: "甲欄" | "乙欄";
  social_insurance_dependent_count: number;
  income_tax_dependent_count: number;
  submitted_flag: boolean;
  effective_start_year_month: string;
};

export type ParseResult = {
  rows: TaxWithholdingRow[];
  errors: string[];
  warnings: string[];
};

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const YM_RE = /^\d{4}-\d{2}-01$/;

export function parseTaxWithholdingCsv(
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

  const rows: TaxWithholdingRow[] = [];
  const seen = new Set<string>();

  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [employeeNumber, taxColumnStr, siDepStr, itDepStr, submittedStr, ym] = cols;

    const employeeName = employeeByNumber.get(employeeNumber);
    if (!employeeName) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})に一致する職員がいません`);
      continue;
    }
    if (seen.has(employeeNumber)) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})がファイル内で重複しています`);
      continue;
    }
    if (taxColumnStr !== "甲欄" && taxColumnStr !== "乙欄") {
      errors.push(`${lineNo}行目: tax_column(${taxColumnStr})は甲欄または乙欄で指定してください`);
      continue;
    }
    const socialInsuranceDependentCount = Number(siDepStr);
    if (!Number.isInteger(socialInsuranceDependentCount) || socialInsuranceDependentCount < 0) {
      errors.push(`${lineNo}行目: social_insurance_dependent_count(${siDepStr})は0以上の整数で指定してください`);
      continue;
    }
    const incomeTaxDependentCount = Number(itDepStr);
    if (!Number.isInteger(incomeTaxDependentCount) || incomeTaxDependentCount < 0) {
      errors.push(`${lineNo}行目: income_tax_dependent_count(${itDepStr})は0以上の整数で指定してください`);
      continue;
    }
    const submittedLower = submittedStr.toLowerCase();
    if (submittedLower !== "true" && submittedLower !== "false") {
      errors.push(`${lineNo}行目: submitted_flag(${submittedStr})はtrueまたはfalseで指定してください`);
      continue;
    }
    if (!YM_RE.test(ym)) {
      errors.push(`${lineNo}行目: effective_start_year_month(${ym})はYYYY-MM-01形式で指定してください`);
      continue;
    }

    seen.add(employeeNumber);
    rows.push({
      employee_number: employeeNumber,
      employee_name: employeeName,
      tax_column: taxColumnStr,
      social_insurance_dependent_count: socialInsuranceDependentCount,
      income_tax_dependent_count: incomeTaxDependentCount,
      submitted_flag: submittedLower === "true",
      effective_start_year_month: ym,
    });
  }

  if (rows.length === 0 && errors.length === 0) {
    warnings.push("取込対象の行がありません");
  }

  return { rows, errors, warnings };
}
