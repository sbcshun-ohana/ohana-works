import fs from "fs";
import path from "path";
import PDFDocument from "pdfkit";
import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";

const FONT_PATH = path.join(process.cwd(), "src/assets/fonts/NotoSansJP-Regular.woff2");

function formatYen(amount: number): string {
  return `${amount.toLocaleString("ja-JP")}円`;
}

function formatDuration(minutes: number): string {
  return `${Math.floor(minutes / 60)}時間${minutes % 60}分`;
}

function generatePayslipPdf(input: {
  officeName: string;
  employeeName: string;
  employeeNumber: string;
  targetMonth: string;
  attendanceDays: number;
  actualWorkedMinutes: number;
  overtimeMinutes: number;
  earnings: Record<string, unknown>;
  deductions: Record<string, unknown>;
  netPay: number;
}): Promise<Buffer> {
  const fontBuffer = fs.readFileSync(FONT_PATH);
  const doc = new PDFDocument({ size: "A4", margin: 40 });
  doc.registerFont("NotoSansJP", fontBuffer);
  doc.font("NotoSansJP");

  const chunks: Buffer[] = [];
  doc.on("data", (chunk: Buffer) => chunks.push(chunk));
  const done = new Promise<Buffer>((resolve) => {
    doc.on("end", () => resolve(Buffer.concat(chunks)));
  });

  const num = (v: unknown) => (typeof v === "number" ? v : 0);
  const earnings = input.earnings;
  const deductions = input.deductions;

  doc.fontSize(18).text("給与明細書", { align: "center" });
  doc.moveDown(0.5);
  doc.fontSize(10).fillColor("#555").text(`対象年月: ${input.targetMonth}`, { align: "center" });
  doc.moveDown(1.5);
  doc.fillColor("#000");

  doc.fontSize(11);
  doc.text(`氏名: ${input.employeeName}`);
  doc.text(`職員番号: ${input.employeeNumber}`);
  doc.text(`基本所属: ${input.officeName}`);
  doc.moveDown(1);

  doc.fontSize(11).text("勤怠情報", { underline: true });
  doc.moveDown(0.3);
  doc.fontSize(10);
  doc.text(`勤務日数: ${input.attendanceDays}日`);
  doc.text(`勤務時間: ${formatDuration(input.actualWorkedMinutes)}`);
  doc.text(`時間外: ${formatDuration(input.overtimeMinutes)}`);
  doc.moveDown(1);

  function drawTable(title: string, rows: [string, number][]) {
    doc.fontSize(11).text(title, { underline: true });
    doc.moveDown(0.3);
    doc.fontSize(10);
    const startX = doc.x;
    for (const [label, amount] of rows) {
      if (amount === 0 && !["基本給", "手当", "支給合計", "控除合計"].includes(label)) continue;
      const y = doc.y;
      doc.text(label, startX, y, { continued: false });
      doc.text(formatYen(amount), startX, y, { width: 480, align: "right" });
    }
    doc.moveDown(0.5);
  }

  drawTable("支給", [
    ["基本給", num(earnings.base_salary)],
    ["手当", num(earnings.allowance_total)],
    ["特殊業務手当", num(earnings.special_duty_allowance)],
    ["早番手当", num(earnings.early_shift_allowance)],
    ["時間外割増", num(earnings.overtime_premium)],
    ["深夜割増", num(earnings.night_premium)],
    ["法定休日割増", num(earnings.holiday_premium)],
    ["交通費", num(earnings.commute_allowance)],
    ["支給合計", num(earnings.gross_total)],
  ]);

  drawTable("控除", [
    ["欠勤・遅刻早退控除", num(deductions.absence_deduction)],
    ["健康保険", num(deductions.health_insurance)],
    ["介護保険", num(deductions.care_insurance)],
    ["厚生年金", num(deductions.pension_insurance)],
    ["雇用保険", num(deductions.employment_insurance)],
    ["子ども・子育て支援金", num(deductions.childcare_support_levy)],
    ["源泉所得税", num(deductions.income_tax)],
    ["住民税", num(deductions.resident_tax)],
    ["負担金", num(deductions.burden_fee)],
    ["借上宿舎本人負担金", num(deductions.company_housing_deduction)],
    ["控除合計", num(deductions.deductions_total)],
  ]);

  doc.moveDown(0.5);
  doc.rect(doc.x, doc.y, 480, 34).fillAndStroke("#f0f9ff", "#bae6fd");
  doc.fillColor("#0c4a6e").fontSize(13);
  doc.text("差引支給額", doc.x + 12, doc.y - 26);
  doc.fontSize(16).text(formatYen(input.netPay), doc.x, doc.y - 20, { width: 468, align: "right" });
  doc.fillColor("#000");

  doc.moveDown(2);
  doc.fontSize(10).text("備考", { underline: true });
  doc.moveDown(0.3);
  doc.fontSize(9).fillColor("#888").text("(特記事項なし)");

  doc.end();
  return done;
}

export async function GET(request: NextRequest) {
  const payrollRunId = request.nextUrl.searchParams.get("payrollRunId");
  const employeeId = request.nextUrl.searchParams.get("employeeId");
  if (!payrollRunId || !employeeId) {
    return NextResponse.json({ error: "payrollRunId and employeeId are required" }, { status: 400 });
  }

  const supabase = await createClient();

  const { data: run, error: runError } = await supabase
    .from("payroll_runs")
    .select("id, target_month, status")
    .eq("id", payrollRunId)
    .maybeSingle();
  if (runError) return NextResponse.json({ error: runError.message }, { status: 500 });
  if (!run) return NextResponse.json({ error: "payroll run not found" }, { status: 404 });
  if (run.status === "draft") {
    return NextResponse.json(
      { error: "給与確定前の対象月は給与明細PDFを発行できません(17.2)" },
      { status: 409 },
    );
  }

  const { data: detail, error: detailError } = await supabase
    .from("payroll_details")
    .select("earnings, deductions, net_pay, employees(name, employee_number, offices(name))")
    .eq("payroll_run_id", payrollRunId)
    .eq("employee_id", employeeId)
    .maybeSingle();
  if (detailError) return NextResponse.json({ error: detailError.message }, { status: 500 });
  if (!detail) return NextResponse.json({ error: "payroll detail not found" }, { status: 404 });

  const employee = detail.employees as unknown as {
    name: string;
    employee_number: string;
    offices: { name: string } | null;
  };

  const { data: summary } = await supabase
    .from("attendance_summaries")
    .select("attendance_days, actual_worked_minutes, overtime_minutes")
    .eq("employee_id", employeeId)
    .eq("target_month", run.target_month)
    .maybeSingle();

  const pdfBuffer = await generatePayslipPdf({
    officeName: employee.offices?.name ?? "",
    employeeName: employee.name,
    employeeNumber: employee.employee_number,
    targetMonth: run.target_month,
    attendanceDays: summary?.attendance_days ?? 0,
    actualWorkedMinutes: summary?.actual_worked_minutes ?? 0,
    overtimeMinutes: summary?.overtime_minutes ?? 0,
    earnings: detail.earnings as Record<string, unknown>,
    deductions: detail.deductions as Record<string, unknown>,
    netPay: detail.net_pay,
  });

  const filePath = `${employeeId}/${payrollRunId}.pdf`;
  const { error: uploadError } = await supabase.storage
    .from("payslips")
    .upload(filePath, pdfBuffer, { contentType: "application/pdf", upsert: true });
  if (uploadError) {
    return NextResponse.json({ error: `PDFの保存に失敗しました: ${uploadError.message}` }, { status: 500 });
  }

  const { error: markError } = await supabase.rpc("mark_payslip_generated", {
    p_payroll_run_id: payrollRunId,
    p_employee_id: employeeId,
    p_file_path: filePath,
  });
  if (markError) {
    return NextResponse.json({ error: markError.message }, { status: 500 });
  }

  return new NextResponse(new Uint8Array(pdfBuffer), {
    status: 200,
    headers: {
      "Content-Type": "application/pdf",
      "Content-Disposition": `attachment; filename="給与明細_${run.target_month}_${employee.name}.pdf"`,
    },
  });
}
