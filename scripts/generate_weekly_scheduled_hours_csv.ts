import * as XLSX from "xlsx";
import * as fs from "fs";
import * as path from "path";

const NENJI =
  "/Users/shuntakagi/Library/CloudStorage/GoogleDrive-yamatoohana.honbu@gmail.com/マイドライブ/本部管理/人事書類/年次更新書類/年次更新（2026年度）Ohana.xlsx";
const DIRECTORY = path.join(__dirname, "employee_directory.json");
const OUT = path.join(__dirname, "..", "output", "weekly_scheduled_hours_import.csv");

const EFFECTIVE_START_DATE = "2026-04-01";

// 賃金台帳・通勤費抽出スクリプトと同じ、DB表記→年次更新表記のエイリアス。
const NAME_ALIASES: Record<string, string> = {
  "VANMILMICHAEL": "ファンミルミハエル",
  "高木俊": "髙木俊",
  "髙木哲平": "高木哲平",
};

function normalizeName(s: string): string {
  return s.replace(/[\s　]+/g, "");
}

type DirEntry = { employee_number: string; name: string };
const directory = JSON.parse(fs.readFileSync(DIRECTORY, "utf-8")).rows as DirEntry[];
const byNormalizedName = new Map(directory.map((d) => [normalizeName(d.name), d]));

const wb = XLSX.readFile(NENJI, { cellDates: false });
const sheet = wb.Sheets["一覧"];
const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, raw: true, defval: null }) as unknown[][];

const outLines: string[] = ["employee_number,weekly_hours,effective_start_date"];
const warnings: string[] = [];
const matched = new Set<string>();

for (let i = 1; i < rows.length; i++) {
  const r = rows[i];
  const rawName = r[0];
  if (typeof rawName !== "string" || rawName.trim() === "") continue;
  if (rawName.includes("（前）")) continue; // 重複契約(旧契約)を無視

  const weeklyHours = r[9];

  const normalized = NAME_ALIASES[normalizeName(rawName)] ?? normalizeName(rawName);
  const entry = byNormalizedName.get(normalized);
  if (!entry) {
    warnings.push(`年次更新一覧の職員 "${rawName}" がDB職員一覧に見つかりません(スキップ)`);
    continue;
  }
  if (matched.has(entry.employee_number)) {
    warnings.push(`${entry.employee_number} ${entry.name}: 年次更新一覧で複数行にマッチしました(スキップ、後勝ちの可能性あり要確認)`);
    continue;
  }

  if (typeof weeklyHours !== "number" || weeklyHours <= 0) {
    warnings.push(`${entry.employee_number} ${entry.name}: 週所定労働時間が数値でないためスキップ(${weeklyHours})`);
    continue;
  }

  outLines.push([entry.employee_number, weeklyHours, EFFECTIVE_START_DATE].join(","));
  matched.add(entry.employee_number);
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, outLines.join("\n") + "\n", "utf-8");

console.log(`出力先: ${OUT}`);
console.log(`登録対象: ${outLines.length - 1}件 / ${directory.length}名`);

const unmatched = directory.filter((d) => !matched.has(d.employee_number));
if (unmatched.length > 0) {
  console.log("\n未マッチのDB職員(CSVに行が無い):");
  unmatched.forEach((d) => console.log(`  - ${d.employee_number} ${d.name}`));
}
if (warnings.length > 0) {
  console.log("\n警告:");
  warnings.forEach((w) => console.log(`  - ${w}`));
}
