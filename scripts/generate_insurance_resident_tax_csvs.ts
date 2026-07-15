import * as XLSX from "xlsx";
import * as fs from "fs";
import * as path from "path";

const CHINGIN =
  "/Users/shuntakagi/Library/CloudStorage/GoogleDrive-yamatoohana.honbu@gmail.com/マイドライブ/本部管理/賃金台帳/賃金台帳（令和8年分）.xlsx";
const DIRECTORY = path.join(__dirname, "employee_directory.json");
const OUT_SMR = path.join(__dirname, "..", "output", "standard_monthly_remunerations_import.csv");
const OUT_ENROLL = path.join(__dirname, "..", "output", "insurance_enrollments_import.csv");
const OUT_RESIDENT = path.join(__dirname, "..", "output", "resident_taxes_import.csv");

const NON_EMPLOYEE_SHEETS = new Set([
  "OHANA支給額一覧", "MAHALO支給額一覧", "Halelea支給額一覧", "Station支給額一覧",
  "預かり所得税・法定福利費", "労働保険計算用", "常勤・非常勤別勤務",
]);

const EFFECTIVE_YM = "2026-04-01";
const PENSION_CAP = 650000; // 厚生年金の標準報酬月額上限(32等級)
// header: [項目名,null,1月,2月,3月,4月,5月,6月,夏季賞与,7月,8月,9月,10月,11月,冬季賞与,12月,合計]
const MONTH_COLS = [5, 6, 7, 9, 10, 11, 12, 13, 15]; // 4月始まりで年度内を順に走査(賞与列は除く)

const NAME_ALIASES: Record<string, string> = {
  "高木俊": "髙木俊",
  "髙木哲平": "高木哲平",
  "真下瞬": "眞下瞬",
};

function normalizeName(s: string): string {
  return s.replace(/[\s　]+/g, "");
}

type DirEntry = { employee_number: string; name: string; hire_date: string };
const directory = JSON.parse(fs.readFileSync(DIRECTORY, "utf-8")).rows as DirEntry[];
const byNormalizedName = new Map(directory.map((d) => [normalizeName(d.name), d]));

const smrLines: string[] = [
  "employee_number,health_insurance_amount,health_insurance_grade,pension_amount,pension_grade,effective_year_month,revision_reason",
];
const enrollLines: string[] = [
  "employee_number,insurance_type,enrolled,acquisition_date,loss_date",
];
const residentLines: string[] = [
  "employee_number,fiscal_year,year_month,amount",
];
const warnings: string[] = [];
const matched = new Set<string>();

const wb = XLSX.readFile(CHINGIN, { cellDates: false });

for (const sheetName of wb.SheetNames) {
  if (NON_EMPLOYEE_SHEETS.has(sheetName) || sheetName.startsWith("予備")) continue;
  const sheet = wb.Sheets[sheetName];
  const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, raw: true, defval: null }) as unknown[][];
  const nameCell = rows[12]?.[1];
  if (typeof nameCell !== "string" || nameCell.trim() === "") continue;

  let normalized = normalizeName(nameCell);
  normalized = NAME_ALIASES[normalized] ?? normalized;
  const entry = byNormalizedName.get(normalized);
  if (!entry) {
    warnings.push(`シート"${sheetName}"(氏名:${nameCell})がDB職員一覧に見つかりません(スキップ)`);
    continue;
  }
  if (matched.has(entry.employee_number)) {
    warnings.push(`シート"${sheetName}"(氏名:${nameCell})は既にマッチ済みの職員番号${entry.employee_number}と重複(スキップ)`);
    continue;
  }

  // --- 標準報酬月額: 4月から順に走査し、社会保険適用有無="有"かつ金額ありの最初の月を採用 ---
  // (4月時点で未加入・欄が空欄の職員が一定数おり、加入開始が数ヶ月後にずれるケースがあるため)
  const smrRow = rows[117]; // ["控除額","標準報酬月額", ...]
  const shakaiHokenRow = rows[3]; // 社会保険適用有無(健保+厚生年金)
  const koyouHokenRow = rows[5]; // 雇用保険適用有無

  let healthAmount: number | null = null;
  let usedMonthCol: number | null = null;
  for (const col of MONTH_COLS) {
    const smrVal = smrRow?.[col];
    if (shakaiHokenRow?.[col] === "有" && typeof smrVal === "number" && smrVal > 0) {
      healthAmount = smrVal;
      usedMonthCol = col;
      break;
    }
  }

  if (healthAmount !== null) {
    const pensionAmount = Math.min(healthAmount, PENSION_CAP);
    smrLines.push(
      [entry.employee_number, healthAmount, 1, pensionAmount, 1, EFFECTIVE_YM, "資格取得時決定"].join(","),
    );
  } else {
    warnings.push(`${entry.employee_number} ${entry.name}: 社会保険加入かつ標準報酬月額ありの月が見つかりません(社会保険未加入の可能性、スキップ)`);
  }

  // --- 保険加入状況: 標準報酬月額と同じ月(無ければ4月時点)の適用有無を採用 ---
  const enrollCol = usedMonthCol ?? MONTH_COLS[0];
  const enrolledHealth = shakaiHokenRow?.[enrollCol] === "有";
  const enrolledPension = shakaiHokenRow?.[enrollCol] === "有";
  const enrolledEmployment = koyouHokenRow?.[enrollCol] === "有";

  enrollLines.push([entry.employee_number, "健康保険", String(enrolledHealth), entry.hire_date, ""].join(","));
  enrollLines.push([entry.employee_number, "厚生年金", String(enrolledPension), entry.hire_date, ""].join(","));
  enrollLines.push([entry.employee_number, "雇用保険", String(enrolledEmployment), entry.hire_date, ""].join(","));

  // --- 住民税(月額、令和8年1-5月=fiscal_year2025の一部、6-12月=fiscal_year2026) ---
  const residentRow = rows[125]; // [null,"住民税", 1月...12月, 合計]
  const monthCols = [2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 15]; // 1,2,3,4,5,6,7,8,9,10,11,12月(夏季賞与列8/冬季賞与列14を除く)
  const monthKeys2026 = ["01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12"];

  monthCols.forEach((col, idx) => {
    const v = residentRow?.[col];
    if (typeof v === "number" && v > 0) {
      const ym = `2026-${monthKeys2026[idx]}`;
      const monthNum = idx + 1;
      const fiscalYear = monthNum <= 5 ? 2025 : 2026;
      residentLines.push([entry.employee_number, fiscalYear, ym, v].join(","));
    }
  });

  matched.add(entry.employee_number);
}

fs.mkdirSync(path.dirname(OUT_SMR), { recursive: true });
fs.writeFileSync(OUT_SMR, smrLines.join("\n") + "\n", "utf-8");
fs.writeFileSync(OUT_ENROLL, enrollLines.join("\n") + "\n", "utf-8");
fs.writeFileSync(OUT_RESIDENT, residentLines.join("\n") + "\n", "utf-8");

console.log(`標準報酬月額CSV: ${OUT_SMR} (${smrLines.length - 1}行)`);
console.log(`保険加入CSV: ${OUT_ENROLL} (${enrollLines.length - 1}行)`);
console.log(`住民税CSV: ${OUT_RESIDENT} (${residentLines.length - 1}行)`);
console.log(`マッチした職員: ${matched.size} / ${directory.length}`);

const unmatched = directory.filter((d) => !matched.has(d.employee_number));
if (unmatched.length > 0) {
  console.log("\n未マッチのDB職員:");
  unmatched.forEach((d) => console.log(`  - ${d.employee_number} ${d.name}`));
}
if (warnings.length > 0) {
  console.log("\n警告:");
  warnings.forEach((w) => console.log(`  - ${w}`));
}
