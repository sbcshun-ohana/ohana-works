import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // pdfkit は new PDFDocument() 時に __dirname 相対で data/*.afm(標準フォント metrics)を
  // fs.readFileSync する。Next/Turbopack がバンドルすると __dirname が実 node_modules を
  // 指さず ENOENT→500(療育QR・療育記録PDF)。native require させてバンドル対象外にする。
  // fontkit(registerFont/woff2 で使用)も同様の動的読み込みをするため併せて外部化。
  serverExternalPackages: ["pdfkit", "fontkit"],
};

export default nextConfig;
