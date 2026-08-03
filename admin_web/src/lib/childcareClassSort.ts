import type { ChildcareClass } from "@/lib/types";

/**
 * 保育業務系ページの園児並び順を「クラス(fetch_childcare_classes の返却順=クラス名順)→園児名」に
 * 統一するためのユーティリティ。年齢区分順の正は fetch_childcare_classes の返却順とし、
 * age_group 文字列の独自ソートはしない(RPCは order by class_name)。
 */

/** クラス名 → 返却順index。未知クラス/クラス無しは末尾。 */
export function classOrderIndex(classes: ChildcareClass[]): Map<string, number> {
  const map = new Map<string, number>();
  classes.forEach((c, i) => map.set(c.class_name, i));
  return map;
}

/** クラス(order順)→ 園児名(ja)で比較。class 無し(null)は末尾。 */
export function compareByClassThenName(
  order: Map<string, number>,
  aClassName: string | null | undefined,
  aChildName: string,
  bClassName: string | null | undefined,
  bChildName: string,
): number {
  const ai = aClassName != null ? order.get(aClassName) ?? Number.MAX_SAFE_INTEGER : Number.MAX_SAFE_INTEGER;
  const bi = bClassName != null ? order.get(bClassName) ?? Number.MAX_SAFE_INTEGER : Number.MAX_SAFE_INTEGER;
  if (ai !== bi) return ai - bi;
  return aChildName.localeCompare(bChildName, "ja");
}
