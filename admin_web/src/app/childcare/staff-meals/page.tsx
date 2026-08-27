"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 職員の食事管理表(月次)。自己注文モデル(365-371)。fetch_staff_meal_ledger を職員×日でピボット。
// セルをクリックで◯(食べる)/×(食べない)を編集(set_staff_meal_day)。請求=この◯の集計。
type LedgerRow = { employee_id: string; employee_name: string; business_date: string; source: string };

function pad(n: number) { return String(n).padStart(2, "0"); }

function StaffMealsContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const now = new Date();
  const [officeId, setOfficeId] = useState("");
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [rows, setRows] = useState<LedgerRow[]>([]);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const effOffice = officeId || selectedOffice;
  const monthParam = `${year}-${pad(month)}-01`;
  const daysInMonth = new Date(year, month, 0).getDate();

  const [reload, setReload] = useState(0);
  useEffect(() => {
    if (!effOffice) return;
    createClient()
      .rpc("fetch_staff_meal_ledger", { p_office: effOffice, p_month: monthParam })
      .then(({ data, error }) => {
        if (error) { setErr(error.message); setRows([]); return; }
        setErr(null);
        setRows((data ?? []) as LedgerRow[]);
      });
  }, [effOffice, monthParam, reload]);

  // 職員ごとに 日→source のマップへ集約
  const byEmployee = new Map<string, { name: string; days: Map<number, string> }>();
  for (const r of rows) {
    const day = Number(r.business_date.slice(8, 10));
    if (!byEmployee.has(r.employee_id)) byEmployee.set(r.employee_id, { name: r.employee_name, days: new Map() });
    byEmployee.get(r.employee_id)!.days.set(day, r.source);
  }
  const employees = [...byEmployee.entries()].sort((a, b) => a[1].name.localeCompare(b[1].name, "ja"));

  async function toggleCell(employeeId: string, day: number, currentlyEating: boolean) {
    if (busy) return;
    const date = `${year}-${pad(month)}-${pad(day)}`;
    setBusy(true);
    const { error } = await createClient().rpc("set_staff_meal_day", {
      p_office: effOffice, p_date: date, p_employee: employeeId, p_will_eat: !currentlyEating,
    });
    setBusy(false);
    if (error) { alert(`変更できません: ${error.message}`); return; }
    setReload((n) => n + 1);
  }

  async function reflectToPayroll() {
    if (!window.confirm(`${year}年${month}月の給食控除を給与へ反映します(全施設分を職員ごとに集計)。よろしいですか?`)) return;
    setBusy(true);
    const { data, error } = await createClient().rpc("aggregate_staff_meal_deductions", { p_month: monthParam });
    setBusy(false);
    if (error) { alert(`反映できません: ${error.message}`); return; }
    alert(`${(data as number | null) ?? 0}名の給食控除を給与へ反映しました。`);
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
        <h2 className="text-lg font-bold text-slate-800">職員の食事管理表(月次)</h2>
        {err && <div className="rounded-lg bg-red-50 px-4 py-2 text-sm text-red-600">{err}</div>}

        <div className="flex flex-wrap items-center gap-3">
          <label className="text-sm">
            <span className="mb-1 block font-medium text-slate-600">施設</span>
            <select value={effOffice} onChange={(e) => setOfficeId(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2">
              {(offices ?? []).map((o) => <option key={o.office_id} value={o.office_id}>{o.office_name}</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className="mb-1 block font-medium text-slate-600">年</span>
            <select value={year} onChange={(e) => setYear(Number(e.target.value))} className="rounded-lg border border-slate-300 px-3 py-2">
              {[now.getFullYear() - 1, now.getFullYear(), now.getFullYear() + 1].map((y) => <option key={y} value={y}>{y}年</option>)}
            </select>
          </label>
          <label className="text-sm">
            <span className="mb-1 block font-medium text-slate-600">月</span>
            <select value={month} onChange={(e) => setMonth(Number(e.target.value))} className="rounded-lg border border-slate-300 px-3 py-2">
              {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => <option key={m} value={m}>{m}月</option>)}
            </select>
          </label>
          <button onClick={() => setReload((n) => n + 1)} className="mt-5 rounded-lg border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">再読込</button>
          <button onClick={() => { void reflectToPayroll(); }} disabled={busy}
            className="mt-5 rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50">
            給与控除へ反映
          </button>
        </div>

        <p className="text-xs text-slate-400">
          セルをクリックで <span className="font-bold text-emerald-600">◯</span>(食べる)/ 空欄(食べない)を切替。
          <span className="font-bold text-amber-600"> ◯</span> = 手動で追加した日。請求は◯の食数×単価(O/M/S=300円・H=250円)で給与へ控除します。
          締切(当日8:55)後・過去月の変更は権限・期限の制限があります。
        </p>

        <div className="overflow-x-auto rounded-2xl border border-slate-200 bg-white shadow-sm">
          {employees.length === 0 ? (
            <div className="p-6 text-center text-sm text-slate-400">この月の食事記録はありません(本人の注文または朝の発注画面で登録されます)</div>
          ) : (
            <table className="min-w-full border-collapse text-xs">
              <thead>
                <tr className="bg-slate-100 text-slate-600">
                  <th className="sticky left-0 z-10 border-b border-r border-slate-200 bg-slate-100 px-3 py-2 text-left">職員</th>
                  <th className="border-b border-r border-slate-200 px-2 py-2">食数</th>
                  {Array.from({ length: daysInMonth }, (_, i) => i + 1).map((d) => {
                    const wd = new Date(year, month - 1, d).getDay(); // 0=日,6=土
                    return (
                      <th key={d} className={`border-b border-l border-slate-200 px-1 py-2 text-center font-medium tabular-nums ${wd === 0 ? "text-red-400" : wd === 6 ? "text-sky-400" : ""}`}>{d}</th>
                    );
                  })}
                </tr>
              </thead>
              <tbody>
                {employees.map(([id, emp], ri) => (
                  <tr key={id} className={ri % 2 === 1 ? "bg-slate-50" : "bg-white"}>
                    <td className={`sticky left-0 z-10 border-b border-r border-slate-200 px-3 py-2 font-medium text-slate-800 whitespace-nowrap ${ri % 2 === 1 ? "bg-slate-50" : "bg-white"}`}>{emp.name}</td>
                    <td className="border-b border-r border-slate-200 px-2 py-2 text-center font-bold tabular-nums">{emp.days.size}</td>
                    {Array.from({ length: daysInMonth }, (_, i) => i + 1).map((d) => {
                      const source = emp.days.get(d);
                      const eating = source !== undefined;
                      const color = !eating ? "" : source === "manual" ? "text-amber-600" : "text-emerald-600";
                      return (
                        <td key={d}
                          onClick={() => { void toggleCell(id, d, eating); }}
                          title={eating ? (source === "manual" ? "手動で追加" : source === "self_order" ? "本人注文" : "曜日テンプレ") : "クリックで追加"}
                          className={`cursor-pointer border-b border-l border-slate-200 px-1 py-2 text-center font-bold hover:bg-sky-50 ${color}`}>
                          {eating ? "◯" : ""}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </main>
    </div>
  );
}

export default function ChildcareStaffMealsPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-500">読み込み中…</div>}>
      <StaffMealsContent />
    </Suspense>
  );
}
