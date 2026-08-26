"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 職員の食事管理表(月次)。給食管理 Phase3(336)。fetch_staff_meal_ledger を職員×日でピボット。
type LedgerRow = { employee_id: string; employee_name: string; business_date: string; source: string; has_attendance: boolean };
// 別施設で同日に給食が付いた重複(入力ミス兆候)。migration 350。
type ConflictRow = { employee_id: string; employee_name: string; business_date: string; office_names: string[] };
// 勤怠なしで請求できない職員給食(赤丸)。migration 358。
type UnbillableRow = { employee_id: string; employee_name: string; office_name: string; business_date: string; source: string };

function pad(n: number) { return String(n).padStart(2, "0"); }

function StaffMealsContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const now = new Date();
  const [officeId, setOfficeId] = useState("");
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [rows, setRows] = useState<LedgerRow[]>([]);
  const [conflicts, setConflicts] = useState<ConflictRow[]>([]);
  const [unbillable, setUnbillable] = useState<UnbillableRow[]>([]);
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

  // 別施設で同日重複(入力ミス兆候)を月内で検知(全施設横断)。施設に依存しないので月だけで再取得。
  useEffect(() => {
    createClient()
      .rpc("fetch_staff_meal_conflicts", { p_month: monthParam })
      .then(({ data }) => setConflicts((data ?? []) as ConflictRow[]));
  }, [monthParam, reload]);

  // 勤怠なしで請求できない職員給食(赤丸)を月内で検知(全施設横断)。
  useEffect(() => {
    createClient()
      .rpc("fetch_staff_meal_unbillable", { p_month: monthParam })
      .then(({ data }) => setUnbillable((data ?? []) as UnbillableRow[]));
  }, [monthParam, reload]);

  // 職員ごとに 日→source のマップへ集約
  const byEmployee = new Map<string, { name: string; days: Map<number, { source: string; att: boolean }> }>();
  for (const r of rows) {
    const day = Number(r.business_date.slice(8, 10));
    if (!byEmployee.has(r.employee_id)) byEmployee.set(r.employee_id, { name: r.employee_name, days: new Map() });
    byEmployee.get(r.employee_id)!.days.set(day, { source: r.source, att: r.has_attendance });
  }
  const employees = [...byEmployee.entries()].sort((a, b) => a[1].name.localeCompare(b[1].name, "ja"));

  // 重複(職員×日)のセル強調用キー: `${employee_id}|${day}`
  const conflictCells = new Set(conflicts.map((c) => `${c.employee_id}|${Number(c.business_date.slice(8, 10))}`));

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
          <span className="font-bold text-sky-600">●</span> = 実勤務あり(請求可) /
          <span className="font-bold text-red-500"> ●</span> = 勤怠なし(シフトはあるが打刻なし=請求不可) / 空欄 = 対象外。「給与控除へ反映」は実勤務のある日のみ集計し、単価(O/M/S=300円・H=250円)で控除額を給与へ転記します(赤=請求から除外)。
        </p>

        {/* 勤怠なしで請求できない職員給食(赤丸)の警告。実勤務が確認できない=給与控除から除外される。 */}
        {unbillable.length > 0 && (
          <div className="rounded-2xl border border-red-300 bg-red-50 px-4 py-3 text-sm">
            <div className="font-bold text-red-700">⚠ 勤怠が確認できず請求できない職員給食があります({unbillable.length}件)</div>
            <p className="mt-0.5 text-xs text-red-600">シフトから給食が計上されていますが、その日の実勤怠(打刻)が無いため給与控除の対象外です。実際に喫食した場合は勤怠の登録を、していない場合は該当日を確認してください。</p>
            <ul className="mt-2 space-y-0.5 text-xs text-red-700">
              {unbillable.map((u) => (
                <li key={`${u.employee_id}-${u.business_date}`}>
                  {(() => { const d = new Date(u.business_date); return `${d.getMonth() + 1}/${d.getDate()}`; })()}・<span className="font-semibold">{u.employee_name}</span>({u.office_name})：{u.source === "auto" ? "シフト自動" : "自己発注"}
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* 別施設で同日に給食が付いた重複(入力ミス兆候)のアラート。正データはunique制約で1件のため給与は正しいが、シフト重複の是正を促す。 */}
        {conflicts.length > 0 && (
          <div className="rounded-2xl border border-red-300 bg-red-50 px-4 py-3 text-sm">
            <div className="font-bold text-red-700">⚠ 別施設で同じ職員に同日の給食が付いています({conflicts.length}件)</div>
            <p className="mt-0.5 text-xs text-red-600">同一職員が同じ日に複数施設でフルカバー確定シフト/自己発注を持つと、食数ボードで二重計上され得ます。シフトを確認してください(給与控除は正データで1件のため二重にはなりません)。</p>
            <ul className="mt-2 space-y-0.5 text-xs text-red-700">
              {conflicts.map((c) => (
                <li key={`${c.employee_id}-${c.business_date}`}>
                  {(() => { const d = new Date(c.business_date); return `${d.getMonth() + 1}/${d.getDate()}`; })()}・<span className="font-semibold">{c.employee_name}</span>：{c.office_names.join(" / ")}
                </li>
              ))}
            </ul>
          </div>
        )}

        <div className="overflow-x-auto rounded-2xl border border-slate-200 bg-white shadow-sm">
          {employees.length === 0 ? (
            <div className="p-6 text-center text-sm text-slate-400">この月の食事記録はありません(9:31の食数算出で記録されます)</div>
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
                      const cell = emp.days.get(d);
                      const dup = conflictCells.has(`${id}|${d}`);
                      // 青●=実勤務あり(請求可) / 赤●=勤怠なし(請求不可)。空欄=対象外。
                      const color = !cell ? "" : cell.att ? "text-sky-600" : "text-red-500";
                      return (
                        <td key={d} title={cell ? `${cell.source === "auto" ? "シフト自動" : "自己発注"}${cell.att ? "" : "・勤怠なし(請求不可)"}` : ""}
                          className={`border-b border-l border-slate-200 px-1 py-2 text-center ${color} ${dup ? "bg-red-100 ring-1 ring-inset ring-red-400" : ""}`}>
                          {cell ? "●" : ""}
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
