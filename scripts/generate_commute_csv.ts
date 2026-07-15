import * as XLSX from "xlsx";
import * as fs from "fs";
import * as path from "path";

const CHINGIN =
  "/Users/shuntakagi/Library/CloudStorage/GoogleDrive-yamatoohana.honbu@gmail.com/マイドライブ/本部管理/賃金台帳/賃金台帳（令和8年分）.xlsx";
const DIRECTORY = path.join(__dirname, "employee_directory.json");
const OUT = path.join(__dirname, "..", "output", "commute_import.csv");

const EFFECTIVE_START_DATE = "2026-04-01";

const LEDGER_OFFICE_LABEL: Record<string, string> = {
  "大和オハナ保育園": "オハナ",
  "BABY MAHALO": "マハロ",
  "Mahalo Station": "ステーション",
  "Halelea": "ハレレア",
};

const BLOCK_START: Record<string, number> = {
  "オハナ": 36,
  "マハロ": 51,
  "ハレレア": 66,
  "ステーション": 81,
};

const CONCURRENT_SHEET_NAME: Record<string, string> = {
  "髙木俊": "高木",
  "大原利奈": "大原",
  "ファンミル ミハエル": "ミハエル",
};

const NAME_ALIASES: Record<string, string> = {
  "高木俊": "髙木俊",
  "髙木哲平": "高木哲平",
  "真下瞬": "眞下瞬",
};

const SHEET_NAME_OVERRIDE: Record<string, string> = {
  "小島三保子": "小島（三）",
  "倉田恵子": "倉田（恵）",
  "小島綾": "小島（綾）",
  "倉田明美里": "倉田（明）",
  "藤﨑早苗": "藤崎",
  "佐藤響": "佐藤（旧石川）",
  "眞下瞬": "真下",
};

// データ上「非課税通勤手当」が1ヶ月のみ突発的に発生し、日額・月額とも
// 継続的な通勤費とは認められないケース(出張等の一時的な実費精算とみなす)。
// 通勤費0円(徒歩扱い)として登録する。
const TREAT_AS_ZERO: Set<string> = new Set(["0074"]);

function normalizeName(s: string): string {
  return s.replace(/[\s　]+/g, "");
}

type DirEntry = {
  employee_number: string;
  name: string;
  home_office_id: string;
  office_name: string;
  employment_type_name: string;
};
const directory = JSON.parse(fs.readFileSync(DIRECTORY, "utf-8")).rows as DirEntry[];

const wb = XLSX.readFile(CHINGIN, { cellDates: false });
const sheetNameByNormalized = new Map<string, string>();
for (const name of wb.SheetNames) {
  sheetNameByNormalized.set(normalizeName(name), name);
}

const outLines: string[] = [
  "employee_number,office_id,commute_method,calc_type,unit_price,taxable_limit,effective_start_date",
];
const summaryLines: string[] = [];
const warnings: string[] = [];

for (const emp of directory) {
  const officeLabel = LEDGER_OFFICE_LABEL[emp.office_name];
  if (!officeLabel) {
    warnings.push(`${emp.employee_number} ${emp.name}: 施設名(${emp.office_name})がマッピングにありません`);
    continue;
  }

  if (TREAT_AS_ZERO.has(emp.employee_number)) {
    outLines.push([emp.employee_number, emp.home_office_id, "", "per_day_roundtrip", 0, "", EFFECTIVE_START_DATE].join(","));
    summaryLines.push(`${emp.employee_number} ${emp.name} [${emp.employment_type_name}]: 0円(突発的な1ヶ月のみの実費精算のため通勤費なし扱い)`);
    continue;
  }

  let sheetName: string | undefined = CONCURRENT_SHEET_NAME[emp.name] ?? SHEET_NAME_OVERRIDE[normalizeName(emp.name)];
  if (!sheetName) {
    const normalized = NAME_ALIASES[normalizeName(emp.name)] ?? normalizeName(emp.name);
    for (const [key, actual] of sheetNameByNormalized.entries()) {
      if (normalized.startsWith(key) || key === normalized) {
        sheetName = actual;
        break;
      }
    }
  }
  if (!sheetName || !wb.Sheets[sheetName]) {
    warnings.push(`${emp.employee_number} ${emp.name}: 賃金台帳シートが見つかりません`);
    continue;
  }

  const sheet = wb.Sheets[sheetName];
  const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, raw: true, defval: null }) as unknown[][];
  const blockStart = BLOCK_START[officeLabel];

  let commuteAllowanceRow: unknown[] | null = null;
  let dailyCommuteRow: unknown[] | null = null;
  for (let off = 0; off < 14; off++) {
    const r = rows[blockStart + off];
    if (!r) continue;
    const label = String(r[1] ?? "");
    if (label.startsWith("非課税通勤手当")) commuteAllowanceRow = r;
    if (label === "１日交通費") dailyCommuteRow = r;
  }

  if (!commuteAllowanceRow || !dailyCommuteRow) {
    warnings.push(`${emp.employee_number} ${emp.name}: シート"${sheetName}"の${officeLabel}ブロックで通勤費関連行が見つかりません`);
    continue;
  }

  // 4月時点でまだ育休・産休等から復職しておらず4月列が空欄の職員がいる
  // (廣谷礼奈・田端美紗等)ため、4月から12月へ順に走査し、最初に実データが
  // 現れた月の値を「現在の適用額」として採用する(標準報酬月額の抽出と
  // 同じ考え方)。1月〜3月は前年度の可能性があるため対象外。
  const allowanceVals = commuteAllowanceRow.slice(2, 16);
  const dailyVals = dailyCommuteRow.slice(2, 16);
  // インデックス: 0=1月,1=2月,2=3月,3=4月,4=5月,5=6月,6=夏季賞与,7=7月,
  // 8=8月,9=9月,10=10月,11=11月,12=冬季賞与,13=12月
  const monthScanOrder = [3, 4, 5, 7, 8, 9, 10, 11, 13];

  let calcType: string | null = null;
  let unitPrice: number | null = null;
  for (const idx of monthScanOrder) {
    const dailyVal = dailyVals[idx];
    if (typeof dailyVal === "number" && dailyVal > 0) {
      calcType = "per_day_roundtrip";
      unitPrice = dailyVal;
      break;
    }
    const allowanceVal = allowanceVals[idx];
    if (typeof allowanceVal === "number" && allowanceVal > 0) {
      calcType = "fixed_monthly";
      unitPrice = allowanceVal;
      break;
    }
  }

  if (calcType === null) {
    // 全月にわたって通勤費の記載がない職員は雇用形態の一般的な計算方法に
    // 合わせつつ金額0円で登録する(徒歩通勤等)。
    calcType = emp.employment_type_name === "正社員" ? "fixed_monthly" : "per_day_roundtrip";
    unitPrice = 0;
  }

  outLines.push(
    [emp.employee_number, emp.home_office_id, "", calcType, unitPrice, "", EFFECTIVE_START_DATE].join(","),
  );
  summaryLines.push(
    `${emp.employee_number} ${emp.name} [${emp.employment_type_name}/${officeLabel}]: ${calcType} ${unitPrice}円`,
  );
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, outLines.join("\n") + "\n", "utf-8");

console.log(`出力先: ${OUT}`);
console.log(`登録対象: ${outLines.length - 1}件\n`);
console.log(summaryLines.join("\n"));
if (warnings.length > 0) {
  console.log("\n=== 警告 ===");
  console.log(warnings.join("\n"));
}
