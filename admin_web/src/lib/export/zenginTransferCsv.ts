import Encoding from "encoding-japanese";
import { toHalfWidthKana } from "./halfWidthKana";

// 19章 振込データ: 全銀協「総合振込」標準フォーマット(固定長120バイト・Shift-JIS)の
// ベストエフォート実装。横浜銀行の法人向けインターネットバンキング仕様書での
// 最終確認が必要(32章の確認事項リスト・設計書19章に明記)。
// 実際の銀行提出前に必ず仕様書と突き合わせ、テスト伝送等で検証すること。

export type PayrollPayer = {
  office_name: string;
  bank_name_kana: string | null;
  branch_name_kana: string | null;
  bank_code: string | null;
  branch_code: string | null;
  account_type: string | null;
  account_number: string | null;
  account_holder_name: string | null;
};

export type PayrollRecipient = {
  employee_id: string;
  employee_name: string;
  net_pay: number;
  bank_name_kana: string | null;
  branch_name_kana: string | null;
  bank_code: string | null;
  branch_code: string | null;
  account_type: string | null;
  account_number: string | null;
  account_holder_name_kana: string | null;
};

function padText(value: string | null, length: number): string {
  const half = toHalfWidthKana((value ?? "").trim());
  if (half.length >= length) return half.slice(0, length);
  return half + " ".repeat(length - half.length);
}

function padNumber(value: string | number | null, length: number): string {
  const digits = String(value ?? "").replace(/\D/g, "");
  if (digits.length >= length) return digits.slice(-length);
  return "0".repeat(length - digits.length) + digits;
}

function padSpace(length: number): string {
  return " ".repeat(length);
}

function accountTypeCode(accountType: string | null): string {
  return accountType === "当座" ? "2" : "1"; // 未設定時は普通預金扱い
}

function formatMMDD(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${pad(date.getMonth() + 1)}${pad(date.getDate())}`;
}

/** 振込に必要な口座情報(銀行コード・支店コード・カナ名義)が揃っているか。 */
export function isRecipientReady(r: PayrollRecipient): boolean {
  return Boolean(
    r.bank_code && r.branch_code && r.account_number && r.account_holder_name_kana,
  );
}

function buildHeaderRecord(payer: PayrollPayer, transferDate: Date): string {
  return [
    "1",
    "21",
    "0",
    padNumber("", 10), // 委託者コード: 銀行から付与されるEDIコード。未設定のため要別途入力。
    padText(payer.account_holder_name, 40),
    formatMMDD(transferDate),
    padNumber(payer.bank_code, 4),
    padText(payer.bank_name_kana, 15),
    padNumber(payer.branch_code, 3),
    padText(payer.branch_name_kana, 15),
    accountTypeCode(payer.account_type),
    padNumber(payer.account_number, 7),
    padSpace(17),
  ].join("");
}

function buildDataRecord(r: PayrollRecipient): string {
  return [
    "2",
    padNumber(r.bank_code, 4),
    padText(r.bank_name_kana, 15),
    padNumber(r.branch_code, 3),
    padText(r.branch_name_kana, 15),
    padNumber("", 4), // 手形交換所番号(省略)
    accountTypeCode(r.account_type),
    padNumber(r.account_number, 7),
    padText(r.account_holder_name_kana, 30),
    padNumber(r.net_pay, 10),
    "0", // 新規コード
    padSpace(10), // 顧客番号1
    padSpace(10), // 顧客番号2
    "0", // 振込指定区分
    " ", // 識別表示
    padSpace(7), // ダミー
  ].join("");
}

function buildTrailerRecord(count: number, totalAmount: number): string {
  return ["8", padNumber(count, 6), padNumber(totalAmount, 12), padSpace(101)].join("");
}

function buildEndRecord(): string {
  return ["9", padSpace(119)].join("");
}

export function buildZenginTransferText(
  payer: PayrollPayer,
  recipients: PayrollRecipient[],
  transferDate: Date,
): string {
  const readyRecipients = recipients.filter(isRecipientReady);
  const totalAmount = readyRecipients.reduce((sum, r) => sum + r.net_pay, 0);

  const lines = [
    buildHeaderRecord(payer, transferDate),
    ...readyRecipients.map(buildDataRecord),
    buildTrailerRecord(readyRecipients.length, totalAmount),
    buildEndRecord(),
  ];
  return lines.join("\r\n") + "\r\n";
}

export function downloadZenginTransferCsv(
  payer: PayrollPayer,
  recipients: PayrollRecipient[],
  transferDate: Date,
  fileNameSuffix: string,
): { skippedCount: number } {
  const text = buildZenginTransferText(payer, recipients, transferDate);
  const skippedCount = recipients.filter((r) => !isRecipientReady(r)).length;

  const bytes = Encoding.convert(Encoding.stringToCode(text), {
    to: "SJIS",
    from: "UNICODE",
  });
  const blob = new Blob([new Uint8Array(bytes)], { type: "text/csv" });

  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `振込データ_${fileNameSuffix}.txt`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);

  return { skippedCount };
}
