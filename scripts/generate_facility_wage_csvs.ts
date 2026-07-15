import * as XLSX from "xlsx";
import * as fs from "fs";
import * as path from "path";

const NENJI =
  "/Users/shuntakagi/Library/CloudStorage/GoogleDrive-yamatoohana.honbu@gmail.com/マイドライブ/本部管理/人事書類/年次更新書類/年次更新（2026年度）Ohana.xlsx";
const CHINGIN =
  "/Users/shuntakagi/Library/CloudStorage/GoogleDrive-yamatoohana.honbu@gmail.com/マイドライブ/本部管理/賃金台帳/賃金台帳（令和8年分）.xlsx";
const DIRECTORY = path.join(__dirname, "employee_directory.json");
const OUT_WAGE = path.join(__dirname, "..", "output", "facility_wages_import.csv");
const OUT_ALLOWANCE = path.join(__dirname, "..", "output", "facility_allowances_import.csv");

const OFFICE_ID: Record<string, string> = {
  "大和オハナ保育園": "9503dfbd-6cdc-424c-aa3e-ac18441478ba",
  "BABY MAHALO": "f693e200-5312-44be-9634-6a8c24bc88da",
  "Mahalo Station": "493d0fce-bfb7-403c-9f93-12f3cb63aeb6",
  "Halelea": "9296067b-8db3-438e-9d1a-c9d13d1d60be",
};
// 賃金台帳シートの見出し語 → office_id
const LEDGER_OFFICE_ID: Record<string, string> = {
  "オハナ": OFFICE_ID["大和オハナ保育園"],
  "マハロ": OFFICE_ID["BABY MAHALO"],
  "ハレレア": OFFICE_ID["Halelea"],
  "ステーション": OFFICE_ID["Mahalo Station"],
};

const EFFECTIVE_START_DATE = "2026-04-01";

// 髙木俊・大原利奈・VAN MIL MICHAELは施設別内訳(賃金台帳)を使う。氏名(DB表記, 空白無し)→賃金台帳シート名。
const CONCURRENT_EMPLOYEES: Record<string, string> = {
  "髙木俊": "高木",
  "大原利奈": "大原",
  "ファンミル ミハエル": "ミハエル",
};

function normalizeName(s: string): string {
  return s.replace(/[\s　]+/g, "");
}

// 年次更新シートの表記とDB上の表記で異体字・別名になっている職員のエイリアス。
const NAME_ALIASES: Record<string, string> = {
  "VANMILMICHAEL": "ファンミルミハエル",
  "高木俊": "髙木俊", // 年次更新は「高木」、DB/労働者名簿は「髙木」
  "髙木哲平": "高木哲平", // 逆に息子の方はDBが「高木」表記
};

type DirEntry = { employee_number: string; name: string; home_office_id: string; office_name: string };
const directory = JSON.parse(fs.readFileSync(DIRECTORY, "utf-8")).rows as DirEntry[];
const byNormalizedName = new Map(directory.map((d) => [normalizeName(d.name), d]));

const wageLines: string[] = ["employee_number,office_id,salary_type,monthly_base_salary,hourly_wage,effective_start_date"];
const allowanceLines: string[] = ["employee_number,office_id,allowance_name,amount,effective_start_date"];
const warnings: string[] = [];
const matchedNumbers = new Set<string>();

// ---- 1. 賃金台帳から兼務3名の施設別基本給(12月時点)を取得 ----
const wbChingin = XLSX.readFile(CHINGIN, { cellDates: false });
for (const [dbName, sheetName] of Object.entries(CONCURRENT_EMPLOYEES)) {
  const entry = byNormalizedName.get(normalizeName(dbName));
  if (!entry) {
    warnings.push(`兼務職員 ${dbName} がDB職員一覧に見つかりません`);
    continue;
  }
  const sheet = wbChingin.Sheets[sheetName];
  if (!sheet) {
    warnings.push(`賃金台帳に ${sheetName} シートが見つかりません`);
    continue;
  }
  const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, raw: true, defval: null }) as unknown[][];
  for (const r of rows) {
    const label = r[0];
    if (typeof label !== "string") continue;
    const m = label.match(/^(オハナ|マハロ|ハレレア|ステーション)給料・手当等内訳$/);
    if (!m) continue;
    const subLabel = r[1];
    if (subLabel !== `基本給（${m[1]}）`) continue;
    const decemberValue = r[15]; // 12月列
    const officeId = LEDGER_OFFICE_ID[m[1]];
    if (typeof decemberValue === "number" && decemberValue > 0) {
      wageLines.push([entry.employee_number, officeId, "月給", decemberValue, "", EFFECTIVE_START_DATE].join(","));
    }
  }
  matchedNumbers.add(entry.employee_number);
}

// ---- 2. 年次更新 一覧シートから残り49名の基本給・手当 ----
const wbNenji = XLSX.readFile(NENJI, { cellDates: false });
const sheetNenji = wbNenji.Sheets["一覧"];
const rowsNenji = XLSX.utils.sheet_to_json(sheetNenji, { header: 1, raw: true, defval: null }) as unknown[][];

for (let i = 1; i < rowsNenji.length; i++) {
  const r = rowsNenji[i];
  const rawName = r[0];
  if (typeof rawName !== "string" || rawName.trim() === "") continue;
  if (rawName.includes("（前）")) continue; // 重複契約を無視

  const salaryTypeLabel = r[11]; // "月給" | "時給"
  const baseSalary = r[12];
  const positionAllowance = r[13];
  const qualificationAllowance = r[14];
  const dutyAllowance = r[15];

  let normalized = normalizeName(rawName);
  normalized = NAME_ALIASES[normalized] ?? normalized;
  const entry = byNormalizedName.get(normalized);
  if (!entry) {
    warnings.push(`年次更新一覧の職員 "${rawName}" がDB職員一覧に見つかりません(スキップ)`);
    continue;
  }

  const isConcurrent = Object.values(CONCURRENT_EMPLOYEES).length > 0 &&
    Object.keys(CONCURRENT_EMPLOYEES).some((n) => normalizeName(n) === normalized);

  if (!isConcurrent) {
    if (salaryTypeLabel !== "月給" && salaryTypeLabel !== "時給") {
      warnings.push(`${rawName}: 賃金形態(${salaryTypeLabel})が不明のためスキップ`);
      continue;
    }
    if (typeof baseSalary !== "number" || baseSalary <= 0) {
      warnings.push(`${rawName}: 基本給が数値でないためスキップ(${baseSalary})`);
      continue;
    }
    const officeId = entry.home_office_id;
    if (salaryTypeLabel === "月給") {
      wageLines.push([entry.employee_number, officeId, "月給", baseSalary, "", EFFECTIVE_START_DATE].join(","));
    } else {
      wageLines.push([entry.employee_number, officeId, "時給", "", baseSalary, EFFECTIVE_START_DATE].join(","));
    }
    matchedNumbers.add(entry.employee_number);
  }

  // 役職手当・資格手当・職務手当(兼務3名も含め、home_office_id側に登録する)
  const officeIdForAllowance = entry.home_office_id;
  if (typeof positionAllowance === "number" && positionAllowance > 0) {
    allowanceLines.push(
      [entry.employee_number, officeIdForAllowance, "役職手当", positionAllowance, EFFECTIVE_START_DATE].join(","),
    );
  }
  if (typeof qualificationAllowance === "number" && qualificationAllowance > 0) {
    allowanceLines.push(
      [entry.employee_number, officeIdForAllowance, "資格手当", qualificationAllowance, EFFECTIVE_START_DATE].join(","),
    );
  }
  if (typeof dutyAllowance === "number" && dutyAllowance > 0) {
    allowanceLines.push(
      [entry.employee_number, officeIdForAllowance, "職務手当", dutyAllowance, EFFECTIVE_START_DATE].join(","),
    );
  }
}

fs.mkdirSync(path.dirname(OUT_WAGE), { recursive: true });
fs.writeFileSync(OUT_WAGE, wageLines.join("\n") + "\n", "utf-8");
fs.writeFileSync(OUT_ALLOWANCE, allowanceLines.join("\n") + "\n", "utf-8");

console.log(`基本給CSV: ${OUT_WAGE} (${wageLines.length - 1}行)`);
console.log(`手当CSV: ${OUT_ALLOWANCE} (${allowanceLines.length - 1}行)`);
console.log(`マッチした職員番号: ${matchedNumbers.size} / 52`);

const unmatched = directory.filter((d) => !matchedNumbers.has(d.employee_number));
if (unmatched.length > 0) {
  console.log("\n未マッチの職員(基本給CSVに行が無い):");
  unmatched.forEach((d) => console.log(`  - ${d.employee_number} ${d.name}`));
}

if (warnings.length > 0) {
  console.log("\n警告:");
  warnings.forEach((w) => console.log(`  - ${w}`));
}
