// 保護者アプリ Phase A: 動的QR発行(変更6)。既存issue-qr-token(職員用)と同じ設計。
// - サーバー発行の署名付きトークン(HMAC/HS256)、有効期限90秒
// - 発行のたびに、その園児の未使用トークンは失効させ、常に有効なトークンを1件に保つ
// - guardian_qr_tokensへの書込はRLS対象外(service role専用)。クライアントは本Functionを経由する。
//
// 事前準備: `supabase secrets set GUARDIAN_QR_TOKEN_SECRET=<十分な長さのランダム文字列>`

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { sha256Hex } from "../_shared/hash.ts";

const QR_TOKEN_TTL_SECONDS = 90; // 変更6: 60〜90秒

async function importHmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "認証情報がありません" }), {
        status: 401,
        headers,
      });
    }

    const body = await req.json();
    const childId = body.child_id as string | undefined;
    if (!childId) {
      return new Response(JSON.stringify({ error: "child_idが必要です" }), {
        status: 400,
        headers,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const tokenSecret = Deno.env.get("GUARDIAN_QR_TOKEN_SECRET");
    if (!tokenSecret) {
      throw new Error("GUARDIAN_QR_TOKEN_SECRET が未設定です");
    }

    // 呼び出し元ユーザーの検証には anon キー + 転送された Authorization ヘッダを使用する
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await callerClient.auth.getUser();
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "認証に失敗しました" }), {
        status: 401,
        headers,
      });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: guardian } = await adminClient
      .from("guardians")
      .select("id, status")
      .eq("auth_user_id", userData.user.id)
      .maybeSingle();
    if (!guardian || guardian.status !== "active") {
      return new Response(
        JSON.stringify({ error: "保護者情報が見つからないか、アカウントが停止されています" }),
        { status: 403, headers },
      );
    }

    const { data: link } = await adminClient
      .from("guardian_child_links")
      .select("child_id")
      .eq("guardian_id", guardian.id)
      .eq("child_id", childId)
      .maybeSingle();
    if (!link) {
      return new Response(JSON.stringify({ error: "この園児へのアクセス権がありません" }), {
        status: 403,
        headers,
      });
    }

    // 未使用の旧トークンは失効させる(既存issue-qr-tokenと同じ方針)
    await adminClient
      .from("guardian_qr_tokens")
      .update({ status: "expired" })
      .eq("child_id", childId)
      .eq("status", "issued");

    const jti = crypto.randomUUID();
    const issuedAt = new Date();
    const expiresAt = new Date(issuedAt.getTime() + QR_TOKEN_TTL_SECONDS * 1000);

    const key = await importHmacKey(tokenSecret);
    const jwt = await create(
      { alg: "HS256", typ: "JWT" },
      {
        type: "guardian",
        guardian_id: guardian.id,
        child_id: childId,
        jti,
        iat: getNumericDate(issuedAt),
        exp: getNumericDate(expiresAt),
      },
      key,
    );

    const tokenHash = await sha256Hex(jwt);

    const { error: insertError } = await adminClient.from("guardian_qr_tokens").insert({
      guardian_id: guardian.id,
      child_id: childId,
      token_hash: tokenHash,
      issued_at: issuedAt.toISOString(),
      expires_at: expiresAt.toISOString(),
      status: "issued",
    });
    if (insertError) throw insertError;

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
      JSON.stringify({ error: "QRコードの発行に失敗しました" }),
      { status: 500, headers },
    );
  }
});
