// 通勤費(commute_masters)の一括CSV取込。
// CSVは1職員=1行(ヘッダー: employee_number,office_id,commute_method,
// calc_type,unit_price,taxable_limit,effective_start_date)。通勤費は
// 所属施設(home_office_id)からのみ支給するため、office_idは対象職員の
// home_office_idと一致している必要がある(不一致はRPC側でエラーになる)。
// calc_typeはfixed_monthly(月額固定)またはper_day_roundtrip(日額×出勤日数)。
// commute_method・taxable_limitは空欄可。

export const EXPECTED_HEADERS = [
  "employee_number",
  "office_id",
  "commute_method",
  "calc_type",
  "unit_price",
  "taxable_limit",
  "effective_start_date",
] as const;

export type CommuteRow = {
  employee_number: string;
  employee_name: string;
  office_id: string;
  office_name: string;
  commute_method: string | null;
  calc_type: "fixed_monthly" | "per_day_roundtrip";
  unit_price: number;
  taxable_limit: number | null;
  effective_start_date: string;
};

export type ParseResult = {
  rows: CommuteRow[];
  errors: string[];
  warnings: string[];
};

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function parseCommuteCsv(
  text: string,
  offices: { id: string; name: string }[],
  employees: { employee_number: string; name: string; home_office_id: string }[],
): ParseResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const officeById = new Map(offices.map((o) => [o.id, o.name]));
  const employeeByNumber = new Map(employees.map((e) => [e.employee_number, e]));

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

  const rows: CommuteRow[] = [];
  const seen = new Set<string>();

  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [employeeNumber, officeId, commuteMethod, calcTypeStr, unitPriceStr, taxableLimitStr, effectiveStartDate] =
      cols;

    const employee = employeeByNumber.get(employeeNumber);
    if (!employee) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})に一致する職員がいません`);
      continue;
    }
    if (seen.has(employeeNumber)) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})がファイル内で重複しています`);
      continue;
    }
    const officeName = officeById.get(officeId);
    if (!officeName) {
      errors.push(`${lineNo}行目: office_id(${officeId})に一致する施設がありません`);
      continue;
    }
    if (officeId !== employee.home_office_id) {
      errors.push(`${lineNo}行目: 通勤費は所属施設のみ登録できます。office_id(${officeId})が${employeeNumber}の所属施設と一致しません`);
      continue;
    }
    if (calcTypeStr !== "fixed_monthly" && calcTypeStr !== "per_day_roundtrip") {
      errors.push(`${lineNo}行目: calc_type(${calcTypeStr})はfixed_monthlyまたはper_day_roundtripで指定してください`);
      continue;
    }
    const unitPrice = Number(unitPriceStr);
    if (!Number.isInteger(unitPrice) || unitPrice < 0) {
      errors.push(`${lineNo}行目: unit_price(${unitPriceStr})は0以上の整数で指定してください`);
      continue;
    }
    let taxableLimit: number | null = null;
    if (taxableLimitStr) {
      taxableLimit = Number(taxableLimitStr);
      if (!Number.isInteger(taxableLimit) || taxableLimit < 0) {
        errors.push(`${lineNo}行目: taxable_limit(${taxableLimitStr})は0以上の整数で指定してください(空欄可)`);
        continue;
      }
    }
    if (!DATE_RE.test(effectiveStartDate)) {
      errors.push(`${lineNo}行目: effective_start_date(${effectiveStartDate})はYYYY-MM-DD形式で指定してください`);
      continue;
    }

    seen.add(employeeNumber);
    rows.push({
      employee_number: employeeNumber,
      employee_name: employee.name,
      office_id: officeId,
      office_name: officeName,
      commute_method: commuteMethod || null,
      calc_type: calcTypeStr,
      unit_price: unitPrice,
      taxable_limit: taxableLimit,
      effective_start_date: effectiveStartDate,
    });
  }

  if (rows.length === 0 && errors.length === 0) {
    warnings.push("取込対象の行がありません");
  }

  return { rows, errors, warnings };
}
