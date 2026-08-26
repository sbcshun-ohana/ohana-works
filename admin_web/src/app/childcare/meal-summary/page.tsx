"use client";

import { Fragment, Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

type MonthlyRow = {
  business_date: string;
  am_child: number; am_staff: number;
  lunch_child: number; lunch_staff: number;
  lunch_late: number; lunch_complete: number; lunch_toddler: number;
  pm_child: number; pm_staff: number;
  leftover_grams: number | null;
};
type BoardCrossRow = {
  office_id: string; office_name: string; office_code: string;
  row_key: string; row_label: string; row_type: string; sort_order: number;
  meal_slot: string; child_count: number; staff_count: number; allergy_count: number;
};
type AllergyRow = {
  office_id: string; office_name: string; office_code: string;
  child_name: string; class_name: string | null; handling: string;
  allergens: string[] | null; substitute: string | null; consent_status: string | null;
};

const SLOTS: { key: string; label: string }[] = [
  { key: "am_snack", label: "午前おやつ" },
  { key: "lunch", label: "昼食" },
  { key: "pm_snack", label: "午後おやつ" },
];

function todayStr(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function MealSummaryContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const now = new Date();
  const [mode, setMode] = useState<"monthly" | "cross">("cross"); // 既定=厨房ビュー(横断)
  const [officeId, setOfficeId] = useState("");
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [monthly, setMonthly] = useState<MonthlyRow[]>([]);
  const [crossDate, setCrossDate] = useState(todayStr());
  const [boardCross, setBoardCross] = useState<BoardCrossRow[]>([]);
  const [allergy, setAllergy] = useState<AllergyRow[]>([]);
  const [err, setErr] = useState<string | null>(null);

  const effOffice = officeId || selectedOffice;

  // 月別集計
  useEffect(() => {
    if (mode !== "monthly" || !effOffice) return;
    createClient()
      .rpc("fetch_meal_monthly_summary", { p_office_id: effOffice, p_year: year, p_month: month })
      .then(({ data, error }) => {
        if (error) { setErr(error.message); setMonthly([]); return; }
        setErr(null);
        setMonthly((data ?? []) as MonthlyRow[]);
      });
  }, [mode, effOffice, year, month]);

  // 厨房ビュー(担当施設の横断)。食数(施設別)+アレルギー対応者リスト。
  useEffect(() => {
    if (mode !== "cross" || !offices || offices.length === 0) return;
    const ids = offices.map((o) => o.office_id);
    const supabase = createClient();
    void supabase
      .rpc("fetch_meal_board_crossoffice", { p_office_ids: ids, p_business_date: crossDate })
      .then(({ data, error }) => {
        if (error) { setErr(error.message); setBoardCross([]); return; }
        setErr(null);
        setBoardCross((data ?? []) as BoardCrossRow[]);
      });
    void supabase
      .rpc("fetch_meal_allergy_crossoffice", { p_office_ids: ids, p_business_date: crossDate })
      .then(({ data }) => setAllergy((data ?? []) as AllergyRow[]));
  }, [mode, offices, crossDate]);

  const sum = (k: keyof MonthlyRow) => monthly.reduce((a, r) => a + (Number(r[k]) || 0), 0);

  async function exportMonthlyExcel() {
    const XLSX = await import("xlsx");
    const officeName = offices?.find((o) => o.office_id === effOffice)?.office_name ?? "";
    const aoa: (string | number)[][] = [
      [`月別食数集計  ${officeName}  ${year}年${month}月`],
      [],
      ["日付", "午前おやつ(児)", "午前おやつ(職)", "昼食 後期", "昼食 完了", "昼食 幼児", "昼食(職)", "午後おやつ(児)", "午後おやつ(職)", "残量(g)"],
    ];
    for (const r of monthly) {
      const d = new Date(r.business_date);
      aoa.push([`${d.getMonth() + 1}/${d.getDate()}`, r.am_child, r.am_staff, r.lunch_late, r.lunch_complete, r.lunch_toddler, r.lunch_staff, r.pm_child, r.pm_staff, r.leftover_grams ?? ""]);
    }
    aoa.push(["月合計", sum("am_child"), sum("am_staff"), sum("lunch_late"), sum("lunch_complete"), sum("lunch_toddler"), sum("lunch_staff"), sum("pm_child"), sum("pm_staff"), sum("leftover_grams")]);
    const ws = XLSX.utils.aoa_to_sheet(aoa);
    ws["!cols"] = [{ wch: 8 }, ...Array(9).fill({ wch: 12 })];
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "月別集計");
    XLSX.writeFile(wb, `月別食数集計_${officeName}_${year}-${String(month).padStart(2, "0")}.xlsx`);
  }

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">保育業務の施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <MealSubNav />
      <main className="flex-1 space-y-5 p-6">
        <div className="flex items-center gap-2">
          <h2 className="text-lg font-bold text-slate-800">給食数の集計</h2>
          <div className="ml-4 flex gap-1 rounded-lg bg-slate-100 p-1">
            <button onClick={() => setMode("cross")}
              className={`rounded-md px-3 py-1 text-sm font-semibold ${mode === "cross" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>厨房ビュー</button>
            <button onClick={() => setMode("monthly")}
              className={`rounded-md px-3 py-1 text-sm font-semibold ${mode === "monthly" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>月次集計</button>
          </div>
        </div>
        {err && <div className="rounded-lg bg-red-50 px-4 py-2 text-sm text-red-600">{err}</div>}

        {mode === "monthly" ? (
          <>
            <div className="flex flex-wrap items-center gap-3">
              <select value={effOffice} onChange={(e) => setOfficeId(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm">
                {(offices ?? []).map((o) => <option key={o.office_id} value={o.office_id}>{o.office_name}</option>)}
              </select>
              <select value={year} onChange={(e) => setYear(Number(e.target.value))} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm">
                {[year - 1, year, year + 1].map((y) => <option key={y} value={y}>{y}年</option>)}
              </select>
              <select value={month} onChange={(e) => setMonth(Number(e.target.value))} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm">
                {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => <option key={m} value={m}>{m}月</option>)}
              </select>
              <button onClick={() => void exportMonthlyExcel()} disabled={monthly.length === 0}
                className="rounded-lg border border-emerald-300 px-3 py-1.5 text-sm font-semibold text-emerald-700 hover:bg-emerald-50 disabled:opacity-50">Excel出力</button>
            </div>
            <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
              <table className="min-w-full text-sm">
                <thead><tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-3 py-2">日付</th><th className="px-3 py-2">午前おやつ</th><th className="px-3 py-2">昼食</th><th className="px-3 py-2">午後おやつ</th><th className="px-3 py-2">残量(g)</th>
                </tr></thead>
                <tbody>
                  {monthly.length === 0 && <tr><td colSpan={5} className="px-3 py-6 text-center text-slate-400">この月の食数データはありません</td></tr>}
                  {monthly.map((r) => {
                    const d = new Date(r.business_date);
                    return (
                      <tr key={r.business_date} className="border-b border-slate-100 last:border-0">
                        <td className="px-3 py-2 font-medium text-slate-700">{d.getMonth() + 1}/{d.getDate()}</td>
                        <td className="px-3 py-2">児{r.am_child} / 職{r.am_staff}</td>
                        <td className="px-3 py-2">
                          <div>後期{r.lunch_late} ・ 完了{r.lunch_complete} ・ 幼児{r.lunch_toddler}</div>
                          <div className="text-xs text-slate-400">職{r.lunch_staff}</div>
                        </td>
                        <td className="px-3 py-2">児{r.pm_child} / 職{r.pm_staff}</td>
                        <td className="px-3 py-2">{r.leftover_grams ?? "—"}</td>
                      </tr>
                    );
                  })}
                  {monthly.length > 0 && (
                    <tr className="bg-slate-50 font-bold">
                      <td className="px-3 py-2">月合計</td>
                      <td className="px-3 py-2">児{sum("am_child")} / 職{sum("am_staff")}</td>
                      <td className="px-3 py-2">
                        <div>後期{sum("lunch_late")} ・ 完了{sum("lunch_complete")} ・ 幼児{sum("lunch_toddler")}</div>
                        <div className="text-xs text-slate-400">職{sum("lunch_staff")}</div>
                      </td>
                      <td className="px-3 py-2">児{sum("pm_child")} / 職{sum("pm_staff")}</td>
                      <td className="px-3 py-2">{sum("leftover_grams")}</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </>
        ) : (
          <>
            <div className="flex items-center gap-3">
              <input type="date" value={crossDate} onChange={(e) => setCrossDate(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
              <span className="text-xs text-slate-400">各園で承認・確定された食数を、担当施設分まとめて表示します(読み取り専用)。承認・変更は「食数ボード」で。</span>
            </div>

            {/* ① 食数(施設 → クラス/給食段階の行 × 食事区分・児/職を列分割) */}
            {(() => {
              type Slots = Record<string, [number, number]>; // slot -> [児, 職]
              const officeList = [...new Map(boardCross.map((r) => [r.office_id, r.office_name])).entries()];
              const rowsOf = (oid: string) => {
                const m = new Map<string, { label: string; sort: number; allergy: number; slots: Slots }>();
                for (const r of boardCross.filter((x) => x.office_id === oid)) {
                  if (!m.has(r.row_key)) m.set(r.row_key, { label: r.row_label, sort: r.sort_order, allergy: r.allergy_count, slots: {} });
                  m.get(r.row_key)!.slots[r.meal_slot] = [r.child_count, r.staff_count];
                }
                return [...m.values()].sort((a, b) => a.sort - b.sort);
              };
              const grand = (slot: string, idx: 0 | 1) => boardCross.filter((r) => r.meal_slot === slot).reduce((a, r) => a + (idx === 0 ? r.child_count : r.staff_count), 0);
              const grandAllergy = (slot: string) => boardCross.filter((r) => r.meal_slot === slot).reduce((a, r) => a + (r.allergy_count || 0), 0);
              // 施設小計(その施設の全行合計)。idx: 0=児 1=職 2=内アレ。
              const offTotal = (oid: string, slot: string, idx: 0 | 1 | 2) =>
                boardCross.filter((r) => r.office_id === oid && r.meal_slot === slot)
                  .reduce((a, r) => a + (idx === 0 ? r.child_count : idx === 1 ? r.staff_count : r.allergy_count || 0), 0);
              return (
                <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
                  <table className="min-w-full text-sm tabular-nums">
                    <thead>
                      <tr className="border-b border-slate-200 text-xs font-semibold text-slate-500">
                        <th rowSpan={2} className="border-r border-slate-100 px-3 py-2 text-left align-bottom">クラス / 区分</th>
                        {SLOTS.map((s) => (
                          <th key={s.key} colSpan={2} className="border-r border-slate-100 px-3 py-1 text-center text-amber-600">{s.label}</th>
                        ))}
                      </tr>
                      <tr className="border-b border-slate-200 text-xs font-semibold text-slate-400">
                        {SLOTS.map((s) => (
                          <Fragment key={s.key}>
                            <th className="px-3 py-1 text-center">児</th>
                            <th className="border-r border-slate-100 px-3 py-1 text-center">職</th>
                          </Fragment>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {officeList.length === 0 && <tr><td colSpan={7} className="px-3 py-6 text-center text-slate-400">この日の食数データはありません(各園の食数ボードで承認してください)</td></tr>}
                      {officeList.map(([oid, oname]) => (
                        <Fragment key={oid}>
                          <tr className="bg-sky-50">
                            <td colSpan={7} className="border-y border-sky-100 px-3 py-1.5 text-sm font-bold text-sky-800">{oname}</td>
                          </tr>
                          {rowsOf(oid).map((row, i) => (
                            <tr key={row.label} className={row.allergy > 0 ? "bg-rose-50/60" : i % 2 === 1 ? "bg-slate-50" : ""}>
                              <td className="border-r border-slate-100 px-3 py-2 pl-6 align-top text-slate-800 whitespace-nowrap">
                                {row.label}
                                {row.allergy > 0 && <span className="ml-2 rounded bg-rose-600 px-1.5 py-0.5 text-[10px] font-bold text-white">アレルギー食</span>}
                              </td>
                              {SLOTS.map((s) => {
                                const cell = row.slots[s.key]; // 未提供の区分は undefined
                                return (
                                  <Fragment key={s.key}>
                                    <td className="px-3 py-2 text-center align-top">
                                      <div>{cell?.[0] ?? 0}</div>
                                      {/* その食事のうち何食がアレルギー対応食か(赤字で明示) */}
                                      {row.allergy > 0 && cell && (
                                        <div className="text-[10px] font-bold leading-tight text-rose-600">内アレ {row.allergy}</div>
                                      )}
                                    </td>
                                    <td className="border-r border-slate-100 px-3 py-2 text-center align-top text-slate-400">{cell?.[1] ?? 0}</td>
                                  </Fragment>
                                );
                              })}
                            </tr>
                          ))}
                          {/* 施設ごとの小計 */}
                          <tr className="bg-slate-100 font-semibold text-slate-700">
                            <td className="border-r border-slate-100 px-3 py-1.5 pl-6">小計</td>
                            {SLOTS.map((s) => (
                              <Fragment key={s.key}>
                                <td className="px-3 py-1.5 text-center align-top">
                                  <div>{offTotal(oid, s.key, 0)}</div>
                                  {offTotal(oid, s.key, 2) > 0 && <div className="text-[10px] font-bold leading-tight text-rose-600">内アレ {offTotal(oid, s.key, 2)}</div>}
                                </td>
                                <td className="border-r border-slate-100 px-3 py-1.5 text-center align-top text-slate-500">{offTotal(oid, s.key, 1)}</td>
                              </Fragment>
                            ))}
                          </tr>
                        </Fragment>
                      ))}
                      {officeList.length > 0 && (
                        <tr className="border-t-2 border-slate-200 bg-emerald-50 font-bold">
                          <td className="border-r border-slate-100 px-3 py-2 align-top">合計(参考)</td>
                          {SLOTS.map((s) => (
                            <Fragment key={s.key}>
                              <td className="px-3 py-2 text-center align-top">
                                <div>{grand(s.key, 0)}</div>
                                {grandAllergy(s.key) > 0 && <div className="text-[10px] font-bold leading-tight text-rose-600">内アレ {grandAllergy(s.key)}</div>}
                              </td>
                              <td className="border-r border-slate-100 px-3 py-2 text-center align-top">{grand(s.key, 1)}</td>
                            </Fragment>
                          ))}
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              );
            })()}

            {/* ② アレルギー対応者リスト(除去食=作る / 弁当持参=作らない を分けて) */}
            {(() => {
              const elim = allergy.filter((a) => a.handling === "elimination");
              const bento = allergy.filter((a) => a.handling === "bento");
              return (
                <div className="space-y-3">
                  <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
                    <div className="border-b border-slate-100 px-4 py-2 text-sm font-bold text-rose-700">アレルギー対応食(作る){elim.length > 0 && `・${elim.length}名`}</div>
                    {elim.length === 0 ? (
                      <div className="px-4 py-4 text-sm text-slate-400">本日のアレルギー対応食はありません</div>
                    ) : (
                      <table className="min-w-full text-sm">
                        <thead><tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                          <th className="px-3 py-2">名前</th><th className="px-3 py-2">施設・クラス</th><th className="px-3 py-2">アレルゲン</th><th className="px-3 py-2">代替(除去・代替内容)</th><th className="px-3 py-2 text-right">食数</th>
                        </tr></thead>
                        <tbody>
                          {elim.map((a, i) => (
                            <tr key={`${a.office_id}-${a.child_name}-${i}`} className={i % 2 === 1 ? "bg-rose-50/40" : ""}>
                              <td className="px-3 py-2 font-medium text-slate-800 whitespace-nowrap">{a.child_name}
                                {a.consent_status === "pending" && <span className="ml-1 rounded bg-amber-100 px-1 text-[10px] text-amber-700">同意待ち</span>}
                              </td>
                              <td className="px-3 py-2 text-slate-600 whitespace-nowrap">{a.office_name}・{a.class_name ?? "—"}</td>
                              <td className="px-3 py-2 font-semibold text-rose-700">{(a.allergens ?? []).join("・") || "—"}</td>
                              <td className="px-3 py-2 whitespace-pre-wrap text-slate-600">{a.substitute || "（当日の除去食献立が未登録）"}</td>
                              <td className="px-3 py-2 text-right tabular-nums">1</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    )}
                  </div>
                  {bento.length > 0 && (
                    <div className="rounded-2xl border border-slate-200 bg-slate-50 px-4 py-3 text-sm">
                      <span className="font-bold text-slate-600">弁当持参(提供なし・作らない)：</span>
                      <span className="text-slate-600">{bento.map((b) => `${b.child_name}(${b.office_name})`).join("・")}</span>
                    </div>
                  )}
                </div>
              );
            })()}
          </>
        )}
      </main>
    </div>
  );
}

export default function ChildcareMealSummaryPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-500">読み込み中…</div>}>
      <MealSummaryContent />
    </Suspense>
  );
}
