// P0: イベント駆動プッシュ通知の自動化。
// notifications(outbox)のpending行(および再送対象のfailed行)をまとめて取得し、
// push_device_tokensと突合してFCMへ並列送信する。定期実行はSupabase Cron Triggerを想定
// (このファイル自体はどこからでも叩ける単純なHTTPハンドラ)。
//
// send-push-notification(1リクエスト=1人宛)は管理者Webからの単発テスト送信用に残し、
// 業務イベント発火時の自動配信はすべてこちら(outbox一括処理)に統一する。
//
// guardian_notification_settingsの配信可否チェックは現時点では未実装。
// このoutboxへ行を積んでいるのは現状すべて職員(target_employee_id)宛の通知のみ
// (給与明細公開・申請結果・シフト変更・お知らせ)で、保護者(target_guardian_id)宛の行は
// まだ生成されていないため。保護者向けイベントをoutbox経由に移行する際に追加すること。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { sendFcmPush } from "../_shared/push.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

const MAX_RETRY = 5;
const BATCH_LIMIT = 200;

function toDataPayload(notificationType: string, payload: unknown): Record<string, string> {
  const result: Record<string, string> = { type: notificationType };
  if (payload && typeof payload === "object") {
    for (const [key, value] of Object.entries(payload as Record<string, unknown>)) {
      if (value !== null && value !== undefined) result[key] = String(value);
    }
  }
  return result;
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = getServiceSecretKey();
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: pending, error } = await adminClient
      .from("notifications")
      .select("id, notification_type, title, body, payload, target_employee_id, target_guardian_id, retry_count")
      .or(`status.eq.pending,and(status.eq.failed,retry_count.lt.${MAX_RETRY})`)
      .order("created_at", { ascending: true })
      .limit(BATCH_LIMIT);

    if (error) throw error;
    if (!pending || pending.length === 0) {
      return new Response(
        JSON.stringify({ processed: 0, sent: 0, failed: 0 }),
        { headers: { ...headers, "Content-Type": "application/json" } },
      );
    }

    const employeeIds = [...new Set(pending.filter((n) => n.target_employee_id).map((n) => n.target_employee_id as string))];
    const guardianIds = [...new Set(pending.filter((n) => n.target_guardian_id).map((n) => n.target_guardian_id as string))];

    const tokenFilters = [
      employeeIds.length > 0 ? `employee_id.in.(${employeeIds.join(",")})` : null,
      guardianIds.length > 0 ? `guardian_id.in.(${guardianIds.join(",")})` : null,
    ].filter((f): f is string => f !== null);

    const tokensByEmployee = new Map<string, string[]>();
    const tokensByGuardian = new Map<string, string[]>();

    if (tokenFilters.length > 0) {
      const { data: tokens, error: tokenError } = await adminClient
        .from("push_device_tokens")
        .select("employee_id, guardian_id, fcm_token")
        .or(tokenFilters.join(","));
      if (tokenError) throw tokenError;

      for (const t of tokens ?? []) {
        if (t.employee_id) {
          const arr = tokensByEmployee.get(t.employee_id) ?? [];
          arr.push(t.fcm_token);
          tokensByEmployee.set(t.employee_id, arr);
        }
        if (t.guardian_id) {
          const arr = tokensByGuardian.get(t.guardian_id) ?? [];
          arr.push(t.fcm_token);
          tokensByGuardian.set(t.guardian_id, arr);
        }
      }
    }

    let sentCount = 0;
    let failedCount = 0;

    await Promise.all(pending.map(async (n) => {
      const tokens = n.target_employee_id
        ? tokensByEmployee.get(n.target_employee_id) ?? []
        : tokensByGuardian.get(n.target_guardian_id ?? "") ?? [];

      let successCount = 0;
      for (const token of tokens) {
        const result = await sendFcmPush({
          fcmToken: token,
          title: n.title,
          body: n.body ?? "",
          data: toDataPayload(n.notification_type, n.payload),
        });
        if (result.ok) successCount++;
      }

      if (successCount > 0) {
        await adminClient.from("notifications").update({ status: "sent", sent_at: new Date().toISOString() }).eq("id", n.id);
        sentCount++;
      } else {
        await adminClient.from("notifications").update({ status: "failed", retry_count: (n.retry_count ?? 0) + 1 }).eq("id", n.id);
        failedCount++;
      }
    }));

    return new Response(
      JSON.stringify({ processed: pending.length, sent: sentCount, failed: failedCount }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "通知配信処理に失敗しました" }),
      { status: 500, headers },
    );
  }
});
