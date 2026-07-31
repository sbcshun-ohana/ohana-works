// 要件3: 職員ピッカー。登録済み保育業務端末(devices)の office に保育業務アクセスがある
// 在籍職員を氏名+役職+PIN設定有無で返す。認証前(ログイン画面)から端末IDで呼ぶため
// service role で実行し、pin_hash 等の機微は一切返さない。
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  try {
    const { device_id } = await req.json();
    if (!device_id || typeof device_id !== "string") {
      return json({ error: "device_id が必要です" }, 400, headers);
    }
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, getServiceSecretKey());

    const { data: device } = await admin
      .from("devices").select("id, office_id, status").eq("id", device_id).maybeSingle();
    if (!device || device.status !== "enabled") {
      return json({ error: "この端末は登録されていないか無効です" }, 403, headers);
    }
    const officeId = device.office_id as string;
    const ids = await staffIdsWithOfficeAccess(admin, officeId);
    if (ids.length === 0) return json({ office_id: officeId, staff: [] }, 200, headers);

    const { data: emps } = await admin
      .from("employees").select("id, name, resignation_date").in("id", ids);
    const { data: roleRows } = await admin
      .from("employee_roles").select("employee_id, roles!inner(code, sort_order)").in("employee_id", ids);
    const topRole = new Map<string, { code: string; sort: number }>();
    for (const r of roleRows ?? []) {
      const code = (r as { roles: { code: string; sort_order: number } }).roles.code;
      const sort = (r as { roles: { code: string; sort_order: number } }).roles.sort_order;
      const cur = topRole.get(r.employee_id as string);
      if (!cur || sort < cur.sort) topRole.set(r.employee_id as string, { code, sort });
    }
    const { data: pins } = await admin.from("staff_pins").select("employee_id").in("employee_id", ids);
    const hasPin = new Set((pins ?? []).map((p) => p.employee_id as string));

    const staff = (emps ?? [])
      .filter((e) => e.resignation_date == null)
      .map((e) => ({
        employee_id: e.id,
        name: e.name,
        role_code: topRole.get(e.id as string)?.code ?? null,
        has_pin: hasPin.has(e.id as string),
      }))
      .sort((a, b) => String(a.name).localeCompare(String(b.name), "ja"));

    return json({ office_id: officeId, staff }, 200, headers);
  } catch (e) {
    console.error("pin-staff-picker error", e instanceof Error ? e.message : "unknown");
    return json({ error: "職員一覧の取得に失敗しました" }, 500, headers);
  }
});

/// office に保育業務アクセスがある職員ID集合(所属 or 管理ロール or 多施設付与)。
export async function staffIdsWithOfficeAccess(admin: SupabaseClient, officeId: string): Promise<string[]> {
  const ids = new Set<string>();
  const today = new Date().toISOString().slice(0, 10);

  const { data: assigns } = await admin
    .from("employee_office_assignments").select("employee_id, start_date, end_date").eq("office_id", officeId);
  for (const a of assigns ?? []) {
    if ((a.start_date as string) <= today && (a.end_date == null || (a.end_date as string) >= today)) {
      ids.add(a.employee_id as string);
    }
  }
  const { data: roleRows } = await admin
    .from("employee_roles").select("employee_id, office_id, roles!inner(code)");
  for (const r of roleRows ?? []) {
    const code = (r as { roles: { code: string } }).roles.code;
    const roleOffice = (r as { office_id: string | null }).office_id;
    if (code === "system_admin" || code === "executive_director") ids.add(r.employee_id as string);
    else if (["director", "chief", "office_manager"].includes(code) && (roleOffice == null || roleOffice === officeId)) {
      ids.add(r.employee_id as string);
    }
  }
  const { data: grants } = await admin
    .from("multi_office_authority_grants").select("grantee_employee_id").eq("office_id", officeId).is("revoked_at", null);
  for (const g of grants ?? []) ids.add(g.grantee_employee_id as string);

  return [...ids];
}

function json(body: unknown, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(body), { status, headers: { ...headers, "Content-Type": "application/json" } });
}
