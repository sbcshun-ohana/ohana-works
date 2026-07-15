import * as XLSX from "xlsx";
import * as fs from "fs";
import * as path from "path";

const SRC = "/Users/shuntakagi/Desktop/従業員管理/労働者名簿（Ohana）.xlsx";
const DIRECTORY = path.join(__dirname, "employee_directory.json");
const OUT = path.join(__dirname, "..", "output", "tax_withholding_import.csv");

const EFFECTIVE_YM = "2026-04-01";

// 甲乙区分の例外(方針: 全員甲欄、髙木俊のみ乙欄)
const OTSU_EMPLOYEE_NUMBERS = new Set(["0006"]);

function normalizeName(s: string): string {
  return s.replace(/[\s　]+/g, "");
}

type DirEntry = { employee_number: string; name: string };
const directory = JSON.parse(fs.readFileSync(DIRECTORY, "utf-8")).rows as DirEntry[];
const byNormalizedName = new Map(directory.map((d) => [normalizeName(d.name), d]));
const numberToName = new Map(directory.map((d) => [d.employee_number, d.name]));

const wb = XLSX.readFile(SRC, { cellDates: false });
const sheet = wb.Sheets["労働者名簿"];
const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, raw: true, defval: null }) as unknown[][];

const outLines: string[] = ["employee_number,tax_column,dependent_count,submitted_flag,effective_start_year_month"];
const warnings: string[] = [];
const matched = new Set<string>();

for (let i = 2; i < rows.length; i++) {
  const r = rows[i];
  const rawName = r[1];
  const empNoInRoster = r[2];
  const resign = r[16];
  const dependentRaw = r[22];

  if (typeof rawName !== "string" || rawName.trim() === "") continue;
  if (resign !== null && resign !== undefined && String(resign).trim() !== "") continue; // 退職日ありは対象外(前回と同じ方針)

  const normalized = normalizeName(rawName);
  const entry = byNormalizedName.get(normalized);
  if (!entry) {
    warnings.push(`"${rawName}"(名簿社員番号${empNoInRoster})がDB職員一覧に見つかりません(スキップ)`);
    continue;
  }

  const dependentCount = typeof dependentRaw === "number" && dependentRaw > 0 ? dependentRaw : 0;
  const taxColumn = OTSU_EMPLOYEE_NUMBERS.has(entry.employee_number) ? "乙欄" : "甲欄";
  const submittedFlag = taxColumn === "甲欄";

  outLines.push(
    [entry.employee_number, taxColumn, dependentCount, String(submittedFlag), EFFECTIVE_YM].join(","),
  );
  matched.add(entry.employee_number);
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, outLines.join("\n") + "\n", "utf-8");

console.log(`出力先: ${OUT} (${outLines.length - 1}行)`);
console.log(`マッチ: ${matched.size} / ${directory.length}`);

const unmatched = directory.filter((d) => !matched.has(d.employee_number));
if (unmatched.length > 0) {
  console.log("\n未マッチのDB職員:");
  unmatched.forEach((d) => console.log(`  - ${d.employee_number} ${d.name}`));
}
if (warnings.length > 0) {
  console.log("\n警告:");
  warnings.forEach((w) => console.log(`  - ${w}`));
}

// 髙木俊(0006)の扶養人数と、名簿記載の哲平(子)との整合性を明示確認
const takagiShun = numberToName.get("0006");
console.log(`\n整合性確認: 0006(${takagiShun})の扶養人数 = ${
  outLines.find((l) => l.startsWith("0006,"))?.split(",")[2]
}`);
