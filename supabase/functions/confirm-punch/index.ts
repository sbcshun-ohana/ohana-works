// 10章: 確認画面で職員がタップ → 打刻確定
// resolve-qr-punch で発行された confirmation_token(=消費済みqr_tokens.id)を検証し、
// 選択された打刻種別で time_punches / daily_attendances を確定する。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { recordPunch } from "../_shared/record-punch.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

const CONFIRMATION_WINDOW_MS = 2 * 60 * 1000; // 古い確認トークンの再利用防止

const PUNCH_MESSAGES: Record<string, string> = {
  clock_in: "出勤しました",
  break_start: "休憩に入ります",
  break_end: "休憩から戻りました",
  clock_out: "退勤しました",
  mistake: "取り消しました。もう一度QRを表示してください",
  admin_review: "管理者確認の依頼を送信しました",
};

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const { confirmation_token, punch_type, device_id } = await req.json();
    if (!confirmation_token || !punch_type || !device_id) {
      return new Response(
        JSON.stringify({ error: "confirmation_token/punch_type/device_idが必要です" }),
        { status: 400, headers },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = getServiceSecretKey();
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

    const { data: qrToken } = await adminClient
      .from("qr_tokens")
      .select("id, employee_id, status, used_at, used_by_device_id")
      .eq("id", confirmation_token)
      .maybeSingle();

    if (
      !qrToken ||
      qrToken.status !== "used" ||
      qrToken.used_by_device_id !== device_id
    ) {
      return new Response(
        JSON.stringify({ error: "確認情報が無効です。最初からやり直してください" }),
        { status: 409, headers },
      );
    }
    if (
      Date.now() - new Date(qrToken.used_at).getTime() >
        CONFIRMATION_WINDOW_MS
    ) {
      return new Response(
        JSON.stringify({ error: "確認がタイムアウトしました。もう一度QRを表示してください" }),
        { status: 408, headers },
      );
    }

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

    let punchedAt: Date | null = null;

    if (
      ["clock_in", "break_start", "break_end", "clock_out"].includes(
        punch_type,
      )
    ) {
      const result = await recordPunch(adminClient, {
        employeeId: employee.id,
        deviceId: device_id,
        officeId: device.office_id,
        punchType: punch_type,
        source: "qr",
        qrTokenId: qrToken.id,
      });
      punchedAt = result.punchedAt;
    } else if (punch_type === "admin_review") {
      const { data: rule } = await adminClient
        .from("alert_rules")
        .select("id")
        .eq("alert_key", "qr_punch_requires_admin_review")
        .maybeSingle();
      if (rule) {
        await adminClient.from("alerts").insert({
          alert_rule_id: rule.id,
          target_employee_id: employee.id,
          target_office_id: device.office_id,
          context: { device_id, qr_token_id: qrToken.id },
        });
      }
    } else if (punch_type !== "mistake") {
      return new Response(
        JSON.stringify({ error: "不正な打刻種別です" }),
        { status: 400, headers },
      );
    }

    return new Response(
      JSON.stringify({
        employee_name: employee.name,
        punch_type,
        message: PUNCH_MESSAGES[punch_type] ?? "処理しました",
        punched_at: punchedAt?.toISOString() ?? null,
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "打刻の確定に失敗しました" }),
      { status: 500, headers },
    );
  }
});
