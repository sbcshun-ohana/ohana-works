import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // pdfkit は new PDFDocument() 時に __dirname 相対で data/*.afm(標準フォント metrics)を
  // fs.readFileSync する。Next/Turbopack がバンドルすると __dirname が実 node_modules を
  // 指さず ENOENT→500(療育QR・療育記録PDF)。native require させてバンドル対象外にする。
  // fontkit(registerFont/woff2 で使用)も同様の動的読み込みをするため併せて外部化。
  serverExternalPackages: ["pdfkit", "fontkit"],
  // PDFルートが fs で読む日本語フォント(src/assets/fonts)は、既定では Vercel の
  // サーバレス関数バンドルに含まれず本番で ENOENT→500 になる(dev はソースが在るので通る=
  // d91a315 の __dirname 破壊と同種の罠)。route glob → project root 相対 glob で明示同梱し、
  // process.cwd() 相対の読み込みを本番でも解決させる。
  outputFileTracingIncludes: {
    "/api/childcare/therapy-qr": ["src/assets/fonts/**/*"],
    "/api/childcare/therapy-records-pdf": ["src/assets/fonts/**/*"],
  },
};

export default nextConfig;
