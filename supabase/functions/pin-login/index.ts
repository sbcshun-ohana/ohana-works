// 要件3: PIN簡易ログイン。登録端末(device_id)+職員+PINをサーバ側で検証し、
// 成功時のみ magiclink トークンを返す(クライアントは即 verifyOtp でセッション確立)。
// PIN照合は Deno 側で pgcrypto bcrypt ハッシュを比較(pin_hash はクライアントへ返さない)。
// 職員単位ロック(5回/15分)＋端末単位レート制限(10分10回)で複製端末の総当たりを封じる。
// PIN値・トークンはログ・エラーレスポンスに一切出力しない。
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { compareSync } from "https://deno.land/x/bcrypt@v0.4.1/mod.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { getServiceSecretKey } from "../_shared/secret-key.ts";

const EMPLOYEE_MAX_FAILURES = 5;
const EMPLOYEE_LOCK_MS = 15 * 60_000;
const DEVICE_WINDOW_MS = 10 * 60_000;
const DEVICE_MAX_FAILURES = 10;

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  try {
    const { device_id, employee_id, pin } = await req.json();
    if (!device_id || !employee_id || typeof pin !== "string") {
      return json({ error: "入力が不足しています" }, 400, headers);
    }
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, getServiceSecretKey());
    const record = (result: string) =>
      admin.from("pin_login_attempts").insert({ device_id, employee_id, result });

    // 1) 端末の有効性
    const { data: device } = await admin
      .from("devices").select("id, office_id, status").eq("id", device_id).maybeSingle();
    if (!device || device.status !== "enabled") {
      await record("device_invalid");
      return json({ error: "この端末は登録されていないか無効です" }, 403, headers);
    }
    const officeId = device.office_id as string;

    // 2) 端末レート制限(直近10分の失敗系が10回以上 → 拒否)
    const windowStart = new Date(Date.now() - DEVICE_WINDOW_MS).toISOString();
    const { count: recentFailures } = await admin
      .from("pin_login_attempts").select("id", { count: "exact", head: true })
      .eq("device_id", device_id).neq("result", "success").gte("attempted_at", windowStart);
    if ((recentFailures ?? 0) >= DEVICE_MAX_FAILURES) {
      await record("device_rate_limited");
      return json({ error: "試行が多すぎます。しばらくしてからお試しください。" }, 429, headers);
    }

    // 3) 職員のPIN行・ロック
    const { data: sp } = await admin
      .from("staff_pins").select("employee_id, pin_hash, failed_attempts, locked_until")
      .eq("employee_id", employee_id).maybeSingle();
    if (!sp) {
      await record("no_pin");
      return json({ error: "この職員のPINが設定されていません" }, 400, headers);
    }
    if (sp.locked_until && new Date(sp.locked_until as string) > new Date()) {
      await record("locked");
      return json({ error: "アカウントがロックされています。しばらくしてからお試しください。" }, 423, headers);
    }

    // 4) 施設アクセス(所属 or 管理ロール or 多施設付与)
    if (!(await employeeHasAccess(admin, employee_id, officeId))) {
      await record("no_access");
      return json({ error: "この端末の施設ではログインできません" }, 403, headers);
    }

    // 5) PIN照合(pin_hash はDBから出さない=Deno内で比較しクライアントに返さない)
    const ok = compareSync(pin, sp.pin_hash as string);
    if (!ok) {
      const failed = (sp.failed_attempts as number) + 1;
      const lock = failed >= EMPLOYEE_MAX_FAILURES;
      await admin.from("staff_pins").update({
        failed_attempts: lock ? 0 : failed,
        locked_until: lock ? new Date(Date.now() + EMPLOYEE_LOCK_MS).toISOString() : null,
      }).eq("employee_id", employee_id);
      await record("invalid_pin");
      return json(
        { error: lock ? "PINを連続で間違えたためロックしました。管理者にリセットを依頼してください。" : "PINが違います。" },
        401, headers,
      );
    }

    // 6) 成功: 失敗回数リセット → セッション発行(magiclink token_hash を返し、クライアント即verifyOtp)
    await admin.from("staff_pins").update({ failed_attempts: 0, locked_until: null }).eq("employee_id", employee_id);
    const { data: emp } = await admin.from("employees").select("auth_user_id").eq("id", employee_id).maybeSingle();
    if (!emp?.auth_user_id) {
      await record("no_access");
      return json({ error: "認証ユーザーが見つかりません" }, 400, headers);
    }
    const { data: userRes } = await admin.auth.admin.getUserById(emp.auth_user_id as string);
    const email = userRes?.user?.email;
    if (!email) {
      await record("no_access");
      return json({ error: "この職員はメールアドレス未設定のためPINログインできません" }, 400, headers);
    }
    const { data: link, error: linkErr } = await admin.auth.admin.generateLink({ type: "magiclink", email });
    if (linkErr || !link?.properties?.hashed_token) {
      console.error("pin-login generateLink failed"); // トークンは出力しない
      return json({ error: "ログイン処理に失敗しました" }, 500, headers);
    }
    await record("success");
    // token_hash のみ返す(クライアントは verifyOtp({ token_hash, type: 'email' }) で即時セッション化)
    return json({ token_hash: link.properties.hashed_token }, 200, headers);
  } catch (e) {
    console.error("pin-login error", e instanceof Error ? e.message : "unknown"); // PIN/トークンは出力しない
    return json({ error: "ログインに失敗しました" }, 500, headers);
  }
});

async function employeeHasAccess(admin: SupabaseClient, employeeId: string, officeId: string): Promise<boolean> {
  const today = new Date().toISOString().slice(0, 10);
  const { data: a } = await admin
    .from("employee_office_assignments").select("start_date, end_date")
    .eq("employee_id", employeeId).eq("office_id", officeId);
  for (const x of a ?? []) {
    if ((x.start_date as string) <= today && (x.end_date == null || (x.end_date as string) >= today)) return true;
  }
  const { data: r } = await admin
    .from("employee_roles").select("office_id, roles!inner(code)").eq("employee_id", employeeId);
  for (const x of r ?? []) {
    const code = (x as { roles: { code: string } }).roles.code;
    const ro = (x as { office_id: string | null }).office_id;
    if (code === "system_admin" || code === "executive_director") return true;
    if (["director", "chief", "office_manager"].includes(code) && (ro == null || ro === officeId)) return true;
  }
  const { data: g } = await admin
    .from("multi_office_authority_grants").select("id")
    .eq("grantee_employee_id", employeeId).eq("office_id", officeId).is("revoked_at", null);
  return (g ?? []).length > 0;
}

function json(body: unknown, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(body), { status, headers: { ...headers, "Content-Type": "application/json" } });
}
