// 9.3 代理打刻: スマホ非所持・故障・圏外時、iPad側の管理者コード(職員ごとの個別PIN)入力による代理打刻。
// 立会いを前提とし、イベントログ記録(proxy_punchesは監査トリガー対象)・
// 管理者確認対象アラートを発報する。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { sha256Hex } from "../_shared/hash.ts";
import { recordPunch } from "../_shared/record-punch.ts";

const VALID_PUNCH_TYPES = ["clock_in", "break_start", "break_end", "clock_out"];

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const { employee_number, admin_pin, punch_type, device_id } = await req
      .json();
    if (!employee_number || !admin_pin || !punch_type || !device_id) {
      return new Response(
        JSON.stringify({
          error: "employee_number/admin_pin/punch_type/device_idが必要です",
        }),
        { status: 400, headers },
      );
    }
    if (!VALID_PUNCH_TYPES.includes(punch_type)) {
      return new Response(
        JSON.stringify({ error: "不正な打刻種別です" }),
        { status: 400, headers },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
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

    // 管理者コード(個別PIN)照合: ソルト付きハッシュのため候補を総当たりで照合する
    const { data: credentials } = await adminClient
      .from("proxy_punch_credentials")
      .select("employee_id, code_salt, code_hash")
      .eq("is_active", true);

    let proxyOperatorId: string | null = null;
    for (const cred of credentials ?? []) {
      const candidateHash = await sha256Hex(cred.code_salt + admin_pin);
      if (candidateHash === cred.code_hash) {
        proxyOperatorId = cred.employee_id;
        break;
      }
    }
    if (!proxyOperatorId) {
      return new Response(
        JSON.stringify({ error: "管理者コードが正しくありません" }),
        { status: 403, headers },
      );
    }

    const { data: employee } = await adminClient
      .from("employees")
      .select("id, name")
      .eq("employee_number", employee_number)
      .is("resignation_date", null)
      .maybeSingle();
    if (!employee) {
      return new Response(
        JSON.stringify({ error: "職員番号が見つかりません" }),
        { status: 404, headers },
      );
    }

    const { punchedAt } = await recordPunch(adminClient, {
      employeeId: employee.id,
      deviceId: device_id,
      officeId: device.office_id,
      punchType: punch_type,
      source: "proxy",
    });

    await adminClient.from("proxy_punches").insert({
      employee_id: employee.id,
      device_id,
      punch_type,
      punched_at: punchedAt.toISOString(),
      proxy_operator_id: proxyOperatorId,
    });

    const { data: rule } = await adminClient
      .from("alert_rules")
      .select("id")
      .eq("alert_key", "proxy_punch_used")
      .maybeSingle();
    if (rule) {
      await adminClient.from("alerts").insert({
        alert_rule_id: rule.id,
        target_employee_id: employee.id,
        target_office_id: device.office_id,
        context: { proxy_operator_id: proxyOperatorId, punch_type, device_id },
      });
    }

    return new Response(
      JSON.stringify({
        employee_name: employee.name,
        punch_type,
        message: "代理打刻を記録しました",
        punched_at: punchedAt.toISOString(),
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "代理打刻に失敗しました" }),
      { status: 500, headers },
    );
  }
});
