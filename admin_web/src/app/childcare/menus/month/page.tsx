"use client";

import { Fragment, Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 献立 月間一覧ビュー。その月に読み込まれた献立(取込=fetch_menu_imports の公開/最新版)を
// fetch_menu_days_for_import で1画面に一覧し、月単位で一括確認できる。日別ビュー(単独タブ)を置換。
// DB変更なし(既存RPCの再利用)。食数ボードの「本日の献立」はそのまま残す。

// 食数ボードの給食段階と統一: 上から 後期 / 完了期 / 幼児食。幼児食は1種類(over3/under3統合)。
const FOOD_TYPES: { key: string; label: string; srcs: string[] }[] = [
  { key: "weaning_late", label: "後期", srcs: ["weaning_late"] },
  { key: "weaning_final", label: "完了期", srcs: ["weaning_final"] },
  { key: "regular", label: "幼児食", srcs: ["regular_over3", "regular_under3"] },
];
const SLOTS: { key: string; label: string }[] = [
  { key: "am_snack", label: "午前おやつ" },
  { key: "lunch", label: "昼食" },
  { key: "pm_snack", label: "午後おやつ" },
];
// 食種ごとの色(食種セルの背景+文字色)。ひと目で種類を見分けやすく。
const FT_STYLE: Record<string, string> = {
  weaning_late: "bg-violet-100 text-violet-800",
  weaning_final: "bg-indigo-100 text-indigo-800",
  regular: "bg-sky-100 text-sky-800",
};

type MenuImport = { id: string; target_month: string; status: string; version: number; source_filename: string };
type Day = {
  menu_date: string;
  food_type: string;
  removal_kind: string | null;
  meal_slot: string;
  menu_text: string | null;
  ingredients: { text?: string } | null;
  removal_note: string | null;
};

function firstOfThisMonth(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function MenuMonthContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const [month, setMonth] = useState(firstOfThisMonth()); // "YYYY-MM"
  const [days, setDays] = useState<Day[]>([]);
  const [used, setUsed] = useState<MenuImport | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!selectedOffice) return;
    let cancelled = false;
    void (async () => {
      setLoading(true);
      setError(null);
      const supabase = createClient();
      const monthStart = `${month}-01`;
      const { data: imports, error: e1 } = await supabase.rpc("fetch_menu_imports", {
        p_office_id: selectedOffice,
        p_target_month: monthStart,
      });
      if (cancelled) return;
      if (e1) {
        setError(e1.message);
        setDays([]);
        setUsed(null);
        setLoading(false);
        return;
      }
      const list = (imports ?? []) as MenuImport[];
      // 公開中を優先、無ければ最新版(version降順の先頭)。
      const chosen = list.find((i) => i.status === "published") ?? list[0] ?? null;
      setUsed(chosen);
      if (!chosen) {
        setDays([]);
        setLoading(false);
        return;
      }
      const { data: dd, error: e2 } = await supabase.rpc("fetch_menu_days_for_import", { p_import_id: chosen.id });
      if (cancelled) return;
      setLoading(false);
      if (e2) {
        setError(e2.message);
        setDays([]);
      } else {
        setDays((dd ?? []) as Day[]);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedOffice, month]);

  // 日付ごとにグループ化。
  const dates = [...new Set(days.map((d) => d.menu_date))].sort();
  function cell(date: string, srcs: string[], slot: string): string {
    for (const ft of srcs) {
      const r = days.find((x) => x.menu_date === date && x.food_type === ft && x.meal_slot === slot && !x.removal_kind);
      if (r?.menu_text) return r.menu_text;
    }
    return "";
  }
  // 材料(その食種の昼食行の ingredients.text)。
  function ingredientsOf(date: string, srcs: string[]): string {
    for (const ft of srcs) {
      const r = days.find((x) => x.menu_date === date && x.food_type === ft && x.meal_slot === "lunch" && !x.removal_kind);
      if (r?.ingredients?.text) return r.ingredients.text;
    }
    return "";
  }
  function foodTypesWithData(date: string): { key: string; label: string; srcs: string[] }[] {
    return FOOD_TYPES.filter((ft) => SLOTS.some((s) => cell(date, ft.srcs, s.key)));
  }
  function removalKinds(date: string): string[] {
    return [...new Set(days.filter((x) => x.menu_date === date && x.food_type === "allergy_removed" && x.removal_kind).map((x) => x.removal_kind as string))];
  }
  function removalCell(date: string, kind: string, slot: string): string {
    const r = days.find((x) => x.menu_date === date && x.food_type === "allergy_removed" && x.removal_kind === kind && x.meal_slot === slot);
    if (!r) return "";
    return [r.menu_text, r.removal_note ? `(${r.removal_note})` : ""].filter(Boolean).join(" ");
  }

  const weekday = (iso: string) => "日月火水木金土"[new Date(iso).getDay()];

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
          <div>
            <h2 className="text-lg font-bold text-slate-800">献立 月間一覧</h2>
            <p className="text-xs text-slate-400">
              その月に読み込まれた献立を1画面で一覧します(食種×区分×日)。
              {used ? `　使用中: v${used.version}・${used.source_filename}${used.status === "published" ? "(公開中)" : "(未公開)"}` : ""}
            </p>
          </div>
          <input
            type="month"
            value={month}
            onChange={(e) => setMonth(e.target.value)}
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          {loading ? (
            <p className="p-6 text-sm text-slate-400">読み込み中…</p>
          ) : dates.length === 0 ? (
            <p className="p-6 text-sm text-slate-400">この月に読み込まれた献立はありません(「献立」タブでアップロード・公開してください)。</p>
          ) : (
            <table className="min-w-full border-collapse text-sm">
              <thead>
                <tr className="text-left text-xs font-semibold text-slate-600">
                  <th className="border border-slate-300 bg-slate-100 px-3 py-2">日付</th>
                  <th className="border border-slate-300 bg-slate-100 px-3 py-2">食種</th>
                  {SLOTS.map((s) => (
                    <th key={s.key} className="border border-slate-300 bg-slate-100 px-3 py-2">{s.label}</th>
                  ))}
                  <th className="border border-slate-300 bg-slate-100 px-3 py-2">材料(昼食)</th>
                </tr>
              </thead>
              <tbody>
                {dates.map((date, di) => {
                  const fts = foodTypesWithData(date);
                  const rks = removalKinds(date);
                  const span = Math.max(1, fts.length + rks.length);
                  const d = new Date(date);
                  const isSun = d.getDay() === 0;
                  const isSat = d.getDay() === 6;
                  // 1日おきに縞々(日付グループ単位で背景色を交互に)。
                  const zebra = di % 2 === 1 ? "bg-slate-50" : "bg-white";
                  // 日の先頭行は上に太い罫線を引いて日の区切りを強調。
                  const dayTop = "border-t-2 border-t-slate-400";
                  return (
                    <Fragment key={date}>
                      {(fts.length + rks.length === 0 ? [null] : fts).map((ft, i) => (
                        <tr key={`${date}-${ft?.key ?? "none"}`} className={`align-top ${zebra}`}>
                          {i === 0 && (
                            <td rowSpan={span} className={`border border-slate-200 ${dayTop} whitespace-nowrap px-3 py-2 text-base font-bold ${isSun ? "text-red-500" : isSat ? "text-sky-500" : "text-slate-800"}`}>
                              {d.getMonth() + 1}/{d.getDate()}<br />（{weekday(date)}）
                            </td>
                          )}
                          {ft ? (
                            <>
                              <td className={`border border-slate-200 ${i === 0 ? dayTop : ""} whitespace-nowrap px-3 py-2 font-bold ${FT_STYLE[ft.key] ?? "text-slate-700"}`}>{ft.label}</td>
                              {SLOTS.map((s) => (
                                <td key={s.key} className={`border border-slate-200 ${i === 0 ? dayTop : ""} whitespace-pre-wrap px-3 py-2 text-slate-600`}>
                                  {cell(date, ft.srcs, s.key) || <span className="text-slate-300">—</span>}
                                </td>
                              ))}
                              <td className={`border border-slate-200 ${i === 0 ? dayTop : ""} whitespace-pre-wrap px-3 py-2 text-xs text-amber-700`}>
                                {ingredientsOf(date, ft.srcs) || <span className="text-slate-300">—</span>}
                              </td>
                            </>
                          ) : (
                            <td colSpan={SLOTS.length + 2} className={`border border-slate-200 ${dayTop} px-3 py-2 text-slate-300`}>献立なし</td>
                          )}
                        </tr>
                      ))}
                      {rks.map((kind) => (
                        <tr key={`${date}-rm-${kind}`} className="bg-amber-50 align-top">
                          <td className="border border-amber-200 whitespace-nowrap px-3 py-2 font-semibold text-amber-700">{kind} 除去</td>
                          {SLOTS.map((s) => (
                            <td key={s.key} className="border border-amber-200 whitespace-pre-wrap px-3 py-2 text-amber-800">
                              {removalCell(date, kind, s.key) || <span className="text-amber-300">—</span>}
                            </td>
                          ))}
                          <td className="border border-amber-200 px-3 py-2 text-amber-300">—</td>
                        </tr>
                      ))}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>

        {offices !== null && offices.length === 0 && (
          <p className="text-sm text-slate-500">保育業務機能が有効な施設がありません。</p>
        )}
      </main>
    </div>
  );
}

export default function MenuMonthViewPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-400">読み込み中…</div>}>
      <MenuMonthContent />
    </Suspense>
  );
}
