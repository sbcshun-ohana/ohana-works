// 職員マスタ編集RPCの例外メッセージを日本語の分かりやすい表示へ変換する。
export function friendlyEmployeeError(message: string | undefined): string {
  const m = message ?? "";
  if (m.includes("cannot change your own role")) return "自分の役職は変更できません";
  if (m.includes("assign a role at or above")) return "この役職を付与する権限がありません";
  if (m.includes("remove a role at or above")) return "この役職を剥奪する権限がありません";
  if (m.includes("cannot remove the last")) return "最後の管理者は剥奪できないため、変更できません";
  if (m.includes("name is required")) return "氏名は必須です";
  if (m.includes("home_office_id is required")) return "所属は必須です";
  if (m.includes("unknown role")) return "不明な役職です";
  if (m.includes("not authorized")) return "この操作を行う権限がありません";
  return "操作に失敗しました";
}
