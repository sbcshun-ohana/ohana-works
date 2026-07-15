#!/usr/bin/env -S npx tsx
// 20.2 源泉所得税額表(月額表)CSV生成スクリプト。
//
// 国税庁「給与所得の源泉徴収税額表(令和8年分)」の月額表Excel(.xls、甲欄・乙欄)を
// 取得し、admin_web /settings 画面が読み込めるwide形式CSV
// (wage_lower_bound,wage_upper_bound,kou_dep0..kou_dep7plus,otsu_amount) に変換する。
//
// 実行方法: cd scripts && npm install && npx tsx generate_withholding_tax_csv.ts
// (xlsxパッケージはscripts/package.jsonで隔離しており、admin_webの本番依存には含めない。
//  国税庁の公式ドメインから直接取得したファイルのみを読み込む用途に限定しているため、
//  xlsxパッケージの既知の脆弱性(未信頼ファイルの解析時のProtoype Pollution/ReDoS)の
//  リスクは限定的と判断している)。
//
// 出典(必ず実行時に最新版を確認すること):
//   https://www.nta.go.jp/publication/pamph/gensen/zeigakuhyo2026/01.htm
//   月額表Excel: https://www.nta.go.jp/publication/pamph/gensen/zeigakuhyo2026/data/01-07.xls
//
// 【重要な制約】
// - 01-07.xls は単一シート「月額表」で完結している(同ページの08-14.xls/pdfは
//   月額表の続きではなく別表(日額表)のため対象外)。
// - 月額表は約737,000円までは固定金額の早見表だが、それを超える帯(740,000円〜)は
//   「基準額を超える金額の◯％に相当する金額を加算した金額」という計算式(累進)に
//   切り替わる。本スクリプトは固定金額のセルが揃っている行のみを抽出し、
//   計算式の行は自動的に対象外となる(型が数値でないため)。33章準拠で自動確定はしない。
// - 105,000円未満の帯は乙欄が「給与の3.063％」という計算式のため対象外。
// - 最終行(737,000円以上)はwage_upper_boundを空欄(上限なし)として出力する安全側の
//   簡易対応。740,000円を大きく超える給与については本来の計算式と乖離するため、
//   該当者がいる場合は国税庁の資料に基づき別途確認・手動調整すること。

import * as XLSX from "xlsx";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const SOURCE_XLS_URL =
  "https://www.nta.go.jp/publication/pamph/gensen/zeigakuhyo2026/data/01-07.xls";
const OUTPUT_PATH = join(process.cwd(), "..", "output", "withholding_tax_2026.csv");
const EXPECTED_SHEET_NAME = "月額表";

const CSV_HEADER = [
  "wage_lower_bound",
  "wage_upper_bound",
  "kou_dep0",
  "kou_dep1",
  "kou_dep2",
  "kou_dep3",
  "kou_dep4",
  "kou_dep5",
  "kou_dep6",
  "kou_dep7plus",
  "otsu_amount",
].join(",");

type Row = {
  wageLowerBound: number;
  wageUpperBound: number;
  kouAmounts: number[]; // 8要素(扶養0〜7人)
  otsuAmount: number;
};

async function downloadXls(url: string): Promise<Buffer> {
  console.log(`ダウンロード中: ${url}`);
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Excelファイルの取得に失敗しました: ${res.status} ${res.statusText}`);
  }
  const arrayBuffer = await res.arrayBuffer();
  return Buffer.from(arrayBuffer);
}

function isNumber(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v);
}

function parseRows(buffer: Buffer): { rows: Row[]; skippedCount: number } {
  const workbook = XLSX.read(buffer, { type: "buffer" });
  const sheetName = workbook.SheetNames.includes(EXPECTED_SHEET_NAME)
    ? EXPECTED_SHEET_NAME
    : workbook.SheetNames[0];
  if (sheetName !== EXPECTED_SHEET_NAME) {
    console.warn(`⚠ シート名が想定(${EXPECTED_SHEET_NAME})と異なります: ${sheetName}`);
  }
  const sheet = workbook.Sheets[sheetName];
  const raw = XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, raw: true });

  const rows: Row[] = [];
  let skippedCount = 0;

  for (const r of raw) {
    // 想定するデータ行の形: [連番, 賃金下限, 賃金上限, 甲0人..甲7人(8列), 乙欄] = 12列。
    // 見出し・空行・「105,000円未満」特殊行・計算式行(累進帯)は数値型でないため自然に除外される。
    if (
      Array.isArray(r) &&
      r.length >= 12 &&
      isNumber(r[0]) &&
      isNumber(r[1]) &&
      isNumber(r[2]) &&
      r.slice(3, 11).every(isNumber) &&
      isNumber(r[11])
    ) {
      const wageLowerBound = r[1] as number;
      const wageUpperBound = r[2] as number;
      if (wageUpperBound <= wageLowerBound) {
        skippedCount++;
        continue;
      }
      rows.push({
        wageLowerBound,
        wageUpperBound,
        kouAmounts: (r.slice(3, 11) as number[]),
        otsuAmount: r[11] as number,
      });
    } else if (Array.isArray(r) && r.some((c) => c !== null && c !== undefined && c !== "")) {
      skippedCount++;
    }
  }

  return { rows, skippedCount };
}

function toCsv(rows: Row[]): string {
  const sorted = [...rows].sort((a, b) => a.wageLowerBound - b.wageLowerBound);
  const lines = [CSV_HEADER];
  sorted.forEach((r, i) => {
    const isLast = i === sorted.length - 1;
    const upper = isLast ? "" : String(r.wageUpperBound);
    lines.push([r.wageLowerBound, upper, ...r.kouAmounts, r.otsuAmount].join(","));
  });
  return lines.join("\n") + "\n";
}

function reportGaps(rows: Row[]) {
  const sorted = [...rows].sort((a, b) => a.wageLowerBound - b.wageLowerBound);
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].wageLowerBound !== sorted[i - 1].wageUpperBound) {
      console.warn(
        `⚠ 賃金帯の不連続: ${sorted[i - 1].wageUpperBound}円 と ${sorted[i].wageLowerBound}円 の間`,
      );
    }
  }
}

async function main() {
  const buffer = await downloadXls(SOURCE_XLS_URL);
  console.log(`Excel取得完了 (${buffer.length.toLocaleString()} bytes)`);

  const { rows, skippedCount } = parseRows(buffer);

  if (rows.length === 0) {
    throw new Error("月額表の行を1件も抽出できませんでした。Excelの構成が変更された可能性があります。");
  }

  reportGaps(rows);

  mkdirSync(join(process.cwd(), "..", "output"), { recursive: true });
  writeFileSync(OUTPUT_PATH, toCsv(rows));

  console.log("");
  console.log(`✓ 抽出行数: ${rows.length}件(固定金額の賃金帯)`);
  console.log(`✓ スキップ行数: ${skippedCount}件(見出し・空行・計算式による累進帯・備考等)`);
  console.log(`✓ 出力先: ${OUTPUT_PATH}`);
  console.log("");
  console.log("⚠ 105,000円未満の帯は対象外です(乙欄が「給与の3.063％」という");
  console.log("  計算式のため固定値で表現できません。低賃金の乙欄該当者がいる場合は");
  console.log("  国税庁資料の計算式に基づき別途手当てしてください)。");
  console.log("⚠ 737,000円を超える給与(社会保険料等控除後)は本CSVでは対象外です。");
  console.log("  該当者がいる場合は国税庁資料の計算式で別途確認してください:");
  console.log(`  ${SOURCE_XLS_URL}`);
}

main().catch((err) => {
  console.error("エラー:", err instanceof Error ? err.message : err);
  process.exit(1);
});
