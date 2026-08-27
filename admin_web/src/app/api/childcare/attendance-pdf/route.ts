import fs from "fs";
import path from "path";
import PDFDocument from "pdfkit";
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

// woff2 は pdfkit でサブセット化に失敗し日本語が白紙化する。TTF を使う(therapy-records-pdf と同一)。
const FONT_PATH = path.join(process.cwd(), "src/assets/fonts/NotoSansJP-Regular.ttf");

// 登降園管理の帳票(§7)。出席簿(register)/登降園実績表(actuals)の2種。
// データは画面が持つ月間マトリクス(child×day)をそのまま POST 受領(therapy-records-pdf と同方針)。
type Row = {
  child_id: string;
  child_name: string;
  class_name: string | null;
  business_date: string;   // YYYY-MM-DD
  in_time: string | null;
  out_time: string | null;
  return_time: string | null;
  depart_time: string | null;
  is_absent: boolean;
  absence_kind: string | null;
};

type Body = {
  reportType: "register" | "actuals";
  officeName: string;
  year: number;
  month: number;
  openDays?: number | null;
  closureDays?: number[];   // 休園日の日番号(網掛け)
  rows: Row[];
};

const hhmm = (t: string | null) => (t ? t.slice(0, 5) : "");
const kindLabel = (r: Row) =>
  r.absence_kind === "sick_absence" ? "病欠" : r.absence_kind === "personal_absence" ? "都合欠" : "欠席";
const registerSymbol = (r: Row) => (r.is_absent ? kindLabel(r) : r.in_time || r.depart_time ? "◯" : "");
// 実測時間 = 初回登園〜最終降園(延長単位は Phase D 待ちで出さない)。
function actualDuration(r: Row): string {
  if (!r.in_time || !r.depart_time) return "";
  const [ih, im] = r.in_time.split(":").map(Number);
  const [dh, dm] = r.depart_time.split(":").map(Number);
  const mins = dh * 60 + dm - (ih * 60 + im);
  if (!Number.isFinite(mins) || mins <= 0) return "";
  return `${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, "0")}`;
}

const WEEKDAYS = ["日", "月", "火", "水", "木", "金", "土"];

function groupByChild(rows: Row[]): { child_id: string; name: string; cls: string | null; byDay: Map<number, Row> }[] {
  const map = new Map<string, { child_id: string; name: string; cls: string | null; byDay: Map<number, Row> }>();
  for (const r of rows) {
    let g = map.get(r.child_id);
    if (!g) { g = { child_id: r.child_id, name: r.child_name, cls: r.class_name, byDay: new Map() }; map.set(r.child_id, g); }
    g.byDay.set(Number(r.business_date.slice(8, 10)), r);
  }
  // クラス→氏名 の順で安定ソート。
  return [...map.values()].sort((a, b) => (a.cls ?? "").localeCompare(b.cls ?? "", "ja") || a.name.localeCompare(b.name, "ja"));
}

function newDoc(landscape: boolean): { doc: PDFKit.PDFDocument; done: Promise<Buffer> } {
  const doc = new PDFDocument({ size: "A4", margin: 28, layout: landscape ? "landscape" : "portrait" });
  doc.registerFont("JP", fs.readFileSync(FONT_PATH));
  doc.font("JP");
  const chunks: Buffer[] = [];
  doc.on("data", (c: Buffer) => chunks.push(c));
  const done = new Promise<Buffer>((resolve) => doc.on("end", () => resolve(Buffer.concat(chunks))));
  return { doc, done };
}

// 出席簿: 園児(行)× 日(列)。◯/病/都/空。休園日は列網掛け。A4横。
function renderRegister(b: Body): Promise<Buffer> {
  const { doc, done } = newDoc(true);
  const days = new Date(b.year, b.month, 0).getDate();
  const closed = new Set(b.closureDays ?? []);
  const groups = groupByChild(b.rows);

  doc.fontSize(15).text(`出席簿(${b.year}年${b.month}月)`, { align: "center" });
  doc.fontSize(9).fillColor("#555").text(`${b.officeName}${b.openDays != null ? `  開所日数 ${b.openDays}日` : ""}`, { align: "center" });
  doc.moveDown(0.6).fillColor("#000");

  const nameW = 78, clsW = 44;
  const dayW = Math.min(18, (doc.page.width - 56 - nameW - clsW) / days);
  const tableW = nameW + clsW + dayW * days;
  const startX = 28;
  let y = doc.y;
  const rowH = 15;

  const cell = (x: number, w: number, text: string, opts: { bold?: boolean; shade?: string; size?: number; align?: "left" | "center" } = {}) => {
    if (opts.shade) { doc.rect(x, y - 1, w, rowH).fill(opts.shade); doc.fillColor("#000"); }
    doc.fontSize(opts.size ?? 8).text(text, x + 1, y + 3, { width: w - 2, align: opts.align ?? "center", ellipsis: true });
  };
  const header = () => {
    cell(startX, nameW, "園児", { align: "left" });
    cell(startX + nameW, clsW, "クラス");
    for (let d = 1; d <= days; d++) {
      const dow = new Date(b.year, b.month - 1, d).getDay();
      const shade = closed.has(d) ? "#E2E8F0" : dow === 0 ? "#FDECEC" : dow === 6 ? "#EAF2FB" : undefined;
      cell(startX + nameW + clsW + dayW * (d - 1), dayW, `${d}\n${WEEKDAYS[dow]}`, { shade, size: 6 });
    }
    y += rowH + 4;
    doc.moveTo(startX, y - 2).lineTo(startX + tableW, y - 2).stroke();
  };
  header();
  for (const g of groups) {
    if (y > doc.page.height - 40) { doc.addPage(); y = doc.y; header(); }
    cell(startX, nameW, g.name, { align: "left" });
    cell(startX + nameW, clsW, g.cls ?? "");
    for (let d = 1; d <= days; d++) {
      const shade = closed.has(d) ? "#F1F5F9" : undefined;
      const r = g.byDay.get(d);
      cell(startX + nameW + clsW + dayW * (d - 1), dayW, r ? registerSymbol(r) : "", { shade, size: 7 });
    }
    y += rowH;
  }
  doc.end();
  return done;
}

// 登降園実績表: 園児ごとに 日付/区分/登園/降園/外出/戻り/実測時間。活動のある日のみ。A4縦。
function renderActuals(b: Body): Promise<Buffer> {
  const { doc, done } = newDoc(false);
  const groups = groupByChild(b.rows);

  doc.fontSize(15).text(`登降園実績表(${b.year}年${b.month}月)`, { align: "center" });
  doc.fontSize(9).fillColor("#555").text(b.officeName, { align: "center" });
  doc.moveDown(0.6).fillColor("#000");

  const cols = [
    { label: "日付", w: 70 }, { label: "区分", w: 50 }, { label: "登園", w: 55 },
    { label: "降園", w: 55 }, { label: "外出", w: 55 }, { label: "戻り", w: 55 }, { label: "実測", w: 60 },
  ];
  const startX = 28;
  const tableW = cols.reduce((a, c) => a + c.w, 0);
  let y = doc.y;
  const rowH = 16;

  const drawCells = (vals: string[], bold: boolean) => {
    let x = startX;
    doc.fontSize(bold ? 9 : 8.5);
    cols.forEach((c, i) => { doc.text(vals[i] ?? "", x + 2, y + 3, { width: c.w - 4, align: i === 0 || i === 1 ? "left" : "center", ellipsis: true }); x += c.w; });
    y += rowH;
  };
  const pageGuard = () => { if (y > doc.page.height - 40) { doc.addPage(); y = doc.y; } };

  for (const g of groups) {
    // 活動のある日(打刻いずれか or 欠席)を抽出。
    const dayEntries = [...g.byDay.entries()]
      .filter(([, r]) => r.is_absent || r.in_time || r.depart_time || r.out_time || r.return_time)
      .sort((a, b2) => a[0] - b2[0]);
    if (dayEntries.length === 0) continue;
    pageGuard();
    doc.fontSize(10.5).text(`${g.name}${g.cls ? `(${g.cls})` : ""}`, startX, y + 2);
    y += rowH + 2;
    drawCells(cols.map((c) => c.label), true);
    doc.moveTo(startX, y - 2).lineTo(startX + tableW, y - 2).stroke();
    for (const [d, r] of dayEntries) {
      pageGuard();
      const dow = WEEKDAYS[new Date(b.year, b.month - 1, d).getDay()];
      const kbn = r.is_absent ? kindLabel(r) : "出席";
      drawCells([`${b.month}/${d}(${dow})`, kbn, hhmm(r.in_time), hhmm(r.depart_time), hhmm(r.out_time), hhmm(r.return_time), actualDuration(r)], false);
    }
    y += 8;
  }
  doc.end();
  return done;
}

export async function POST(req: NextRequest) {
  try {
    const b = (await req.json()) as Body;
    const pdf = b.reportType === "actuals" ? await renderActuals(b) : await renderRegister(b);
    const fname = b.reportType === "actuals" ? "attendance-actuals" : "attendance-register";
    return new NextResponse(new Uint8Array(pdf), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename="${fname}-${b.year}-${String(b.month).padStart(2, "0")}.pdf"`,
      },
    });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: "PDF生成に失敗しました" }, { status: 500 });
  }
}
