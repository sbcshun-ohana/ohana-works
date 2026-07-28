// Supabase新方式APIキーへの移行用ヘルパー。
// SUPABASE_SECRET_KEYS はSupabaseが自動注入する予約環境変数(JSON辞書)で、
// 新方式のsecret key(sb_secret_...)を "default" キーに保持する。
// レガシーのSUPABASE_SERVICE_ROLE_KEYの代わりにこちらを使う。

export function getServiceSecretKey(): string {
  const raw = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!raw) throw new Error("SUPABASE_SECRET_KEYS が未設定です");

  const parsed = JSON.parse(raw) as Record<string, string>;
  const key = parsed["default"];
  if (!key) throw new Error("SUPABASE_SECRET_KEYS に default キーがありません");
  return key;
}
