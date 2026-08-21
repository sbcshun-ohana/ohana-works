"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { currentDate } from "@/lib/datetime";

// 献立管理 Phase 2: 園側の日別献立ビュー(公開済みの当日献立を1画面で確認)。migration 267 fetch_published_menu_day。
// デイリーボード・食数ボードから当日の献立へ遷移する導線としても使える。

const FOOD_TYPES: { key: string; label: string }[] = [
  { key: "regular_over3", label: "以上児(通常)" },
  { key: "regular_under3", label: "未満児(通常)" },
  { key: "weaning_late", label: "離乳食 後期" },
  { key: "weaning_final", label: "完了期" },
  { key: "allergy_removed", label: "除去食" },
];
const SLOTS: { key: string; label: string }[] = [
  { key: "am_snack", label: "午前おやつ" },
  { key: "lunch", label: "昼食" },
  { key: "pm_snack", label: "午後おやつ" },
];

type Row = {
  food_type: string;
  removal_kind: string | null;
  meal_slot: string;
  menu_text: string | null;
  ingredients: { text?: string } | null;
  removal_note: string | null;
};

function MenuDayViewContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const [date, setDate] = useState(currentDate());
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!selectedOffice) return;
    let cancelled = false;
    void (async () => {
      setLoading(true);
      const supabase = createClient();
      const { data, error: e } = await supabase.rpc("fetch_published_menu_day", {
        p_office_id: selectedOffice,
        p_menu_date: date,
      });
      if (cancelled) return;
      setLoading(false);
      if (e) {
        setError(e.message);
        setRows([]);
      } else {
        setError(null);
        setRows((data ?? []) as Row[]);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedOffice, date]);

  // food_type×meal_slot -> menu_text(除去食以外)。除去食は removal_kind ごとに別扱い。
  function cell(foodType: string, slot: string): string {
    const r = rows.find((x) => x.food_type === foodType && x.meal_slot === slot && !x.removal_kind);
    return r?.menu_text ?? "";
  }
  // 材料(昼食行の ingredients.text)。
  function lunchIngredients(foodType: string): string {
    const r = rows.find((x) => x.food_type === foodType && x.meal_slot === "lunch" && !x.removal_kind);
    return r?.ingredients?.text ?? "";
  }
  const removals = rows.filter((r) => r.food_type === "allergy_removed" && r.removal_kind);

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <MealSubNav />
      <main className="flex-1 space-y-4 p-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-bold text-slate-800">日別献立ビュー</h2>
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>
        <p className="text-xs text-slate-400">公開中の献立を表示します(食種×区分)。下書き・未公開は表示されません。</p>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white p-4 shadow-sm">
          {loading ? (
            <p className="text-sm text-slate-400">読み込み中…</p>
          ) : rows.length === 0 ? (
            <p className="text-sm text-slate-400">この日の公開済み献立はありません。</p>
          ) : (
            <table className="min-w-full text-sm">
              <thead>
                <tr className="text-left text-xs font-semibold text-slate-500">
                  <th className="px-3 py-2">食種＼区分</th>
                  {SLOTS.map((s) => (
                    <th key={s.key} className="px-3 py-2">
                      {s.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {FOOD_TYPES.filter((ft) => ft.key !== "allergy_removed").map((ft) => (
                  <tr key={ft.key} className="border-t border-slate-100">
                    <td className="px-3 py-2 align-top font-medium text-slate-700">{ft.label}</td>
                    {SLOTS.map((s) => (
                      <td key={s.key} className="whitespace-pre-wrap px-3 py-2 align-top text-slate-600">
                        {cell(ft.key, s.key) || <span className="text-slate-300">—</span>}
                        {/* 材料は昼食セルの下に表示。 */}
                        {s.key === "lunch" && lunchIngredients(ft.key) && (
                          <div className="mt-1 text-xs text-amber-700">材料: {lunchIngredients(ft.key)}</div>
                        )}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* 除去食(アレルゲン別)。園側のみ表示(保護者公開はアレルギー管理実装後)。 */}
        {removals.length > 0 && (
          <div className="space-y-2 rounded-2xl bg-white p-4 shadow-sm">
            <h3 className="text-base font-bold text-slate-800">除去食(アレルゲン別)</h3>
            {Array.from(new Set(removals.map((r) => r.removal_kind))).map((kind) => (
              <div key={kind} className="rounded-xl border border-amber-200 bg-amber-50 p-3">
                <p className="text-sm font-semibold text-amber-800">{kind} 除去</p>
                {SLOTS.map((s) => {
                  const r = removals.find((x) => x.removal_kind === kind && x.meal_slot === s.key);
                  if (!r?.menu_text && !r?.removal_note) return null;
                  return (
                    <p key={s.key} className="text-sm text-slate-700">
                      <span className="text-slate-500">{s.label}: </span>
                      {r?.menu_text}
                      {r?.removal_note ? `(${r.removal_note})` : ""}
                    </p>
                  );
                })}
              </div>
            ))}
          </div>
        )}

        {offices !== null && offices.length === 0 && (
          <p className="text-sm text-slate-500">保育業務機能が有効な施設がありません。</p>
        )}
      </main>
    </div>
  );
}

export default function MenuDayViewPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-400">読み込み中…</div>}>
      <MenuDayViewContent />
    </Suspense>
  );
}
