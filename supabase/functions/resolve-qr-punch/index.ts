// 10章 iPad勤怠画面仕様: QR読取 → 自動判定
// 9.2 QRトークンの検証・single-use消費(この時点で使用済みにする)。
// JWT検証なし(共有端末からの呼び出しのため。device_idの有効性で保護する)。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { sha256Hex } from "../_shared/hash.ts";
import { tokyoDayBounds } from "../_shared/tokyo.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

type PunchRow = { punch_type: string; punched_at: string };

function importHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

function determineCandidates(punches: PunchRow[]): string[] {
  if (punches.length === 0) return ["clock_in"];
  const last = punches[punches.length - 1].punch_type;
  if (last === "clock_in" || last === "break_end") {
    return ["break_start", "clock_out"];
  }
  if (last === "break_start") return ["break_end"];
  // last === "clock_out": 退勤後の再読取
  return ["clock_in", "mistake", "admin_review"];
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const { token, device_id } = await req.json();
    if (!token || !device_id) {
      return new Response(
        JSON.stringify({ error: "token/device_idが必要です" }),
        { status: 400, headers },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = getServiceSecretKey();
    const tokenSecret = Deno.env.get("QR_TOKEN_SECRET");
    if (!tokenSecret) throw new Error("QR_TOKEN_SECRET が未設定です");

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // 端末の有効性確認
    const { data: device } = await adminClient
      .from("devices")
      .select("id, status, office_id")
      .eq("id", device_id)
      .maybeSingle();
    if (!device || device.status !== "enabled") {
      return new Response(
        JSON.stringify({ error: "端末が無効です" }),
        { status: 403, headers },
      );
    }

    // JWT署名・有効期限検証
    const key = await importHmacKey(tokenSecret);
    let payload: { employee_id?: string };
    try {
      payload = await verify(token, key) as { employee_id?: string };
    } catch {
      return new Response(
        JSON.stringify({ error: "QRコードが無効または期限切れです" }),
        { status: 400, headers },
      );
    }
    if (!payload.employee_id) {
      return new Response(
        JSON.stringify({ error: "QRコードが不正です" }),
        { status: 400, headers },
      );
    }

    // single-use消費: このタイミングでstatus='used'に更新する。
    // 既に使用済み/失効済みのトークン(スクショ再利用等)はここで弾かれる。
    const tokenHash = await sha256Hex(token);
    const { data: qrToken, error: qrTokenError } = await adminClient
      .from("qr_tokens")
      .select("id, employee_id, status, expires_at")
      .eq("token_hash", tokenHash)
      .maybeSingle();

    if (qrTokenError || !qrToken || qrToken.status !== "issued") {
      return new Response(
        JSON.stringify({ error: "このQRコードは既に使用済みか無効です" }),
        { status: 409, headers },
      );
    }
    if (new Date(qrToken.expires_at).getTime() < Date.now()) {
      return new Response(
        JSON.stringify({ error: "QRコードの有効期限が切れています" }),
        { status: 400, headers },
      );
    }

    const { error: consumeError } = await adminClient
      .from("qr_tokens")
      .update({ status: "used", used_at: new Date().toISOString(), used_by_device_id: device_id })
      .eq("id", qrToken.id)
      .eq("status", "issued"); // 二重消費防止(競合時はaffected rows=0)

    if (consumeError) throw consumeError;

    const { data: employee } = await adminClient
      .from("employees")
      .select("id, name")
      .eq("id", qrToken.employee_id)
      .maybeSingle();

    if (!employee) {
      return new Response(
        JSON.stringify({ error: "職員情報が見つかりません" }),
        { status: 404, headers },
      );
    }

    const { startUtc, endUtc } = tokyoDayBounds();
    const { data: todaysPunches } = await adminClient
      .from("time_punches")
      .select("punch_type, punched_at")
      .eq("employee_id", employee.id)
      .gte("punched_at", startUtc.toISOString())
      .lt("punched_at", endUtc.toISOString())
      .order("punched_at", { ascending: true });

    const candidates = determineCandidates((todaysPunches ?? []) as PunchRow[]);

    return new Response(
      JSON.stringify({
        employee_id: employee.id,
        employee_name: employee.name,
        candidates,
        confirmation_token: qrToken.id,
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "QRコードの検証に失敗しました" }),
      { status: 500, headers },
    );
  }
});
