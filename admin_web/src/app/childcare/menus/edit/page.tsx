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
  // 編集中の本文。キー = `${food_type}:${meal_slot}`
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);

  const dates = useMemo(() => (month ? daysInMonth(month) : []), [month]);

  useEffect(() => {
    if (!importId) return;
    let cancelled = false;
    void (async () => {
      const supabase = createClient();
      const { data, error: e } = await supabase.rpc("fetch_menu_days_for_import", { p_import_id: importId });
      if (cancelled) return;
      if (e) setError(e.message);
      else setDays((data ?? []) as MenuDay[]);
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

  // 選択日の既存値を編集フォームへ反映。
  useEffect(() => {
    const map: Record<string, string> = {};
    for (const d of days.filter((x) => x.menu_date === date && !x.removal_kind)) {
      map[`${d.food_type}:${d.meal_slot}`] = d.menu_text ?? "";
    }
    Promise.resolve().then(() => setEdits(map));
  }, [days, date]);

  async function saveDay() {
    if (!importId || !date) return;
    setSaving(true);
    setError(null);
    setMsg(null);
    const supabase = createClient();
    try {
      for (const ft of FOOD_TYPES) {
        for (const s of SLOTS) {
          const key = `${ft.key}:${s.key}`;
          const text = (edits[key] ?? "").trim();
          const existing = days.find(
            (x) => x.menu_date === date && x.food_type === ft.key && x.meal_slot === s.key && !x.removal_kind,
          );
          // 変更が無い空セルはスキップ(無駄な行を作らない)。
          if (!text && !existing) continue;
          if (existing && (existing.menu_text ?? "") === text) continue;
          const { error: e } = await supabase.rpc("upsert_menu_day", {
            p_import_id: importId,
            p_menu_date: date,
            p_food_type: ft.key,
            p_removal_kind: null,
            p_meal_slot: s.key,
            p_menu_text: text || null,
            p_ingredients: null,
            p_nutrition: null,
            p_removal_note: null,
          });
          if (e) throw e;
        }
      }
      setReloadToken((t) => t + 1);
      setMsg(`${date} の献立を保存しました`);
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

  async function runImportRpc(fn: string, extra?: Record<string, unknown>) {
    if (!importId) return;
    const supabase = createClient();
    const { error: e } = await supabase.rpc(fn, { p_id: importId, ...(extra ?? {}) });
    if (e) setError(e.message);
    else {
      setMsg(fn === "confirm_menu_import" ? "確認済みにしました" : "公開しました");
      setReloadToken((t) => t + 1);
    }
  }

  // 日別の入力充足(何かしら入っている日)をマークするための集合。
  const filledDates = new Set(days.filter((d) => (d.menu_text ?? "").trim() && !d.removal_kind).map((d) => d.menu_date));

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
            <h2 className="mt-1 text-lg font-bold text-slate-800">献立を編集({month})</h2>
            <p className="text-xs text-slate-400">日ごとに食種×区分のメニューを入力し、確認→公開します。AI解析の下書きもここに入ります。</p>
          </div>
          <div className="flex gap-2">
            <button
              onClick={runAiAnalyze}
              disabled={saving}
              className="rounded-lg border border-indigo-300 bg-indigo-50 px-3 py-2 text-sm font-semibold text-indigo-700 hover:bg-indigo-100 disabled:opacity-50"
            >
              AI解析(下書き生成)
            </button>
            <button
              onClick={() => runImportRpc("confirm_menu_import")}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm text-slate-600 hover:bg-slate-50"
            >
              確認済みにする
            </button>
            <button
              onClick={() => runImportRpc("publish_menu_import")}
              className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700"
            >
              公開する
            </button>
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
                    onClick={saveDay}
                    disabled={saving}
                    className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-700 disabled:opacity-50"
                  >
                    {saving ? "保存中…" : "この日を保存"}
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
                      </tr>
                    </thead>
                    <tbody>
                      {FOOD_TYPES.map((ft) => (
                        <tr key={ft.key} className="border-t border-slate-100">
                          <td className="px-2 py-2 align-top font-medium text-slate-700">{ft.label}</td>
                          {SLOTS.map((s) => {
                            const key = `${ft.key}:${s.key}`;
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
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <p className="text-xs text-slate-400">
                  ※除去食(卵除去等)の編集は今後追加します。栄養価・材料の詳細入力も順次対応します。
                </p>
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
