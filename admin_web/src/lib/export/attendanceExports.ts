import ExcelJS from "exceljs";

// 登降園管理のExcel出力(俊指示 2026-08-25: CSV→Excel化・月付き日付・中央寄せ・欠席児は下部)。
export type AttendanceExportRow = {
  child_id: string;
  child_name: string;
  class_name: string | null;
  business_date: string;
  in_time: string | null;
  out_time: string | null;
  return_time: string | null;
  depart_time: string | null;
  is_absent: boolean;
  absence_reason: string | null;
  absence_kind: string | null;
  note: string | null;
};

const WEEKDAYS = ["日", "月", "火", "水", "木", "金", "土"];
const hhmm = (t: string | null) => (t ? t.slice(0, 5) : "");
const kindLabel = (r: AttendanceExportRow) =>
  r.absence_kind === "sick_absence" ? "病欠" : r.absence_kind === "personal_absence" ? "都合欠" : "欠席";
const registerSymbol = (r: AttendanceExportRow) =>
  r.is_absent ? kindLabel(r) : (r.in_time || r.depart_time) ? "◯" : "";

type ChildAgg = { name: string; cls: string | null; days: Map<number, AttendanceExportRow>; absentCount: number };

function groupByChild(rows: AttendanceExportRow[]) {
  const map = new Map<string, ChildAgg>();
  const order: string[] = [];
  for (const r of rows) {
    if (!map.has(r.child_id)) { map.set(r.child_id, { name: r.child_name, cls: r.class_name, days: new Map(), absentCount: 0 }); order.push(r.child_id); }
    const g = map.get(r.child_id)!;
    g.days.set(new Date(r.business_date).getDate(), r);
    if (r.is_absent) g.absentCount++;
  }
  return { map, order };
}

function centerAll(ws: ExcelJS.Worksheet) {
  ws.eachRow((row) => {
    row.eachCell((cell) => {
      cell.alignment = { horizontal: "center", vertical: "middle" };
      cell.border = {
        top: { style: "thin", color: { argb: "FFE2E8F0" } },
        left: { style: "thin", color: { argb: "FFE2E8F0" } },
        bottom: { style: "thin", color: { argb: "FFE2E8F0" } },
        right: { style: "thin", color: { argb: "FFE2E8F0" } },
      };
    });
  });
}

// 行(またはグループ)ごとの縞模様。groupSize=1で1行ごと、3で3行ごと(時刻表の登園/降園/欠席)。
function stripe(ws: ExcelJS.Worksheet, firstDataRow: number, groupSize: number) {
  let group = 0;
  for (let r = firstDataRow; r <= ws.rowCount; r += groupSize) {
    if (group % 2 === 1) {
      for (let rr = r; rr < r + groupSize && rr <= ws.rowCount; rr++) {
        ws.getRow(rr).eachCell((cell) => (cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF6F8FB" } }));
      }
    }
    group++;
  }
}

function dowFill(d: number, year: number, month: number): string | null {
  const g = new Date(year, month - 1, d).getDay();
  return g === 0 ? "FFFDECEC" : g === 6 ? "FFEAF5FD" : null; // 日=淡赤 / 土=淡青
}

async function download(wb: ExcelJS.Workbook, filename: string) {
  const buffer = await wb.xlsx.writeBuffer();
  const blob = new Blob([buffer], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

// 出席簿(◯/病欠/都合欠)。園児×日 + 集計。欠席の多い児は下にまとめる。
export async function exportRegisterXlsx(
  rows: AttendanceExportRow[], year: number, month: number,
  closures?: Record<number, { reason: string | null; label: string | null }>, openDays?: number | null,
) {
  const daysInMonth = new Date(year, month, 0).getDate();
  const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);
  const { map, order } = groupByChild(rows);
  // 欠席児(欠席が1日でもある子)を下にまとめる(俊指示)。それ以外は元の年齢/氏名順。
  const sortedIds = [...order].sort((a, b) => {
    const aa = (map.get(a)!.absentCount > 0 ? 1 : 0), bb = (map.get(b)!.absentCount > 0 ? 1 : 0);
    return aa - bb || order.indexOf(a) - order.indexOf(b);
  });

  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(`${year}年${month}月`);
  const lastCol = 2 + days.length + 3;
  ws.mergeCells(1, 1, 1, lastCol);
  const title = ws.getCell(1, 1);
  title.value = openDays != null ? `${year}年${month}月 出席簿(開所日数 ${openDays}日)` : `${year}年${month}月 出席簿`;
  title.font = { bold: true, size: 14 };
  title.alignment = { horizontal: "center", vertical: "middle" };

  const header = ["クラス", "氏名", ...days.map((d) => `${month}/${d}`), "出席", "病欠", "都合欠"];
  const dow = ["", "", ...days.map((d) => WEEKDAYS[new Date(year, month - 1, d).getDay()]), "", "", ""];
  ws.addRow(header);
  ws.addRow(dow);
  for (const id of sortedIds) {
    const c = map.get(id)!;
    let present = 0, sick = 0, personal = 0;
    const cells = days.map((d) => {
      const r = c.days.get(d);
      const s = r ? registerSymbol(r) : "";
      if (s === "◯") present++; else if (s === "病欠") sick++; else if (s === "都合欠") personal++;
      return s;
    });
    ws.addRow([c.cls ?? "", c.name, ...cells, present, sick, personal]);
  }
  ws.getRow(2).font = { bold: true };
  ws.getRow(3).font = { size: 9, color: { argb: "FF94A3B8" } };
  centerAll(ws);
  stripe(ws, 4, 1); // 出席簿は1行ごとに縞
  // 休園日カラムの網掛け(定休/祝日/園独自=グレー)。closures未指定時は従来の土日淡色。
  days.forEach((d, i) => {
    const fill = closures?.[d] ? "FFE2E8F0" : dowFill(d, year, month);
    if (fill) for (let r = 2; r <= ws.rowCount; r++) ws.getRow(r).getCell(3 + i).fill = { type: "pattern", pattern: "solid", fgColor: { argb: fill } };
  });
  ws.getColumn(1).width = 9; ws.getColumn(2).width = 14;
  days.forEach((_, i) => (ws.getColumn(3 + i).width = 4.5));
  for (let i = 0; i < 3; i++) ws.getColumn(3 + days.length + i).width = 6;
  ws.views = [{ state: "frozen", xSplit: 2, ySplit: 3 }];
  await download(wb, `出席簿_${year}-${String(month).padStart(2, "0")}.xlsx`);
}

// 登降園時刻簿。園児ごとに「登園/降園/欠席」の3行 × 日付列。欠席児は下にまとめる。
export async function exportTimeXlsx(rows: AttendanceExportRow[], year: number, month: number) {
  const daysInMonth = new Date(year, month, 0).getDate();
  const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);
  const { map, order } = groupByChild(rows);
  const sortedIds = [...order].sort((a, b) => {
    const aa = (map.get(a)!.absentCount > 0 ? 1 : 0), bb = (map.get(b)!.absentCount > 0 ? 1 : 0);
    return aa - bb || order.indexOf(a) - order.indexOf(b);
  });

  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(`${year}年${month}月`);
  const cCount1 = 2 + days.length + 1; // 集計列(出席/病欠/都合欠)の先頭列
  const lastCol = 2 + days.length + 3;
  ws.mergeCells(1, 1, 1, lastCol);
  const title = ws.getCell(1, 1);
  title.value = `${year}年${month}月 登降園時刻`;
  title.font = { bold: true, size: 14 };
  title.alignment = { horizontal: "center", vertical: "middle" };

  ws.addRow(["氏名", "区分", ...days.map((d) => `${month}/${d}`), "出席", "病欠", "都合欠"]);
  ws.addRow(["", "", ...days.map((d) => WEEKDAYS[new Date(year, month - 1, d).getDay()]), "", "", ""]);
  for (const id of sortedIds) {
    const c = map.get(id)!;
    const arrival = days.map((d) => { const r = c.days.get(d); return r && !r.is_absent ? hhmm(r.in_time) : ""; });
    const departure = days.map((d) => { const r = c.days.get(d); return r && !r.is_absent ? hhmm(r.depart_time) : ""; });
    const absence = days.map((d) => { const r = c.days.get(d); return r && r.is_absent ? kindLabel(r) : ""; });
    // 集計(出席=登園or降園あり / 病欠 / 都合欠)。
    let present = 0, sick = 0, personal = 0;
    days.forEach((d) => {
      const r = c.days.get(d);
      if (!r) return;
      if (r.is_absent) { if (r.absence_kind === "sick_absence") sick++; else if (r.absence_kind === "personal_absence") personal++; }
      else if (r.in_time || r.depart_time) present++;
    });
    const nameCell = `${c.name}${c.cls ? `（${c.cls}）` : ""}`;
    const r1 = ws.addRow([nameCell, "登園", ...arrival, present, sick, personal]);
    ws.addRow(["", "降園", ...departure]);
    const r3 = ws.addRow(["", "欠席", ...absence]);
    ws.mergeCells(r1.number, 1, r3.number, 1); // 氏名を3行で結合
    // 集計セルも園児の3行で結合。
    for (let k = 0; k < 3; k++) ws.mergeCells(r1.number, cCount1 + k, r3.number, cCount1 + k);
  }
  ws.getRow(2).font = { bold: true };
  ws.getRow(3).font = { size: 9, color: { argb: "FF94A3B8" } };
  centerAll(ws);
  stripe(ws, 4, 3); // 時刻表は園児(登園/降園/欠席の3行)ごとに縞
  days.forEach((d, i) => {
    const fill = dowFill(d, year, month);
    if (fill) for (let r = 2; r <= ws.rowCount; r++) ws.getRow(r).getCell(3 + i).fill = { type: "pattern", pattern: "solid", fgColor: { argb: fill } };
  });
  ws.getColumn(1).width = 16; ws.getColumn(2).width = 6;
  days.forEach((_, i) => (ws.getColumn(3 + i).width = 6));
  for (let k = 0; k < 3; k++) ws.getColumn(cCount1 + k).width = 6;
  ws.views = [{ state: "frozen", xSplit: 2, ySplit: 3 }];
  await download(wb, `登降園時刻_${year}-${String(month).padStart(2, "0")}.xlsx`);
}

// 園児別。選択児の1ヶ月(日/曜/出欠/登園/外出/戻り/降園/備考)。
export async function exportChildXlsx(rows: AttendanceExportRow[], year: number, month: number, childId: string, childName: string, className: string | null) {
  const daysInMonth = new Date(year, month, 0).getDate();
  const byDay = new Map<number, AttendanceExportRow>();
  for (const r of rows) if (r.child_id === childId) byDay.set(new Date(r.business_date).getDate(), r);

  const wb = new ExcelJS.Workbook();
  const ws = wb.addWorksheet(childName.slice(0, 28) || "園児");
  ws.mergeCells(1, 1, 1, 8);
  const title = ws.getCell(1, 1);
  title.value = `${year}年${month}月 登降園（${childName}${className ? ` / ${className}` : ""}）`;
  title.font = { bold: true, size: 14 };
  title.alignment = { horizontal: "center", vertical: "middle" };

  ws.addRow(["日", "曜", "出欠", "登園", "外出", "戻り", "降園", "備考"]);
  let present = 0, sick = 0, personal = 0;
  for (let d = 1; d <= daysInMonth; d++) {
    const r = byDay.get(d);
    const g = new Date(year, month - 1, d).getDay();
    const state = !r ? "" : r.is_absent ? kindLabel(r) : (r.in_time || r.depart_time) ? "出席" : "";
    if (state === "出席") present++; else if (state === "病欠") sick++; else if (state === "都合欠") personal++;
    ws.addRow([d, WEEKDAYS[g], state, r ? hhmm(r.in_time) : "", r ? hhmm(r.out_time) : "", r ? hhmm(r.return_time) : "", r ? hhmm(r.depart_time) : "", r?.note ?? ""]);
  }
  // 月合計(出席/病欠/都合欠の日数)。
  const totalRow = ws.addRow(["合計", "", `出席 ${present} / 病欠 ${sick} / 都合欠 ${personal}`, "", "", "", "", ""]);
  ws.mergeCells(totalRow.number, 3, totalRow.number, 8);
  totalRow.font = { bold: true };
  ws.getRow(2).font = { bold: true };
  centerAll(ws);
  stripe(ws, 3, 1); // 園児別は1日ごとに縞
  ws.getColumn(8).alignment = { horizontal: "left", vertical: "middle" }; // 備考は左寄せ
  for (let d = 1; d <= daysInMonth; d++) {
    const fill = dowFill(d, year, month);
    if (fill) ws.getRow(2 + d).eachCell((cell) => (cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: fill } }));
  }
  [4, 4, 8, 8, 8, 8, 8, 24].forEach((w, i) => (ws.getColumn(i + 1).width = w));
  ws.views = [{ state: "frozen", ySplit: 2 }];
  await download(wb, `登降園_${childName}_${year}-${String(month).padStart(2, "0")}.xlsx`);
}
