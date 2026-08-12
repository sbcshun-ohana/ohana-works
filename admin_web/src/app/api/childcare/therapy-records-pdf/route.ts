import fs from "fs";
import path from "path";
import PDFDocument from "pdfkit";
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

// woff2 は pdfkit でサブセット化に失敗し日本語が描画されない(白紙)。TTF/OTF を使う。
// (therapy-qr/route.ts と同一の理由・同一フォント)
const FONT_PATH = path.join(process.cwd(), "src/assets/fonts/NotoSansJP-Regular.ttf");

type Row = {
  childName: string;
  providerName: string;
  date: string;
  out: string;
  ret: string;
  duration: string;
  warning: string;
};

// 療育記録の月次帳票(§5.3・render専用)。一覧と同じ「外出/戻りペア+所要+片方欠落警告」。
async function generatePdf(input: { officeName: string; month: string; rows: Row[] }): Promise<Buffer> {
  const doc = new PDFDocument({ size: "A4", margin: 36, layout: "landscape" });
  doc.registerFont("NotoSansJP", fs.readFileSync(FONT_PATH));
  doc.font("NotoSansJP");

  const chunks: Buffer[] = [];
  doc.on("data", (c: Buffer) => chunks.push(c));
  const done = new Promise<Buffer>((resolve) => doc.on("end", () => resolve(Buffer.concat(chunks))));

  doc.fontSize(16).text(`療育外出 記録(${input.month})`, { align: "center" });
  doc.fontSize(10).fillColor("#555").text(input.officeName, { align: "center" });
  doc.moveDown(1).fillColor("#000");

  const cols = [
    { key: "childName", label: "園児", w: 110 },
    { key: "providerName", label: "事業所", w: 120 },
    { key: "date", label: "日付", w: 90 },
    { key: "out", label: "外出", w: 60 },
    { key: "ret", label: "戻り", w: 60 },
    { key: "duration", label: "所要", w: 70 },
    { key: "warning", label: "警告", w: 90 },
  ] as const;

  const startX = doc.x;
  let y = doc.y;
  const rowH = 20;

  const drawRow = (vals: string[], bold: boolean, shade: boolean) => {
    if (shade) {
      doc.rect(startX, y - 2, cols.reduce((a, c) => a + c.w, 0), rowH).fill("#FDECEC");
      doc.fillColor("#000");
    }
    let x = startX;
    doc.fontSize(bold ? 10 : 9);
    cols.forEach((c, i) => {
      doc.text(vals[i] ?? "", x + 2, y, { width: c.w - 4, ellipsis: true });
      x += c.w;
    });
    y += rowH;
    if (y > doc.page.height - 40) {
      doc.addPage();
      y = doc.y;
    }
  };

  drawRow(cols.map((c) => c.label), true, false);
  doc.moveTo(startX, y - 2).lineTo(startX + cols.reduce((a, c) => a + c.w, 0), y - 2).stroke();
  for (const r of input.rows) {
    drawRow(cols.map((c) => (r as unknown as Record<string, string>)[c.key] ?? ""), false, Boolean(r.warning));
  }

  doc.end();
  return done;
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const pdf = await generatePdf({
      officeName: body.officeName ?? "",
      month: body.month ?? "",
      rows: (body.rows ?? []) as Row[],
    });
    return new NextResponse(new Uint8Array(pdf), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename="therapy-records.pdf"`,
      },
    });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: "PDF生成に失敗しました" }, { status: 500 });
  }
}
