import * as XLSX from "xlsx";
import * as fs from "fs";
import * as path from "path";

const SRC = "/Users/shuntakagi/Desktop/従業員管理/労働者名簿（Ohana）.xlsx";
const OUT = path.join(__dirname, "..", "output", "employees_import.csv");

const OFFICE_ID: Record<string, string> = {
  "大和オハナ保育園": "9503dfbd-6cdc-424c-aa3e-ac18441478ba",
  "BABY MAHALO": "f693e200-5312-44be-9634-6a8c24bc88da",
  "Mahalo Station": "493d0fce-bfb7-403c-9f93-12f3cb63aeb6",
  "MahaloStation": "493d0fce-bfb7-403c-9f93-12f3cb63aeb6",
  "Halelea": "9296067b-8db3-438e-9d1a-c9d13d1d60be",
};

// 入江千華(No.39)の社員番号は0144が田端美紗(No.31)と重複していた誤記。
// 周辺の番号列(...0155,0156,0157,[欠番],0159,0160...)から0158が本来の番号と判断し修正する。
const EMPLOYEE_NUMBER_OVERRIDES: Record<string, string> = {
  "入江　千華": "0158",
};

// 佐藤　響(0149)のふりがな列が元データ上「いしかわ　ひびき」となっており氏名と
// 不整合(別職員の値が混入していた)。正しい読みは「さとう　ひびき」と本人確認済み。
const KANA_OVERRIDES: Record<string, string> = {
  "佐藤　響": "さとう　ひびき",
};

function excelSerialToYmd(serial: number): string {
  // Excel(Windows)のシリアル値は1899-12-30を起点とする。
  const epoch = Date.UTC(1899, 11, 30);
  const ms = epoch + serial * 86400000;
  const d = new Date(ms);
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function splitName(raw: string): [string, string] {
  const parts = raw.trim().split(/[\s　]+/).filter(Boolean);
  if (parts.length === 0) return ["", ""];
  if (parts.length === 1) return [parts[0], ""];
  return [parts[0], parts.slice(1).join(" ")];
}

const wb = XLSX.readFile(SRC, { cellDates: false });
const sheet = wb.Sheets["労働者名簿"];
const rows = XLSX.utils.sheet_to_json(sheet, { header: 1, raw: true, defval: null }) as unknown[][];

const header = [
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
];

const outLines: string[] = [header.join(",")];
const skippedOnLeave: string[] = [];
const errors: string[] = [];
const seenNumbers = new Set<string>();

for (let i = 2; i < rows.length; i++) {
  const r = rows[i];
  const name = String(r[1] ?? "").trim();
  let empNo = String(r[2] ?? "").trim();
  const kana = String(r[3] ?? "").trim();
  const office = String(r[5] ?? "").trim();
  const birth = r[6];
  const empType = String(r[12] ?? "").trim();
  const hire = r[14];
  const resign = r[16];

  if (resign !== null && resign !== undefined && String(resign).trim() !== "") {
    skippedOnLeave.push(`${name}(${empNo}): 退職日欄="${resign}"`);
    continue;
  }

  if (EMPLOYEE_NUMBER_OVERRIDES[name]) {
    empNo = EMPLOYEE_NUMBER_OVERRIDES[name];
  }

  if (seenNumbers.has(empNo)) {
    errors.push(`${name}: employee_number(${empNo})が重複しています`);
    continue;
  }
  seenNumbers.add(empNo);

  const officeId = OFFICE_ID[office];
  if (!officeId) {
    errors.push(`${name}: 施設名(${office})がマッピングにありません`);
    continue;
  }
  if (empType !== "正社員" && empType !== "パート") {
    errors.push(`${name}: 雇用形態(${empType})が想定外です`);
    continue;
  }
  if (typeof birth !== "number" || typeof hire !== "number") {
    errors.push(`${name}: 生年月日または雇入日が数値(シリアル値)ではありません`);
    continue;
  }

  const [lastName, firstName] = splitName(name);
  const [lastKana, firstKana] = splitName(KANA_OVERRIDES[name] ?? kana);
  const fullTimeFlag = empType === "正社員";
  // employment_typesマスタは「パートタイム」表記(ユーザー指示によりリネーム済み)。
  const employmentTypeLabel = empType === "パート" ? "パートタイム" : empType;

  const row = [
    empNo,
    lastName,
    firstName,
    lastKana,
    firstKana,
    excelSerialToYmd(birth),
    excelSerialToYmd(hire),
    officeId,
    employmentTypeLabel,
    String(fullTimeFlag),
    "0",
  ];
  outLines.push(row.join(","));
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, outLines.join("\n") + "\n", "utf-8");

console.log(`出力先: ${OUT}`);
console.log(`取込対象: ${outLines.length - 1}件`);
if (skippedOnLeave.length > 0) {
  console.log(`\n退職日欄に値があり除外(育休/産休など、要個別確認):`);
  skippedOnLeave.forEach((s) => console.log(`  - ${s}`));
}
if (errors.length > 0) {
  console.log(`\nエラー:`);
  errors.forEach((e) => console.log(`  - ${e}`));
}
