// 20.2 職員マスタCSV取込。
// CSVは1職員=1行(ヘッダー: employee_number,last_name,first_name,last_name_kana,
// first_name_kana,birth_date,hire_date,office_id,employment_type,full_time_flag,
// base_salary)で受け付ける。office_id/employment_typeはDB保存前にoffices/
// employment_typesマスタと突き合わせて検証し、employment_typeは名称からIDへ解決する。

export const EXPECTED_HEADERS = [
  "employee_number",
  "last_name",
  "first_name",
  "last_name_kana",
  "first_name_kana",
  "birth_date",
  "hire_date",
  "office_id",
  "employment_type",
  "full_time_flag",
  "base_salary",
] as const;

export type EmployeeImportRow = {
  employee_number: string;
  name: string;
  name_kana: string | null;
  birth_date: string | null;
  hire_date: string;
  office_id: string;
  office_name: string;
  employment_type_id: string;
  employment_type_name: string;
  full_time_flag: boolean;
  base_salary: number | null;
};

export type ParseResult = {
  rows: EmployeeImportRow[];
  errors: string[];
  warnings: string[];
};

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function parseEmployeeMasterCsv(
  text: string,
  offices: { id: string; name: string }[],
  employmentTypes: { id: string; name: string }[],
): ParseResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const officeById = new Map(offices.map((o) => [o.id, o.name]));
  const employmentTypeByName = new Map(employmentTypes.map((t) => [t.name, t.id]));

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

  const rows: EmployeeImportRow[] = [];
  const seenEmployeeNumbers = new Set<string>();

  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [
      employeeNumber,
      lastName,
      firstName,
      lastNameKana,
      firstNameKana,
      birthDateStr,
      hireDateStr,
      officeId,
      employmentTypeName,
      fullTimeFlagStr,
      baseSalaryStr,
    ] = cols;

    if (!employeeNumber) {
      errors.push(`${lineNo}行目: employee_numberは必須です`);
      continue;
    }
    if (seenEmployeeNumbers.has(employeeNumber)) {
      errors.push(`${lineNo}行目: employee_number(${employeeNumber})がファイル内で重複しています`);
      continue;
    }
    if (!lastName || !firstName) {
      errors.push(`${lineNo}行目: last_name/first_nameは必須です`);
      continue;
    }
    if (!hireDateStr) {
      errors.push(`${lineNo}行目: hire_dateは必須です`);
      continue;
    }
    if (!DATE_RE.test(hireDateStr)) {
      errors.push(`${lineNo}行目: hire_date(${hireDateStr})はYYYY-MM-DD形式で指定してください`);
      continue;
    }
    if (birthDateStr && !DATE_RE.test(birthDateStr)) {
      errors.push(`${lineNo}行目: birth_date(${birthDateStr})はYYYY-MM-DD形式で指定してください(空欄可)`);
      continue;
    }
    if (!officeId) {
      errors.push(`${lineNo}行目: office_idは必須です`);
      continue;
    }
    const officeName = officeById.get(officeId);
    if (!officeName) {
      errors.push(`${lineNo}行目: office_id(${officeId})に一致する施設がありません`);
      continue;
    }
    if (!employmentTypeName) {
      errors.push(`${lineNo}行目: employment_typeは必須です`);
      continue;
    }
    const employmentTypeId = employmentTypeByName.get(employmentTypeName);
    if (!employmentTypeId) {
      errors.push(
        `${lineNo}行目: employment_type(${employmentTypeName})に一致する雇用形態がありません。` +
          `利用可能な雇用形態: ${employmentTypes.map((t) => t.name).join("、")}`,
      );
      continue;
    }
    const fullTimeFlagLower = fullTimeFlagStr.toLowerCase();
    if (fullTimeFlagLower !== "true" && fullTimeFlagLower !== "false") {
      errors.push(`${lineNo}行目: full_time_flag(${fullTimeFlagStr})はtrueまたはfalseで指定してください`);
      continue;
    }
    const fullTimeFlag = fullTimeFlagLower === "true";

    let baseSalary: number | null = null;
    if (baseSalaryStr) {
      baseSalary = Number(baseSalaryStr);
      if (!Number.isFinite(baseSalary) || baseSalary < 0) {
        errors.push(`${lineNo}行目: base_salary(${baseSalaryStr})は0以上の数値で指定してください(空欄可)`);
        continue;
      }
    }

    seenEmployeeNumbers.add(employeeNumber);
    rows.push({
      employee_number: employeeNumber,
      name: `${lastName}${firstName}`,
      name_kana: lastNameKana || firstNameKana ? `${lastNameKana}${firstNameKana}` : null,
      birth_date: birthDateStr || null,
      hire_date: hireDateStr,
      office_id: officeId,
      office_name: officeName,
      employment_type_id: employmentTypeId,
      employment_type_name: employmentTypeName,
      full_time_flag: fullTimeFlag,
      base_salary: baseSalary,
    });
  }

  if (rows.length === 0 && errors.length === 0) {
    warnings.push("取込対象の行がありません");
  }

  return { rows, errors, warnings };
}
