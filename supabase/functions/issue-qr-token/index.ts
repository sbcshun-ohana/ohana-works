// 9.2 ワンタイムQR発行(確定仕様、開発計画改訂版 2026-07-17 Phase1 B-1で90秒方式に変更)
// - サーバー発行の署名付きトークン(JWT/HS256)、有効期限90秒(保護者QRと同じ仕様)
// - 発行のたびに、その職員の未使用トークンは失効させ、常に有効なトークンを1件に保つ
// - qr_tokens への書込はRLS対象外(service role専用)。クライアントは本Functionを経由する。
//
// 事前準備: `supabase secrets set QR_TOKEN_SECRET=<十分な長さのランダム文字列>`

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

const QR_TOKEN_TTL_SECONDS = 90; // 90秒(保護者QRのissue-guardian-qr-tokenと同じ仕様)

function corsHeaders(origin: string | null) {
  return {
    "Access-Control-Allow-Origin": origin ?? "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

async function importHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "認証情報がありません" }), {
        status: 401,
        headers,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = getServiceSecretKey();
    const tokenSecret = Deno.env.get("QR_TOKEN_SECRET");
    if (!tokenSecret) {
      throw new Error("QR_TOKEN_SECRET が未設定です");
    }

    // 呼び出し元ユーザーの検証には anon キー + 転送された Authorization ヘッダを使用する
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await callerClient.auth
      .getUser();
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "認証に失敗しました" }), {
        status: 401,
        headers,
      });
    }

    // qr_tokens への書込みは service role 専用(職員本人にもINSERT権限を与えない)
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: employee, error: employeeError } = await adminClient
      .from("employees")
      .select("id")
      .eq("auth_user_id", userData.user.id)
      .is("resignation_date", null)
      .maybeSingle();

    if (employeeError || !employee) {
      return new Response(
        JSON.stringify({ error: "職員情報が見つかりません" }),
        { status: 403, headers },
      );
    }

    // 未使用の旧トークンは失効させる
    await adminClient
      .from("qr_tokens")
      .update({ status: "expired" })
      .eq("employee_id", employee.id)
      .eq("status", "issued");

    const jti = crypto.randomUUID();
    const issuedAt = new Date();
    const expiresAt = new Date(
      issuedAt.getTime() + QR_TOKEN_TTL_SECONDS * 1000,
    );

    const key = await importHmacKey(tokenSecret);
    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        employee_id: employee.id,
        jti,
        iat: getNumericDate(issuedAt),
        exp: getNumericDate(expiresAt),
      },
      key,
    );

    const tokenHash = await sha256Hex(jwt);

    const { error: insertError } = await adminClient.from("qr_tokens")
      .insert({
        employee_id: employee.id,
        token_hash: tokenHash,
        issued_at: issuedAt.toISOString(),
        expires_at: expiresAt.toISOString(),
        status: "issued",
      });

    if (insertError) {
      throw insertError;
    }

    return new Response(
      JSON.stringify({
        token: jwt,
        issued_at: issuedAt.toISOString(),
        expires_at: expiresAt.toISOString(),
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "QRトークンの発行に失敗しました" }),
      { status: 500, headers },
    );
  }
});
