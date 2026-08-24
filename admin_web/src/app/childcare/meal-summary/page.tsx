"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

type MonthlyRow = {
  business_date: string;
  am_child: number; am_staff: number;
  lunch_child: number; lunch_staff: number;
  pm_child: number; pm_staff: number;
  leftover_grams: number | null;
};
type CrossRow = {
  office_id: string; office_name: string; office_code: string;
  meal_slot: string; child_total: number; staff_total: number;
};

const SLOTS: { key: string; label: string }[] = [
  { key: "am_snack", label: "朝おやつ" },
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
  const [mode, setMode] = useState<"monthly" | "cross">("monthly");
  const [officeId, setOfficeId] = useState("");
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [monthly, setMonthly] = useState<MonthlyRow[]>([]);
  const [crossDate, setCrossDate] = useState(todayStr());
  const [cross, setCross] = useState<CrossRow[]>([]);
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

  // 食事区分横断(閲覧可能な全施設)
  useEffect(() => {
    if (mode !== "cross" || !offices || offices.length === 0) return;
    const ids = offices.map((o) => o.office_id);
    createClient()
      .rpc("fetch_meal_slot_crossoffice", { p_office_ids: ids, p_business_date: crossDate })
      .then(({ data, error }) => {
        if (error) { setErr(error.message); setCross([]); return; }
        setErr(null);
        setCross((data ?? []) as CrossRow[]);
      });
  }, [mode, offices, crossDate]);

  const sum = (k: keyof MonthlyRow) => monthly.reduce((a, r) => a + (Number(r[k]) || 0), 0);

  async function exportMonthlyExcel() {
    const XLSX = await import("xlsx");
    const officeName = offices?.find((o) => o.office_id === effOffice)?.office_name ?? "";
    const aoa: (string | number)[][] = [
      [`月別食数集計  ${officeName}  ${year}年${month}月`],
      [],
      ["日付", "朝おやつ(児)", "朝おやつ(職)", "昼食(児)", "昼食(職)", "午後おやつ(児)", "午後おやつ(職)", "残量(g)"],
    ];
    for (const r of monthly) {
      const d = new Date(r.business_date);
      aoa.push([`${d.getMonth() + 1}/${d.getDate()}`, r.am_child, r.am_staff, r.lunch_child, r.lunch_staff, r.pm_child, r.pm_staff, r.leftover_grams ?? ""]);
    }
    aoa.push(["月合計", sum("am_child"), sum("am_staff"), sum("lunch_child"), sum("lunch_staff"), sum("pm_child"), sum("pm_staff"), sum("leftover_grams")]);
    const ws = XLSX.utils.aoa_to_sheet(aoa);
    ws["!cols"] = [{ wch: 8 }, ...Array(7).fill({ wch: 12 })];
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
          <h2 className="text-lg font-bold text-slate-800">食数集計</h2>
          <div className="ml-4 flex gap-1 rounded-lg bg-slate-100 p-1">
            <button onClick={() => setMode("monthly")}
              className={`rounded-md px-3 py-1 text-sm font-semibold ${mode === "monthly" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>月別集計</button>
            <button onClick={() => setMode("cross")}
              className={`rounded-md px-3 py-1 text-sm font-semibold ${mode === "cross" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>食事区分ごと(全施設)</button>
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
                  <th className="px-3 py-2">日付</th><th className="px-3 py-2">朝おやつ</th><th className="px-3 py-2">昼食</th><th className="px-3 py-2">午後おやつ</th><th className="px-3 py-2">残量(g)</th>
                </tr></thead>
                <tbody>
                  {monthly.length === 0 && <tr><td colSpan={5} className="px-3 py-6 text-center text-slate-400">この月の食数データはありません</td></tr>}
                  {monthly.map((r) => {
                    const d = new Date(r.business_date);
                    return (
                      <tr key={r.business_date} className="border-b border-slate-100 last:border-0">
                        <td className="px-3 py-2 font-medium text-slate-700">{d.getMonth() + 1}/{d.getDate()}</td>
                        <td className="px-3 py-2">児{r.am_child} / 職{r.am_staff}</td>
                        <td className="px-3 py-2">児{r.lunch_child} / 職{r.lunch_staff}</td>
                        <td className="px-3 py-2">児{r.pm_child} / 職{r.pm_staff}</td>
                        <td className="px-3 py-2">{r.leftover_grams ?? "—"}</td>
                      </tr>
                    );
                  })}
                  {monthly.length > 0 && (
                    <tr className="bg-slate-50 font-bold">
                      <td className="px-3 py-2">月合計</td>
                      <td className="px-3 py-2">児{sum("am_child")} / 職{sum("am_staff")}</td>
                      <td className="px-3 py-2">児{sum("lunch_child")} / 職{sum("lunch_staff")}</td>
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
            <input type="date" value={crossDate} onChange={(e) => setCrossDate(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
            <div className="grid gap-4 md:grid-cols-3">
              {SLOTS.map((slot) => {
                const rows = cross.filter((r) => r.meal_slot === slot.key);
                const total = rows.reduce((a, r) => a + r.child_total + r.staff_total, 0);
                return (
                  <div key={slot.key} className="rounded-2xl bg-white p-4 shadow-sm">
                    <div className="mb-2 flex items-center justify-between border-b border-slate-100 pb-2">
                      <span className="text-base font-bold text-amber-600">{slot.label}</span>
                      <span className="text-base font-bold">計 {total} 食</span>
                    </div>
                    {rows.length === 0 ? (
                      <div className="py-4 text-center text-sm text-slate-400">データなし</div>
                    ) : rows.map((r) => (
                      <div key={r.office_id} className="flex items-center justify-between py-1 text-sm">
                        <span className="font-medium text-slate-700">{r.office_name}</span>
                        <span className="text-slate-400">児{r.child_total} / 職{r.staff_total}</span>
                        <span className="font-bold">{r.child_total + r.staff_total} 食</span>
                      </div>
                    ))}
                  </div>
                );
              })}
            </div>
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
