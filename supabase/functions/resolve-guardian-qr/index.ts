// 保護者アプリ Phase A: 保護者QR読取→登降園判定(変更1・変更6)。
// キオスク端末(共有iPad)からの呼び出しのため、既存resolve-qr-punchと同様
// JWT検証は行わず、device_idの有効性で保護する。
//
// 家庭連絡帳が必須のクラス/園児(is_family_daily_report_required)で、当日の提出が
// 無い場合はdrop_off(登園)を拒否し、'rejected'イベントとして記録する(変更1)。
// 拒否時は保護者へその場でプッシュ通知し、「その場で入力→再提示→登園」の動線を促す。
// 例外処理(災害等)は職員側のadmin_override_attendance_check_in RPCで別途対応する。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { sha256Hex } from "../_shared/hash.ts";
import { tokyoDayBounds } from "../_shared/tokyo.ts";
import { sendFcmPush } from "../_shared/push.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

function importHmacKey(secret: string): Promise<CryptoKey> {
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
    const { token, device_id } = await req.json();
    if (!token || !device_id) {
      return new Response(
        JSON.stringify({ error: "token/device_idが必要です" }),
        { status: 400, headers },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = getServiceSecretKey();
    const tokenSecret = Deno.env.get("GUARDIAN_QR_TOKEN_SECRET");
    if (!tokenSecret) throw new Error("GUARDIAN_QR_TOKEN_SECRET が未設定です");

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: device } = await adminClient
      .from("devices")
      .select("id, status, office_id")
      .eq("id", device_id)
      .maybeSingle();
    if (!device || device.status !== "enabled") {
      return new Response(JSON.stringify({ error: "端末が無効です" }), {
        status: 403,
        headers,
      });
    }

    const key = await importHmacKey(tokenSecret);
    let payload: { type?: string; child_id?: string; guardian_id?: string };
    try {
      payload = await verify(token, key) as typeof payload;
    } catch {
      return new Response(
        JSON.stringify({ error: "QRコードが無効または期限切れです" }),
        { status: 400, headers },
      );
    }
    if (payload.type !== "guardian" || !payload.child_id || !payload.guardian_id) {
      return new Response(JSON.stringify({ error: "QRコードが不正です" }), {
        status: 400,
        headers,
      });
    }

    const tokenHash = await sha256Hex(token);
    const { data: qrToken, error: qrTokenError } = await adminClient
      .from("guardian_qr_tokens")
      .select("id, child_id, guardian_id, status, expires_at")
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

    // single-use消費(既存resolve-qr-punkと同じ、二重消費防止のため条件付きUPDATE)
    const { error: consumeError } = await adminClient
      .from("guardian_qr_tokens")
      .update({ status: "used", used_at: new Date().toISOString(), used_by_device_id: device_id })
      .eq("id", qrToken.id)
      .eq("status", "issued");
    if (consumeError) throw consumeError;

    const { data: child } = await adminClient
      .from("children")
      .select("id, display_name, honorific_suffix, gender")
      .eq("id", qrToken.child_id)
      .maybeSingle();
    if (!child) {
      return new Response(JSON.stringify({ error: "園児情報が見つかりません" }), {
        status: 404,
        headers,
      });
    }

    const { dateStr: businessDate } = tokyoDayBounds();

    const { data: dailyStatus } = await adminClient
      .from("daily_child_status")
      .select("status")
      .eq("child_id", child.id)
      .eq("business_date", businessDate)
      .maybeSingle();
    const currentStatus = dailyStatus?.status ?? "not_arrived";

    if (currentStatus === "picked_up") {
      return new Response(
        JSON.stringify({
          accepted: false,
          reason: "already_picked_up",
          message: "本日は既に降園済みです",
        }),
        { headers: { ...headers, "Content-Type": "application/json" } },
      );
    }

    if (currentStatus === "not_arrived") {
      const { data: isRequired } = await adminClient.rpc("is_family_daily_report_required", {
        p_child_id: child.id,
        p_business_date: businessDate,
      });
      if (isRequired) {
        const { data: isSubmitted } = await adminClient.rpc("has_family_daily_report_submitted", {
          p_child_id: child.id,
          p_business_date: businessDate,
        });
        if (!isSubmitted) {
          await adminClient.from("child_attendance_events").insert({
            child_id: child.id,
            event_type: "rejected",
            device_id,
            recorded_by_guardian_id: qrToken.guardian_id,
            rejection_reason: "家庭連絡帳未提出",
          });

          const { data: tokens } = await adminClient
            .from("push_device_tokens")
            .select("fcm_token")
            .eq("guardian_id", qrToken.guardian_id);
          for (const t of tokens ?? []) {
            await sendFcmPush({
              fcmToken: t.fcm_token,
              title: "家庭連絡帳の入力が必要です",
              body: `${child.display_name}さんの登園には、本日分の家庭連絡帳の提出が必要です。`,
              data: { type: "family_daily_report_required", child_id: child.id },
            });
          }

          return new Response(
            JSON.stringify({
              accepted: false,
              reason: "family_daily_report_required",
              child_name: child.display_name,
              message: "家庭連絡帳が未提出のため受付できません。保護者アプリから入力後、再度QRを表示してください。",
            }),
            { headers: { ...headers, "Content-Type": "application/json" } },
          );
        }
      }
    }

    const eventType = currentStatus === "present" ? "pick_up" : "drop_off";

    await adminClient.from("child_attendance_events").insert({
      child_id: child.id,
      event_type: eventType,
      device_id,
      recorded_by_guardian_id: qrToken.guardian_id,
    });
    await adminClient.rpc("refresh_daily_child_status", {
      p_child_id: child.id,
      p_business_date: businessDate,
    });

    return new Response(
      JSON.stringify({
        accepted: true,
        event_type: eventType,
        child_name: child.display_name,
        honorific_suffix: child.honorific_suffix,
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "QRコードの処理に失敗しました" }),
      { status: 500, headers },
    );
  }
});
