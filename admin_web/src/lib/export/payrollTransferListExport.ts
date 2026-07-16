import ExcelJS from "exceljs";
import { createClient } from "@/lib/supabase/client";

type TransferListRow = {
  employee_id: string;
  employee_number: string;
  employee_name: string;
  employee_name_kana: string | null;
  office_id: string;
  office_name: string;
  bank_name: string | null;
  branch_name: string | null;
  account_type: string | null;
  account_number: string | null;
  account_holder_name_kana: string | null;
  net_pay: number;
  account_info_ready: boolean;
};

const COLUMNS = [
  { header: "職員番号", width: 12 },
  { header: "氏名", width: 20 },
  { header: "所属施設", width: 18 },
  { header: "振込先金融機関", width: 18 },
  { header: "支店名", width: 14 },
  { header: "口座種別", width: 10 },
  { header: "口座番号", width: 12 },
  { header: "口座名義(カナ)", width: 20 },
  { header: "差引支給額(振込額)", width: 16 },
  { header: "備考", width: 20 },
];

const MISSING_FILL: ExcelJS.Fill = {
  type: "pattern",
  pattern: "solid",
  fgColor: { argb: "FFFDE2E2" },
};

function sanitizeSheetName(name: string): string {
  const cleaned = name.replace(/[:\\/?*[\]]/g, "");
  return cleaned.slice(0, 31) || "sheet";
}

function accountTypeLabel(accountType: string | null): string {
  if (accountType === "当座") return "当座";
  if (accountType === "普通") return "普通";
  return accountType ?? "";
}

function buildRow(row: TransferListRow): (string | number)[] {
  const nameWithKana = row.employee_name_kana ? `${row.employee_name}(${row.employee_name_kana})` : row.employee_name;
  return [
    row.employee_number,
    nameWithKana,
    row.office_name,
    row.bank_name ?? "",
    row.branch_name ?? "",
    accountTypeLabel(row.account_type),
    row.account_number ?? "",
    row.account_holder_name_kana ?? "",
    row.net_pay,
    row.account_info_ready ? "" : "口座情報未登録(振込データから除外されます)",
  ];
}

export async function exportPayrollTransferListExcel({
  payrollRunId,
  targetMonth,
}: {
  payrollRunId: string;
  targetMonth: string;
}): Promise<{ skippedCount: number }> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fetch_payroll_transfer_list_export", {
    p_payroll_run_id: payrollRunId,
  });
  if (error) throw new Error(error.message);

  const rows = (data ?? []) as TransferListRow[];
  const skippedCount = rows.filter((r) => !r.account_info_ready).length;

  const groups = new Map<string, { officeName: string; rows: TransferListRow[] }>();
  for (const row of rows) {
    if (!groups.has(row.office_id)) {
      groups.set(row.office_id, { officeName: row.office_name, rows: [] });
    }
    groups.get(row.office_id)!.rows.push(row);
  }

  const workbook = new ExcelJS.Workbook();
  const usedSheetNames = new Set<string>();

  for (const [officeId, group] of Array.from(groups.entries()).sort(([, a], [, b]) =>
    a.officeName.localeCompare(b.officeName, "ja"),
  )) {
    let sheetName = sanitizeSheetName(group.officeName);
    if (usedSheetNames.has(sheetName)) {
      sheetName = sanitizeSheetName(`${sheetName}_${officeId.slice(0, 4)}`);
    }
    usedSheetNames.add(sheetName);

    const sheet = workbook.addWorksheet(sheetName);
    sheet.columns = COLUMNS.map((c) => ({ header: c.header, width: c.width }));
    sheet.getRow(1).font = { bold: true };

    let readyTotal = 0;
    for (const row of group.rows.sort((a, b) => a.employee_number.localeCompare(b.employee_number))) {
      const excelRow = sheet.addRow(buildRow(row));
      if (!row.account_info_ready) {
        excelRow.eachCell((cell) => {
          cell.fill = MISSING_FILL;
        });
      } else {
        readyTotal += row.net_pay;
      }
    }

    sheet.addRow([]);
    const totalRow = sheet.addRow(["", "", "", "", "", "", "", "合計(振込対象のみ)", readyTotal, ""]);
    totalRow.font = { bold: true };
  }

  if (workbook.worksheets.length === 0) {
    workbook.addWorksheet("該当データなし");
  }

  const buffer = await workbook.xlsx.writeBuffer();
  const blob = new Blob([buffer], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `振込一覧_${targetMonth}.xlsx`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);

  return { skippedCount };
}
