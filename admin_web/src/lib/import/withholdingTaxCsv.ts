// 20.2 源泉所得税額表(月額表)CSV取込。
// 国税庁の月額表は「賃金帯×扶養人数(0〜7人以上)」の甲欄と、賃金帯のみの乙欄で構成される。
// CSVは1賃金帯=1行のwide形式(甲欄8列+乙欄1列)で受け付け、DB保存直前にlong形式へ展開する。

export const EXPECTED_HEADERS = [
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
] as const;

export type WideRow = {
  wageLowerBound: number;
  wageUpperBound: number | null;
  kouAmounts: number[]; // index = dependent_count(0-7)
  otsuAmount: number;
};

export type LongRow = {
  tax_column: "甲欄" | "乙欄";
  dependent_count: number;
  wage_lower_bound: number;
  wage_upper_bound: number | null;
  tax_amount: number;
};

export type ParseResult = {
  wideRows: WideRow[];
  rows: LongRow[];
  errors: string[];
  warnings: string[];
};

function splitCsvLine(line: string): string[] {
  return line.split(",").map((c) => c.trim());
}

export function parseWithholdingTaxCsv(text: string): ParseResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const lines = text
    .split(/\r\n|\n|\r/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0);

  if (lines.length === 0) {
    return { wideRows: [], rows: [], errors: ["ファイルが空です"], warnings: [] };
  }

  const header = splitCsvLine(lines[0]);
  const headerOk =
    header.length === EXPECTED_HEADERS.length &&
    EXPECTED_HEADERS.every((h, i) => header[i] === h);
  if (!headerOk) {
    errors.push(`ヘッダー行が想定形式と異なります。期待するヘッダー: ${EXPECTED_HEADERS.join(",")}`);
    return { wideRows: [], rows: [], errors, warnings };
  }

  const wideRows: WideRow[] = [];
  for (let i = 1; i < lines.length; i++) {
    const cols = splitCsvLine(lines[i]);
    const lineNo = i + 1;
    if (cols.length !== EXPECTED_HEADERS.length) {
      errors.push(`${lineNo}行目: 列数が不正です(${cols.length}列、期待${EXPECTED_HEADERS.length}列)`);
      continue;
    }
    const [lowerStr, upperStr, ...rest] = cols;
    const kouStrs = rest.slice(0, 8);
    const otsuStr = rest[8];

    const lower = Number(lowerStr);
    const upper = upperStr === "" ? null : Number(upperStr);
    const kouAmounts = kouStrs.map(Number);
    const otsuAmount = Number(otsuStr);

    if (
      !Number.isFinite(lower) ||
      (upper !== null && !Number.isFinite(upper)) ||
      kouAmounts.some((a) => !Number.isFinite(a)) ||
      !Number.isFinite(otsuAmount)
    ) {
      errors.push(`${lineNo}行目: 数値として解釈できない値があります`);
      continue;
    }
    if (lower < 0 || kouAmounts.some((a) => a < 0) || otsuAmount < 0) {
      errors.push(`${lineNo}行目: 負の値は指定できません`);
      continue;
    }
    if (upper !== null && upper <= lower) {
      errors.push(`${lineNo}行目: wage_upper_bound(${upper})はwage_lower_bound(${lower})より大きい必要があります`);
      continue;
    }

    wideRows.push({ wageLowerBound: lower, wageUpperBound: upper, kouAmounts, otsuAmount });
  }

  const sorted = [...wideRows].sort((a, b) => a.wageLowerBound - b.wageLowerBound);
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i].wageLowerBound !== sorted[i - 1].wageUpperBound) {
      warnings.push(
        `賃金帯が不連続です: ${sorted[i - 1].wageUpperBound ?? "上限なし"}円 と ${sorted[i].wageLowerBound}円 の間`,
      );
    }
  }
  if (sorted.length > 0 && sorted[sorted.length - 1].wageUpperBound !== null) {
    warnings.push("最後の賃金帯にwage_upper_bound(上限)が設定されています。通常は最終行を上限なし(空欄)にします。");
  }

  const rows: LongRow[] = [];
  for (const w of wideRows) {
    for (let dep = 0; dep <= 7; dep++) {
      rows.push({
        tax_column: "甲欄",
        dependent_count: dep,
        wage_lower_bound: w.wageLowerBound,
        wage_upper_bound: w.wageUpperBound,
        tax_amount: w.kouAmounts[dep],
      });
      rows.push({
        tax_column: "乙欄",
        dependent_count: dep,
        wage_lower_bound: w.wageLowerBound,
        wage_upper_bound: w.wageUpperBound,
        tax_amount: w.otsuAmount,
      });
    }
  }

  return { wideRows, rows, errors, warnings };
}
