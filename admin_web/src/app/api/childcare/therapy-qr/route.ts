import fs from "fs";
import path from "path";
import PDFDocument from "pdfkit";
import QRCode from "qrcode";
import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

// pdfkit は woff2 を正しくサブセット化できず(glyf破損)、埋め込みは肥大化するのに
// 日本語グリフが描画されない(=PDF白紙。ToUnicodeは残るため pdftotext では文字が取れる)。
// TTF/OTF なら必要グリフのみ正しくサブセットされ描画される。woff2 から変換した TTF を使う。
const FONT_PATH = path.join(process.cwd(), "src/assets/fonts/NotoSansJP-Regular.ttf");

// 療育送迎用QRカード(A6程度)。QRは "therapy:" + token(発行RPCが返した生token)。
// このルートはレンダリング専用(DBに触れない)。token発行・権限は client の issue_therapy_qr が担う。
async function generateCardPdf(input: {
  token: string;
  childName: string;
  providerName: string;
  officeName: string;
  issueDate: string;
}): Promise<Buffer> {
  const fontBuffer = fs.readFileSync(FONT_PATH);
  // A6 = 297.64 x 419.53 pt
  const doc = new PDFDocument({ size: "A6", margin: 24 });
  doc.registerFont("NotoSansJP", fontBuffer);
  doc.font("NotoSansJP");

  const chunks: Buffer[] = [];
  doc.on("data", (c: Buffer) => chunks.push(c));
  const done = new Promise<Buffer>((resolve) => doc.on("end", () => resolve(Buffer.concat(chunks))));

  // 玄関/受け渡しで他者の目に触れうる物理カード。機微配慮で「療育」語を出さず「送迎用」とする
  // (俊承認 2026-08-12)。事業所名・園児名・園名・発行日は取り違え防止のため維持。
  doc.fontSize(11).fillColor("#7A5FC0").text("送迎用", { align: "center" });
  doc.moveDown(0.3);
  doc.fontSize(16).fillColor("#000").text(input.childName, { align: "center" });
  doc.moveDown(0.2);
  doc.fontSize(11).fillColor("#555").text(input.providerName, { align: "center" });
  doc.moveDown(0.6);

  const qrBuffer = await QRCode.toBuffer(`therapy:${input.token}`, { type: "png", width: 360, margin: 1 });
  const qrSize = 200;
  const x = (doc.page.width - qrSize) / 2;
  doc.image(qrBuffer, x, doc.y, { width: qrSize, height: qrSize });
  doc.y += qrSize + 10;

  doc.fontSize(9).fillColor("#555");
  doc.text(`園名: ${input.officeName}`, { align: "center" });
  doc.text(`発行日: ${input.issueDate}`, { align: "center" });

  doc.end();
  return done;
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { token, childName, providerName, officeName, issueDate } = body ?? {};
    if (!token || !childName || !providerName) {
      return NextResponse.json({ error: "token/childName/providerName が必要です" }, { status: 400 });
    }
    const pdf = await generateCardPdf({
      token,
      childName,
      providerName,
      officeName: officeName ?? "",
      issueDate: issueDate ?? "",
    });
    return new NextResponse(new Uint8Array(pdf), {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename="therapy-qr.pdf"`,
      },
    });
  } catch (e) {
    console.error(e);
    return NextResponse.json({ error: "PDF生成に失敗しました" }, { status: 500 });
  }
}
