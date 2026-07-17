// クラス写真(変更7): クレジット透かし入り画像のみを保存し、元画像はサーバーへ送信しない。
// ブラウザのCanvasで透かしを合成してからアップロードする。

export async function watermarkImage(file: File): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const canvas = document.createElement("canvas");
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("canvas context is not available");

  ctx.drawImage(bitmap, 0, 0);

  const fontSize = Math.max(16, Math.round(canvas.width * 0.025));
  ctx.font = `${fontSize}px sans-serif`;
  ctx.textAlign = "right";
  ctx.textBaseline = "bottom";
  const text = "© Ohana Co., Ltd.";
  const padding = fontSize;

  ctx.fillStyle = "rgba(0, 0, 0, 0.35)";
  ctx.fillText(text, canvas.width - padding + 1, canvas.height - padding + 1);
  ctx.fillStyle = "rgba(255, 255, 255, 0.85)";
  ctx.fillText(text, canvas.width - padding, canvas.height - padding);

  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("failed to encode image"))),
      "image/jpeg",
      0.9,
    );
  });
}
