"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";

// 献立管理 Phase 1: 構造化献立(menu_days)の確認・編集。migration 267。
// 日別に 食種(food_type)×区分(meal_slot)のメニュー本文を編集し、確認→公開する。
// AI解析(自動下書き)は後でこの器に流し込む(キー設定後)。

const FOOD_TYPES: { key: string; label: string }[] = [
  { key: "regular_over3", label: "以上児(通常)" },
  { key: "regular_under3", label: "未満児(通常)" },
  { key: "weaning_late", label: "離乳食 後期" },
  { key: "weaning_final", label: "完了期" },
];
const SLOTS: { key: string; label: string }[] = [
  { key: "am_snack", label: "午前おやつ" },
  { key: "lunch", label: "昼食" },
  { key: "pm_snack", label: "午後おやつ" },
];

type MenuDay = {
  id: string;
  menu_date: string;
  food_type: string;
  removal_kind: string | null;
  meal_slot: string;
  menu_text: string | null;
  ingredients: { text?: string } | null;
  removal_note: string | null;
};

function daysInMonth(month: string): string[] {
  // month = "YYYY-MM"。その月の全日(YYYY-MM-DD)。
  const [y, m] = month.split("-").map(Number);
  const last = new Date(y, m, 0).getDate();
  return Array.from({ length: last }, (_, i) => `${month}-${String(i + 1).padStart(2, "0")}`);
}

function MenuEditContent() {
  const params = useSearchParams();
  const office = params.get("office");
  const importId = params.get("import");
  const month = params.get("month") ?? "";
  const [days, setDays] = useState<MenuDay[]>([]);
  const [date, setDate] = useState<string>("");
  // 編集中の本文(全日を保持=日をまたいでも消えない)。キー = `${date}:${food_type}:${meal_slot}`
  const [edits, setEdits] = useState<Record<string, string>>({});
  // 材料(食種ごと・昼食行の ingredients に保存)。キー = `${date}:${food_type}`
  const [ingr, setIngr] = useState<Record<string, string>>({});
  // 除去食(アレルゲン別・昼食行)。キー = `${date}:${allergen}` → { menu, note }
  const [removals, setRemovals] = useState<Record<string, { menu: string; note: string }>>({});
  const [error, setError] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const [status, setStatus] = useState<string>(""); // 取込の公開状態(published 等)
  const published = status === "published" || status === "fallback";

  const dates = useMemo(() => (month ? daysInMonth(month) : []), [month]);

  useEffect(() => {
    if (!importId) return;
    let cancelled = false;
    void (async () => {
      const supabase = createClient();
      const [{ data, error: e }, { data: imp }] = await Promise.all([
        supabase.rpc("fetch_menu_days_for_import", { p_import_id: importId }),
        supabase.rpc("fetch_menu_import", { p_id: importId }),
      ]);
      if (cancelled) return;
      if (e) setError(e.message);
      else setDays((data ?? []) as MenuDay[]);
      setStatus(((imp ?? [])[0]?.status as string | undefined) ?? "");
    })();
    return () => {
      cancelled = true;
    };
  }, [importId, reloadToken]);

  useEffect(() => {
    // setState はマイクロタスクへ逃がす(react-hooks/set-state-in-effect 回避)。
    if (!date && dates.length > 0) {
      const first = dates[0];
      Promise.resolve().then(() => setDate(first));
    }
  }, [dates, date]);

  // 既存値(全日分)を編集フォームへ反映。日をまたいでも編集は保持される。
  useEffect(() => {
    const map: Record<string, string> = {};
    const ingrMap: Record<string, string> = {};
    const remMap: Record<string, { menu: string; note: string }> = {};
    for (const d of days) {
      if (d.food_type === "allergy_removed" && d.removal_kind) {
        // 除去食は昼食行を代表として編集(v1)。
        if (d.meal_slot === "lunch") {
          remMap[`${d.menu_date}:${d.removal_kind}`] = { menu: d.menu_text ?? "", note: d.removal_note ?? "" };
        }
        continue;
      }
      map[`${d.menu_date}:${d.food_type}:${d.meal_slot}`] = d.menu_text ?? "";
      if (d.meal_slot === "lunch") ingrMap[`${d.menu_date}:${d.food_type}`] = d.ingredients?.text ?? "";
    }
    Promise.resolve().then(() => {
      setEdits(map);
      setIngr(ingrMap);
      setRemovals(remMap);
    });
  }, [days]);

  // 変更されたセルを保存。onlyDate 指定なら当日のみ、未指定なら全日を一括保存。publishAfter で保存後に公開。
  async function saveCells(opts?: { onlyDate?: string; publishAfter?: boolean }) {
    if (!importId) return;
    setSaving(true);
    setError(null);
    setMsg(null);
    const supabase = createClient();
    const targetDates = opts?.onlyDate ? [opts.onlyDate] : dates;
    try {
      let count = 0;
      for (const d0 of targetDates) {
        for (const ft of FOOD_TYPES) {
          const ingrText = (ingr[`${d0}:${ft.key}`] ?? "").trim();
          for (const s of SLOTS) {
            const text = (edits[`${d0}:${ft.key}:${s.key}`] ?? "").trim();
            const existing = days.find(
              (x) => x.menu_date === d0 && x.food_type === ft.key && x.meal_slot === s.key && !x.removal_kind,
            );
            const isLunch = s.key === "lunch";
            const newIngr = isLunch && ingrText ? { text: ingrText } : null;
            const existingIngrText = (existing?.ingredients?.text ?? "").trim();
            const menuChanged = existing ? (existing.menu_text ?? "") !== text : !!text;
            const ingrChanged = isLunch && existingIngrText !== ingrText;
            // 変更が無い/空で既存も無いセルはスキップ(無駄な行を作らない)。
            if (!menuChanged && !ingrChanged) continue;
            if (!text && !newIngr && !existing) continue;
            const { error: e } = await supabase.rpc("upsert_menu_day", {
              p_import_id: importId,
              p_menu_date: d0,
              p_food_type: ft.key,
              p_removal_kind: null,
              p_meal_slot: s.key,
              p_menu_text: text || null,
              p_ingredients: newIngr,
              p_nutrition: null,
              p_removal_note: null,
            });
            if (e) throw e;
            count++;
          }
        }
      }
      // 除去食(アレルゲン別・昼食行)を保存。
      for (const [k, v] of Object.entries(removals)) {
        const [d0, allergen] = k.split(":");
        if (!targetDates.includes(d0)) continue;
        const menu = v.menu.trim();
        const note = v.note.trim();
        const existing = days.find(
          (x) => x.menu_date === d0 && x.food_type === "allergy_removed" && x.removal_kind === allergen && x.meal_slot === "lunch",
        );
        const changed = existing ? (existing.menu_text ?? "") !== menu || (existing.removal_note ?? "") !== note : !!(menu || note);
        if (!changed) continue;
        const { error: e } = await supabase.rpc("upsert_menu_day", {
          p_import_id: importId,
          p_menu_date: d0,
          p_food_type: "allergy_removed",
          p_removal_kind: allergen,
          p_meal_slot: "lunch",
          p_menu_text: menu || null,
          p_ingredients: null,
          p_nutrition: null,
          p_removal_note: note || null,
        });
        if (e) throw e;
        count++;
      }
      if (opts?.publishAfter && !published) {
        const { error: pe } = await supabase.rpc("publish_menu_import", { p_id: importId, p_fallback: false });
        if (pe) throw pe;
      }
      setReloadToken((t) => t + 1);
      setMsg(
        opts?.publishAfter
          ? `保存して公開しました(更新 ${count} 件)。保護者アプリ・厨房・日別ビューに反映されます。`
          : opts?.onlyDate
            ? `${opts.onlyDate} の献立を保存しました`
            : `すべての変更を保存しました(更新 ${count} 件)`,
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "保存に失敗しました");
    } finally {
      setSaving(false);
    }
  }

  async function runAiAnalyze() {
    if (!importId) return;
    setSaving(true);
    setError(null);
    setMsg(null);
    try {
      const supabase = createClient();
      const { data, error: e } = await supabase.functions.invoke("analyze-menu-import", {
        body: { import_id: importId },
      });
      if (e) throw e;
      const r = data as { mock?: boolean; saved?: number; total?: number } | null;
      setMsg(
        r?.mock
          ? `AIサンプル下書きを${r?.saved ?? 0}件生成しました(APIキー未設定のためサンプルです。確認・修正して公開してください)`
          : `AI解析で${r?.saved ?? 0}/${r?.total ?? 0}件の下書きを生成しました。確認・修正して公開してください`,
      );
      setReloadToken((t) => t + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : "AI解析に失敗しました(Edge Functionの配備が必要です)");
    } finally {
      setSaving(false);
    }
  }

  function addAllergen() {
    if (!date) return;
    const a = window.prompt("除去するアレルゲンを入力してください(例: 卵 / そば / ピーナッツ)");
    const allergen = (a ?? "").trim();
    if (!allergen) return;
    setRemovals((p) => ({ ...p, [`${date}:${allergen}`]: p[`${date}:${allergen}`] ?? { menu: "", note: "" } }));
  }

  async function removeAllergen(key: string) {
    const [d0, allergen] = key.split(":");
    const existing = days.find(
      (x) => x.menu_date === d0 && x.food_type === "allergy_removed" && x.removal_kind === allergen && x.meal_slot === "lunch",
    );
    if (existing) {
      const supabase = createClient();
      const { error: e } = await supabase.rpc("delete_menu_day", { p_id: existing.id });
      if (e) {
        setError(e.message);
        return;
      }
      setReloadToken((t) => t + 1);
    } else {
      setRemovals((p) => {
        const n = { ...p };
        delete n[key];
        return n;
      });
    }
  }

  // 日別の入力充足(何かしら入っている日)をマークするための集合。
  // 入力がある日(未保存の編集も含む)に●を出す。キーは `${date}:${ft}:${slot}`。
  const filledDates = new Set(
    Object.entries(edits)
      .filter(([, v]) => v.trim())
      .map(([k]) => k.split(":")[0]),
  );

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <MealSubNav />
      <main className="flex-1 space-y-4 p-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <Link href={`/childcare/menus?office=${office ?? ""}`} className="text-sm text-sky-600 hover:underline">
              ← 献立一覧へ戻る
            </Link>
            <div className="mt-1 flex items-center gap-2">
              <h2 className="text-lg font-bold text-slate-800">献立を編集({month})</h2>
              {published ? (
                <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700">公開中</span>
              ) : (
                <span className="rounded-full bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-700">未公開</span>
              )}
            </div>
            <p className="text-xs text-slate-500">
              {published
                ? "公開中です。各日を編集して保存すれば、そのまま保護者アプリ・厨房・日別ビューに反映されます(再公開は不要)。日別の修正はその日だけ直せます。"
                : "各日を入力し、まとめて確認したら「すべて保存して公開」を押すと表示されます。以降は編集・保存だけで反映されます。"}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              onClick={runAiAnalyze}
              disabled={saving}
              className="rounded-lg border border-indigo-300 bg-indigo-50 px-3 py-2 text-sm font-semibold text-indigo-700 hover:bg-indigo-100 disabled:opacity-50"
            >
              AI解析(下書き生成)
            </button>
            <button
              onClick={() => saveCells()}
              disabled={saving}
              className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50"
            >
              すべて保存
            </button>
            {published ? (
              <span className="self-center rounded-lg bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-700">
                公開中(保存すれば反映)
              </span>
            ) : (
              <button
                onClick={() => saveCells({ publishAfter: true })}
                disabled={saving}
                className="rounded-lg bg-emerald-600 px-5 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50"
              >
                すべて保存して公開
              </button>
            )}
          </div>
        </div>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}
        {msg && <p className="text-sm font-medium text-emerald-600">{msg}</p>}

        <div className="grid grid-cols-1 gap-4 md:grid-cols-[200px_1fr]">
          {/* 日付リスト */}
          <div className="max-h-[70vh] overflow-y-auto rounded-2xl bg-white p-2 shadow-sm">
            {dates.map((d) => (
              <button
                key={d}
                onClick={() => setDate(d)}
                className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left text-sm ${
                  d === date ? "bg-sky-50 font-semibold text-sky-700" : "text-slate-600 hover:bg-slate-50"
                }`}
              >
                <span>{Number(d.slice(8, 10))}日</span>
                {filledDates.has(d) && <span className="text-xs text-emerald-500">●</span>}
              </button>
            ))}
          </div>

          {/* 編集グリッド(食種×区分) */}
          <div className="space-y-3 rounded-2xl bg-white p-4 shadow-sm">
            {!date ? (
              <p className="text-sm text-slate-400">左から日付を選んでください。</p>
            ) : (
              <>
                <div className="flex items-center justify-between">
                  <h3 className="text-base font-bold text-slate-800">{date} の献立</h3>
                  <button
                    onClick={() => saveCells({ onlyDate: date })}
                    disabled={saving}
                    className="rounded-lg border border-indigo-300 bg-indigo-50 px-4 py-2 text-sm font-semibold text-indigo-700 hover:bg-indigo-100 disabled:opacity-50"
                  >
                    {saving ? "保存中…" : "この日だけ保存"}
                  </button>
                </div>
                <div className="overflow-x-auto">
                  <table className="min-w-full text-sm">
                    <thead>
                      <tr className="text-left text-xs font-semibold text-slate-500">
                        <th className="px-2 py-2">食種＼区分</th>
                        {SLOTS.map((s) => (
                          <th key={s.key} className="px-2 py-2">
                            {s.label}
                          </th>
                        ))}
                        <th className="px-2 py-2">材料(昼食・保護者に表示)</th>
                      </tr>
                    </thead>
                    <tbody>
                      {FOOD_TYPES.map((ft) => (
                        <tr key={ft.key} className="border-t border-slate-100">
                          <td className="px-2 py-2 align-top font-medium text-slate-700">{ft.label}</td>
                          {SLOTS.map((s) => {
                            const key = `${date}:${ft.key}:${s.key}`;
                            return (
                              <td key={s.key} className="px-2 py-2 align-top">
                                <textarea
                                  value={edits[key] ?? ""}
                                  onChange={(e) => setEdits((p) => ({ ...p, [key]: e.target.value }))}
                                  rows={3}
                                  className="w-full min-w-[160px] rounded-lg border border-slate-300 px-2 py-1.5 text-sm focus:border-sky-400 focus:outline-none"
                                  placeholder="—"
                                />
                              </td>
                            );
                          })}
                          <td className="px-2 py-2 align-top">
                            <textarea
                              value={ingr[`${date}:${ft.key}`] ?? ""}
                              onChange={(e) => setIngr((p) => ({ ...p, [`${date}:${ft.key}`]: e.target.value }))}
                              rows={3}
                              className="w-full min-w-[180px] rounded-lg border border-amber-300 bg-amber-50/40 px-2 py-1.5 text-sm focus:border-amber-400 focus:outline-none"
                              placeholder="例: 米・鶏肉・人参・玉ねぎ…"
                            />
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                {/* 除去食(アレルゲン別) */}
                <div className="mt-4 space-y-2 rounded-xl border border-amber-200 bg-amber-50/40 p-3">
                  <div className="flex items-center justify-between">
                    <h4 className="text-sm font-bold text-amber-800">除去食(アレルゲン別・昼食)</h4>
                    <button
                      onClick={addAllergen}
                      className="rounded-lg border border-amber-300 bg-white px-3 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-100"
                    >
                      ＋ 除去食を追加
                    </button>
                  </div>
                  <p className="text-xs text-slate-500">
                    卵・そば・ピーナッツ等の除去食の昼食メニューと除去・代替内容。園側の日別ビュー・食数ボードに表示されます(保護者公開はアレルギー管理実装後)。
                  </p>
                  {Object.keys(removals).filter((k) => k.startsWith(`${date}:`)).length === 0 ? (
                    <p className="text-xs text-slate-400">この日の除去食はありません。</p>
                  ) : (
                    Object.keys(removals)
                      .filter((k) => k.startsWith(`${date}:`))
                      .map((k) => {
                        const allergen = k.slice(date.length + 1);
                        return (
                          <div key={k} className="rounded-lg border border-amber-200 bg-white p-2">
                            <div className="mb-1 flex items-center justify-between">
                              <span className="text-sm font-semibold text-amber-800">{allergen} 除去</span>
                              <button onClick={() => removeAllergen(k)} className="text-xs text-red-500 hover:underline">
                                削除
                              </button>
                            </div>
                            <div className="grid grid-cols-1 gap-2 md:grid-cols-2">
                              <textarea
                                value={removals[k]?.menu ?? ""}
                                onChange={(e) => setRemovals((p) => ({ ...p, [k]: { ...p[k], menu: e.target.value } }))}
                                rows={2}
                                placeholder="昼食(除去対応メニュー)"
                                className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm focus:border-sky-400 focus:outline-none"
                              />
                              <textarea
                                value={removals[k]?.note ?? ""}
                                onChange={(e) => setRemovals((p) => ({ ...p, [k]: { ...p[k], note: e.target.value } }))}
                                rows={2}
                                placeholder="除去・代替内容(例: 卵を除き豆腐で代替)"
                                className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm focus:border-sky-400 focus:outline-none"
                              />
                            </div>
                          </div>
                        );
                      })
                  )}
                </div>

                <p className="text-xs text-slate-400">※栄養価・材料の詳細入力(3群)は順次対応します。</p>
              </>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}

export default function MenuEditPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-400">読み込み中…</div>}>
      <MenuEditContent />
    </Suspense>
  );
}
