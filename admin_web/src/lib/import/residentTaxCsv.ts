// 住民税(月額)の一括CSV取込。ヘッダー: employee_number,fiscal_year,year_month,amount
// (1職員×1年度×1ヶ月=1行のロング形式。RPC側で年度単位のmonthly_amountsへ集約する)

export const EXPECTED_HEADERS = ["employee_number", "fiscal_year", "year_month", "amount"] as const;

export type ResidentTaxRow = {
  employee_number: string;
  employee_name: string;
  fiscal_year: number;
  year_month: string;
  amount: number;
};

export type ParseResult = {
  rows: ResidentTaxRow[];
  errors: string[];
  warnings: string[];
  groupCount: number;
};

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const YM_RE = /^\d{4}-\d{2}$/;

export function parseResidentTaxCsv(
  text: string,
  employees: { employee_number: string; name: string }[],
): ParseResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const employeeByNumber = new Map(employees.map((e) => [e.employee_number, e.name]));

  const lines = text.split(/\r\n|\n|\r/).map((l) => l.trim()).filter((l) => l.length > 0);
  if (lines.length === 0) return { rows: [], errors: ["ファイルが空です"], warnings: [], groupCount: 0 };

  const header = splitCsvLine(lines[0]);
  if (header.length !== EXPECTED_HEADERS.length || !EXPECTED_HEADERS.every((h, i) => header[i] === h)) {
    errors.push(`ヘッダー行が想定形式と異なります。期待するヘッダー: ${EXPECTED_HEADERS.join(",")}`);
    return { rows: [], errors, warnings, groupCount: 0 };
  }

  const rows: ResidentTaxRow[] = [];
  const groups = new Set<string>();
  const seenMonth = new Set<string>();

  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [employeeNumber, fiscalYearStr, ym, amountStr] = cols;

    const employeeName = employeeByNumber.get(employeeNumber);
    if (!employeeName) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})に一致する職員がいません`);
      continue;
    }
    const fiscalYear = Number(fiscalYearStr);
    if (!Number.isInteger(fiscalYear)) {
      errors.push(`${lineNo}行目: fiscal_year(${fiscalYearStr})は整数で指定してください`);
      continue;
    }
    if (!YM_RE.test(ym)) {
      errors.push(`${lineNo}行目: year_month(${ym})はYYYY-MM形式で指定してください`);
      continue;
    }
    const amount = Number(amountStr);
    if (!Number.isInteger(amount) || amount < 0) {
      errors.push(`${lineNo}行目: amount(${amountStr})は0以上の整数で指定してください`);
      continue;
    }
    const monthKey = `${employeeNumber}:${ym}`;
    if (seenMonth.has(monthKey)) {
      errors.push(`${lineNo}行目: ${employeeNumber}の${ym}がファイル内で重複しています`);
      continue;
    }
    seenMonth.add(monthKey);
    groups.add(`${employeeNumber}:${fiscalYear}`);

    rows.push({ employee_number: employeeNumber, employee_name: employeeName, fiscal_year: fiscalYear, year_month: ym, amount });
  }

  if (rows.length === 0 && errors.length === 0) warnings.push("取込対象の行がありません");
  return { rows, errors, warnings, groupCount: groups.size };
}
