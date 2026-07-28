// 保護者アプリ Phase A: プッシュ通知送信(FCM経由・iOS/Android共通)。
// OFF不可(強制配信)カテゴリはguardian_notification_settingsのenabled=falseを無視して送る
// (緊急連絡・災害・休園・発熱・未降園・感染症・引渡し・重要事項確認)。
// 送信結果は既存notificationsテーブル(target_guardian_id/target_employee_id)に記録する。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { sendFcmPush } from "../_shared/push.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

const FORCE_DELIVER_CATEGORIES = new Set([
  "emergency_contact",
  "disaster",
  "closure",
  "fever",
  "not_picked_up",
  "infectious_disease",
  "handover",
  "important_confirmation",
  "family_daily_report_required",
]);

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const body = await req.json();
    const guardianId = body.guardian_id as string | undefined;
    const employeeId = body.employee_id as string | undefined;
    const category = body.category as string | undefined;
    const title = body.title as string | undefined;
    const messageBody = body.body as string | undefined;
    const data = body.data as Record<string, string> | undefined;

    if ((!guardianId && !employeeId) || !category || !title) {
      return new Response(
        JSON.stringify({ error: "guardian_id/employee_idのいずれかと、category/titleが必要です" }),
        { status: 400, headers },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = getServiceSecretKey();
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    if (guardianId && !FORCE_DELIVER_CATEGORIES.has(category)) {
      const { data: setting } = await adminClient
        .from("guardian_notification_settings")
        .select("enabled")
        .eq("guardian_id", guardianId)
        .eq("category", category)
        .maybeSingle();
      if (setting && setting.enabled === false) {
        return new Response(
          JSON.stringify({ skipped: true, reason: "notification disabled by guardian" }),
          { headers: { ...headers, "Content-Type": "application/json" } },
        );
      }
    }

    const tokensQuery = adminClient.from("push_device_tokens").select("fcm_token");
    const { data: tokens } = guardianId
      ? await tokensQuery.eq("guardian_id", guardianId)
      : await tokensQuery.eq("employee_id", employeeId);

    let sentCount = 0;
    let lastError: string | undefined;
    for (const t of tokens ?? []) {
      const result = await sendFcmPush({
        fcmToken: t.fcm_token,
        title,
        body: messageBody ?? "",
        data,
      });
      if (result.ok) sentCount++;
      else lastError = result.error;
    }

    await adminClient.from("notifications").insert({
      notification_type: category,
      title,
      body: messageBody ?? null,
      channels: ["fcm", "in_app"],
      target_employee_id: employeeId ?? null,
      target_guardian_id: guardianId ?? null,
      payload: data ?? {},
      status: sentCount > 0 ? "sent" : "failed",
      sent_at: sentCount > 0 ? new Date().toISOString() : null,
    });

    return new Response(
      JSON.stringify({
        sent_count: sentCount,
        device_count: (tokens ?? []).length,
        last_error: lastError,
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "通知送信に失敗しました" }),
      { status: 500, headers },
    );
  }
});
