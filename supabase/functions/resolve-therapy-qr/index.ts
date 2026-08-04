// 療育外出・戻り登録 §3: 療育固定QRの resolve(キオスク)。
// 保護者QR(回転JWT)とは別 Function として実装し、resolve-guardian-qr には手を入れない。
// QR payload は "therapy:" + 固定token(推測不能ランダム)。token は保存せず token_hash(hex sha256)で照合。
// バリデーション順(§3.2): token有効/未revoke → 適用期間内(当日) → 登園中(present) →
//   トグル(外出中でなければout・外出中ならreturn) → 60秒以内の同種連続打刻は無視。
// 保護者通知は一切送らない(notifications に積まない)。立会記録は不要(QR打刻のみ)。
// 機能フラグOFF施設は拒否(§6: OFF施設で機能を露出しない)。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { sha256Hex } from "../_shared/hash.ts";
import { tokyoDayBounds } from "../_shared/tokyo.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

const DUP_WINDOW_MS = 60 * 1000;

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const body = await req.json();
    const device_id = body.device_id as string | undefined;
    let token = body.token as string | undefined;
    if (!token || !device_id) {
      return new Response(JSON.stringify({ error: "token/device_idが必要です" }), { status: 400, headers });
    }
    // "therapy:" プレフィックスを剥がす(キオスクが付けたまま送ってきても許容)。
    if (token.startsWith("therapy:")) token = token.slice("therapy:".length);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const adminClient = createClient(supabaseUrl, getServiceSecretKey());

    const { data: device } = await adminClient
      .from("devices").select("id, status").eq("id", device_id).maybeSingle();
    if (!device || device.status !== "enabled") {
      return new Response(JSON.stringify({ error: "端末が無効です" }), { status: 403, headers });
    }

    // 1) token 照合(hex sha256)・未revoke
    const tokenHash = await sha256Hex(token);
    const { data: qr } = await adminClient
      .from("therapy_outing_qr_codes")
      .select("id, child_id, provider_id, revoked_at")
      .eq("token_hash", tokenHash)
      .maybeSingle();
    if (!qr || qr.revoked_at) {
      return new Response(
        JSON.stringify({ accepted: false, reason: "invalid_qr", message: "無効なQRです。職員にお声がけください" }),
        { headers: { ...headers, "Content-Type": "application/json" } },
      );
    }

    const { data: child } = await adminClient
      .from("children").select("id, display_name, honorific_suffix_resolved, office_id")
      .eq("id", qr.child_id).maybeSingle();
    const { data: provider } = await adminClient
      .from("therapy_providers").select("id, name").eq("id", qr.provider_id).maybeSingle();
    if (!child || !provider) {
      return new Response(JSON.stringify({ accepted: false, reason: "invalid_qr", message: "無効なQRです。職員にお声がけください" }),
        { headers: { ...headers, "Content-Type": "application/json" } });
    }

    // 機能フラグ(施設)OFF は拒否
    const { data: enabled } = await adminClient.rpc("is_therapy_outing_enabled_for_office", { p_office_id: child.office_id });
    if (!enabled) {
      return new Response(JSON.stringify({ accepted: false, reason: "disabled", message: "この施設では療育外出は無効です" }),
        { headers: { ...headers, "Content-Type": "application/json" } });
    }

    const { dateStr, startUtc, endUtc } = tokyoDayBounds();

    // 2) 適用期間内(当日基準・児×事業者)
    const { data: setting } = await adminClient
      .from("child_therapy_settings")
      .select("id")
      .eq("child_id", qr.child_id)
      .eq("provider_id", qr.provider_id)
      .lte("start_date", dateStr)
      .or(`end_date.is.null,end_date.gte.${dateStr}`)
      .limit(1)
      .maybeSingle();
    if (!setting) {
      return new Response(JSON.stringify({ accepted: false, reason: "out_of_period", message: "療育の適用期間外です" }),
        { headers: { ...headers, "Content-Type": "application/json" } });
    }

    // 3) 登園中(present)であること
    const { data: dcs } = await adminClient
      .from("daily_child_status").select("status")
      .eq("child_id", qr.child_id).eq("business_date", dateStr).maybeSingle();
    if ((dcs?.status ?? "not_arrived") !== "present") {
      return new Response(JSON.stringify({ accepted: false, reason: "not_present", message: "登園中ではありません" }),
        { headers: { ...headers, "Content-Type": "application/json" } });
    }

    // 4/5) 当日の最終イベント → トグル + 60秒重複無視
    const { data: lastEvents } = await adminClient
      .from("therapy_outing_events")
      .select("event_type, occurred_at")
      .eq("child_id", qr.child_id)
      .gte("occurred_at", startUtc.toISOString())
      .lt("occurred_at", endUtc.toISOString())
      .order("occurred_at", { ascending: false })
      .limit(1);
    const last = lastEvents?.[0];

    if (last && Date.now() - new Date(last.occurred_at).getTime() < DUP_WINDOW_MS) {
      // 直前イベントから60秒以内 = 二重読み取り。記録せず無視。
      return new Response(JSON.stringify({ accepted: false, reason: "duplicate", message: "すでに記録済みです" }),
        { headers: { ...headers, "Content-Type": "application/json" } });
    }

    const eventType = last?.event_type === "out" ? "return" : "out";
    const occurredAt = new Date();

    await adminClient.from("therapy_outing_events").insert({
      child_id: qr.child_id,
      provider_id: qr.provider_id,
      event_type: eventType,
      occurred_at: occurredAt.toISOString(),
      source: "kiosk_qr",
      qr_code_id: qr.id,
    });

    return new Response(
      JSON.stringify({
        accepted: true,
        event_type: eventType,
        child_name: child.display_name,
        honorific_suffix: child.honorific_suffix_resolved,
        provider_name: provider.name,
        occurred_at: occurredAt.toISOString(),
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: "療育QRの処理に失敗しました" }), { status: 500, headers });
  }
});
