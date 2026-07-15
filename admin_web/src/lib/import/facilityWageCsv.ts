// 施設別基本給の一括CSV取込。
// CSVは1施設×1職員=1行(ヘッダー: employee_number,office_id,salary_type,
// monthly_base_salary,hourly_wage,effective_start_date)。単一施設の職員は1行、
// 兼務職員は施設数分の行を持つ。

export const EXPECTED_HEADERS = [
  "employee_number",
  "office_id",
  "salary_type",
  "monthly_base_salary",
  "hourly_wage",
  "effective_start_date",
] as const;

export type FacilityWageRow = {
  employee_number: string;
  office_id: string;
  office_name: string;
  employee_name: string;
  salary_type: "月給" | "時給";
  monthly_base_salary: number | null;
  hourly_wage: number | null;
  effective_start_date: string;
};

export type ParseResult = {
  rows: FacilityWageRow[];
  errors: string[];
  warnings: string[];
};

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function parseFacilityWageCsv(
  text: string,
  offices: { id: string; name: string }[],
  employees: { employee_number: string; name: string }[],
): ParseResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const officeById = new Map(offices.map((o) => [o.id, o.name]));
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

  const rows: FacilityWageRow[] = [];

  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [employeeNumber, officeId, salaryTypeStr, monthlyStr, hourlyStr, effectiveStartDate] = cols;

    const employeeName = employeeByNumber.get(employeeNumber);
    if (!employeeName) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})に一致する職員がいません`);
      continue;
    }
    const officeName = officeById.get(officeId);
    if (!officeName) {
      errors.push(`${lineNo}行目: office_id(${officeId})に一致する施設がありません`);
      continue;
    }
    if (salaryTypeStr !== "月給" && salaryTypeStr !== "時給") {
      errors.push(`${lineNo}行目: salary_type(${salaryTypeStr})は月給または時給で指定してください`);
      continue;
    }
    if (!DATE_RE.test(effectiveStartDate)) {
      errors.push(`${lineNo}行目: effective_start_date(${effectiveStartDate})はYYYY-MM-DD形式で指定してください`);
      continue;
    }

    let monthlyBaseSalary: number | null = null;
    let hourlyWage: number | null = null;
    if (salaryTypeStr === "月給") {
      monthlyBaseSalary = Number(monthlyStr);
      if (!Number.isInteger(monthlyBaseSalary) || monthlyBaseSalary < 0) {
        errors.push(`${lineNo}行目: monthly_base_salary(${monthlyStr})は0以上の整数で指定してください`);
        continue;
      }
      if (hourlyStr) {
        errors.push(`${lineNo}行目: salary_type=月給の場合hourly_wageは空欄にしてください`);
        continue;
      }
    } else {
      hourlyWage = Number(hourlyStr);
      if (!Number.isInteger(hourlyWage) || hourlyWage < 0) {
        errors.push(`${lineNo}行目: hourly_wage(${hourlyStr})は0以上の整数で指定してください`);
        continue;
      }
      if (monthlyStr) {
        errors.push(`${lineNo}行目: salary_type=時給の場合monthly_base_salaryは空欄にしてください`);
        continue;
      }
    }

    rows.push({
      employee_number: employeeNumber,
      office_id: officeId,
      office_name: officeName,
      employee_name: employeeName,
      salary_type: salaryTypeStr,
      monthly_base_salary: monthlyBaseSalary,
      hourly_wage: hourlyWage,
      effective_start_date: effectiveStartDate,
    });
  }

  if (rows.length === 0 && errors.length === 0) {
    warnings.push("取込対象の行がありません");
  }

  return { rows, errors, warnings };
}
