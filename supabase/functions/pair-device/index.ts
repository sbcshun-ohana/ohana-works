// 9.1 端末マスタとのペアリング
// iPadキオスクアプリの初回セットアップ時に、管理者が devices テーブルへ事前登録した
// device_code を入力し、その端末の office_id 等を取得してローカル保存する。
// JWT検証なし(職員としてログインしていない共有端末からの呼び出しのため)。
// devices は「有効・無効」の切替のみで運用され、device_codeそのものは強い秘密情報ではない
// (実際の打刻はQRトークン or 個別PINでの検証が必要なため、ペアリングだけでは何もできない)。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const { device_code } = await req.json();
    if (!device_code || typeof device_code !== "string") {
      return new Response(
        JSON.stringify({ error: "device_codeを入力してください" }),
        { status: 400, headers },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: device, error } = await adminClient
      .from("devices")
      .select("id, status, office_id, offices(name)")
      .eq("device_code", device_code)
      .maybeSingle();

    if (error || !device) {
      return new Response(
        JSON.stringify({ error: "端末コードが見つかりません" }),
        { status: 404, headers },
      );
    }
    if (device.status !== "enabled") {
      return new Response(
        JSON.stringify({ error: "この端末は無効化されています" }),
        { status: 403, headers },
      );
    }

    const officeName = (device as { offices?: { name?: string } }).offices
      ?.name ?? null;

    return new Response(
      JSON.stringify({
        device_id: device.id,
        office_id: device.office_id,
        office_name: officeName,
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "ペアリングに失敗しました" }),
      { status: 500, headers },
    );
  }
});
