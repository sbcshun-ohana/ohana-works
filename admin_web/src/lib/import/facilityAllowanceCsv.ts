// 施設別手当の一括CSV取込。
// CSVは1施設×1手当種別×1職員=1行(ヘッダー: employee_number,office_id,
// allowance_name,amount,effective_start_date)。

export const EXPECTED_HEADERS = [
  "employee_number",
  "office_id",
  "allowance_name",
  "amount",
  "effective_start_date",
] as const;

export type FacilityAllowanceRow = {
  employee_number: string;
  office_id: string;
  office_name: string;
  employee_name: string;
  allowance_name: string;
  amount: number;
  effective_start_date: string;
};

export type ParseResult = {
  rows: FacilityAllowanceRow[];
  errors: string[];
  warnings: string[];
};

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function parseFacilityAllowanceCsv(
  text: string,
  offices: { id: string; name: string }[],
  employees: { employee_number: string; name: string }[],
  allowanceMasters: { id: string; name: string }[],
): ParseResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const officeById = new Map(offices.map((o) => [o.id, o.name]));
  const employeeByNumber = new Map(employees.map((e) => [e.employee_number, e.name]));
  const allowanceNames = new Set(allowanceMasters.map((a) => a.name));

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

  const rows: FacilityAllowanceRow[] = [];

  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [employeeNumber, officeId, allowanceName, amountStr, effectiveStartDate] = cols;

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
    if (!allowanceNames.has(allowanceName)) {
      errors.push(`${lineNo}行目: allowance_name(${allowanceName})に一致する手当種別がありません`);
      continue;
    }
    const amount = Number(amountStr);
    if (!Number.isInteger(amount) || amount < 0) {
      errors.push(`${lineNo}行目: amount(${amountStr})は0以上の整数で指定してください`);
      continue;
    }
    if (!DATE_RE.test(effectiveStartDate)) {
      errors.push(`${lineNo}行目: effective_start_date(${effectiveStartDate})はYYYY-MM-DD形式で指定してください`);
      continue;
    }

    rows.push({
      employee_number: employeeNumber,
      office_id: officeId,
      office_name: officeName,
      employee_name: employeeName,
      allowance_name: allowanceName,
      amount,
      effective_start_date: effectiveStartDate,
    });
  }

  if (rows.length === 0 && errors.length === 0) {
    warnings.push("取込対象の行がありません");
  }

  return { rows, errors, warnings };
}
