import ExcelJS from "exceljs";
import { createClient } from "@/lib/supabase/client";

type PayrollExportRow = {
  employee_id: string;
  employee_number: string;
  employee_name: string;
  office_id: string;
  office_name: string;
  is_home_office: boolean;
  base_salary: number | null;
  allowances: number | null;
  commute: number | null;
  subtotal: number | null;
  deductions_total: number | null;
  net_pay: number | null;
};

const COLUMNS = [
  { header: "職員番号", width: 12 },
  { header: "氏名", width: 16 },
  { header: "所属施設", width: 18 },
  { header: "基本給", width: 12 },
  { header: "手当", width: 12 },
  { header: "通勤費", width: 12 },
  { header: "小計", width: 12 },
  { header: "控除額", width: 12 },
  { header: "差引支給額", width: 14 },
];

function sanitizeSheetName(name: string): string {
  const cleaned = name.replace(/[:\\/?*[\]]/g, "");
  return cleaned.slice(0, 31) || "sheet";
}

function buildRow(row: PayrollExportRow): (string | number)[] {
  return [
    row.employee_number,
    row.employee_name,
    row.office_name,
    row.base_salary ?? 0,
    row.allowances ?? 0,
    row.commute ?? 0,
    row.subtotal ?? 0,
    // 控除額・差引支給額は所属施設(home_office)のみ算出される(兼務先には計上しない設計)。
    row.is_home_office ? (row.deductions_total ?? 0) : "",
    row.is_home_office ? (row.net_pay ?? 0) : "",
  ];
}

export async function exportPayrollByOfficeExcel({
  payrollRunId,
  targetMonth,
}: {
  payrollRunId: string;
  targetMonth: string;
}): Promise<void> {
  const supabase = createClient();

  const { data, error } = await supabase.rpc("fetch_payroll_export_by_office", {
    p_payroll_run_id: payrollRunId,
    p_office_id: null,
  });
  if (error) throw new Error(error.message);

  const rows = (data ?? []) as PayrollExportRow[];

  const groups = new Map<string, { officeName: string; rows: PayrollExportRow[] }>();
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

    for (const row of group.rows.sort((a, b) => a.employee_number.localeCompare(b.employee_number))) {
      sheet.addRow(buildRow(row));
    }
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
  link.download = `施設別給与内訳_${targetMonth}.xlsx`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
