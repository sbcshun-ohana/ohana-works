"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 登降園管理 Phase A(314)。日別=登降園時刻の行内修正+打刻漏れ強調、月間=俯瞰。主任以上。
type Row = {
  child_id: string;
  child_name: string;
  class_name: string | null;
  business_date: string;
  in_time: string | null;
  out_time: string | null;
  return_time: string | null;
  depart_time: string | null;
  is_absent: boolean;
  absence_reason: string | null;
};
type Edit = { in: string; out: string; ret: string; depart: string };
// Phase B(317): 要確認(anomaly)。severity=action は補正必須(確認済み不可)。
type Anomaly = { child_id: string; business_date: string; anomaly_type: string; label: string; severity: string };
const anomKey = (childId: string, date: string) => `${childId}__${date.slice(0, 10)}`;

function todayStr(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
const hhmm = (t: string | null) => (t ? t.slice(0, 5) : "");

function AttendanceContent() {
  const { officesError, selectedOffice } = useChildcareOffices();
  const now = new Date();
  const [mode, setMode] = useState<"day" | "month">("day");
  const [date, setDate] = useState(todayStr());
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [rows, setRows] = useState<Row[]>([]);
  const [anomalies, setAnomalies] = useState<Anomaly[]>([]);
  const [edits, setEdits] = useState<Record<string, Edit>>({});
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    if (!selectedOffice) return;
    const p = (n: number) => String(n).padStart(2, "0");
    const start = mode === "day" ? date : `${year}-${p(month)}-01`;
    const end = mode === "day" ? date : `${year}-${p(month)}-${p(new Date(year, month, 0).getDate())}`;
    const supabase = createClient();
    supabase
      .rpc("fetch_attendance_matrix_for_office", { p_office_id: selectedOffice, p_start: start, p_end: end })
      .then(({ data, error }) => {
        if (error) { setErr(error.message); setRows([]); return; }
        setErr(null);
        const rs = (data ?? []) as Row[];
        setRows(rs);
        if (mode === "day") {
          const e: Record<string, Edit> = {};
          for (const r of rs) e[r.child_id] = { in: hhmm(r.in_time), out: hhmm(r.out_time), ret: hhmm(r.return_time), depart: hhmm(r.depart_time) };
          setEdits(e);
        }
      });
    // 要確認(317)。付加情報のため失敗しても本体表示は継続。
    supabase
      .rpc("fetch_attendance_anomalies_for_office", { p_office_id: selectedOffice, p_start: start, p_end: end })
      .then(({ data }) => setAnomalies((data ?? []) as Anomaly[]));
  }, [selectedOffice, mode, date, year, month, reloadToken]);

  // (child_id+日) → 要確認ラベル配列。
  const anomByKey = new Map<string, string[]>();
  for (const a of anomalies) {
    const k = anomKey(a.child_id, a.business_date);
    if (!anomByKey.has(k)) anomByKey.set(k, []);
    anomByKey.get(k)!.push(a.label);
  }

  async function saveActuals(childId: string) {
    const e = edits[childId];
    if (!e) return;
    setBusy(true);
    const { error } = await createClient().rpc("set_child_attendance_actuals", {
      p_child_id: childId, p_business_date: date,
      p_in: e.in || null, p_out: e.out || null, p_return: e.ret || null, p_depart: e.depart || null,
    });
    setBusy(false);
    if (error) return setErr(error.message);
    setErr(null);
    setReloadToken((t) => t + 1);
  }

  async function toggleAbsent(childId: string, absent: boolean) {
    setBusy(true);
    const { error } = await createClient().rpc("set_child_daily_attendance", {
      p_child_id: childId, p_business_date: date, p_is_absent: absent, p_absence_reason: null,
    });
    setBusy(false);
    if (error) return setErr(error.message);
    setReloadToken((t) => t + 1);
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
      <main className="flex-1 space-y-4 p-6">
        <div className="flex flex-wrap items-center gap-3">
          <h2 className="text-lg font-bold text-slate-800">登降園管理</h2>
          <div className="ml-2 flex gap-1 rounded-lg bg-slate-100 p-1">
            <button onClick={() => setMode("day")} className={`rounded-md px-3 py-1 text-sm font-semibold ${mode === "day" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>日別(修正)</button>
            <button onClick={() => setMode("month")} className={`rounded-md px-3 py-1 text-sm font-semibold ${mode === "month" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>月間(俯瞰)</button>
          </div>
          {mode === "day" ? (
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
          ) : (
            <>
              <select value={year} onChange={(e) => setYear(Number(e.target.value))} className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                {[year - 1, year, year + 1].map((y) => <option key={y} value={y}>{y}年</option>)}
              </select>
              <select value={month} onChange={(e) => setMonth(Number(e.target.value))} className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => <option key={m} value={m}>{m}月</option>)}
              </select>
            </>
          )}
          <span className="text-xs text-slate-400">※ 赤=要確認(補正が必要)。編集は主任以上。</span>
        </div>
        {anomalies.length > 0 && (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-2 text-sm text-red-700">
            <span className="font-bold">⚠ 要確認 {anomalies.length}件</span>
            <span className="ml-2 text-red-600">— 登降園実績を補正してください(補正まで請求候補に進みません)。</span>
          </div>
        )}
        {err && <div className="rounded-lg bg-red-50 px-4 py-2 text-sm text-red-600">{err}</div>}

        {mode === "day" ? <DayView /> : <MonthView />}
      </main>
    </div>
  );

  function DayView() {
    return (
      <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
              <th className="px-3 py-2">クラス</th><th className="px-3 py-2">園児</th><th className="px-3 py-2">欠席</th>
              <th className="px-3 py-2">登園</th><th className="px-3 py-2">外出</th><th className="px-3 py-2">戻り</th><th className="px-3 py-2">降園</th><th className="px-3 py-2"></th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan={8} className="px-3 py-6 text-center text-slate-400">在籍児がいません</td></tr>}
            {rows.map((r) => {
              const e = edits[r.child_id] ?? { in: "", out: "", ret: "", depart: "" };
              const set = (k: keyof Edit, v: string) => setEdits((prev) => ({ ...prev, [r.child_id]: { ...e, [k]: v } }));
              const anoms = anomByKey.get(anomKey(r.child_id, date)) ?? [];
              const miss = anoms.length > 0;
              return (
                <tr key={r.child_id} className={`border-b border-slate-100 ${miss ? "bg-red-50" : ""}`}>
                  <td className="px-3 py-2 text-slate-500">{r.class_name ?? "—"}</td>
                  <td className="px-3 py-2 font-medium text-slate-800">
                    {r.child_name}
                    {anoms.map((l) => (
                      <span key={l} className="ml-1 rounded bg-red-100 px-1.5 py-0.5 text-xs font-bold text-red-600">{l}</span>
                    ))}
                  </td>
                  <td className="px-3 py-2">
                    <input type="checkbox" checked={r.is_absent} onChange={(ev) => void toggleAbsent(r.child_id, ev.target.checked)} />
                  </td>
                  {(["in", "out", "ret", "depart"] as (keyof Edit)[]).map((k) => (
                    <td key={k} className="px-2 py-2">
                      <input type="time" value={e[k]} disabled={r.is_absent} onChange={(ev) => set(k, ev.target.value)}
                        className="rounded border border-slate-300 px-1 py-1 text-sm disabled:bg-slate-100" />
                    </td>
                  ))}
                  <td className="px-3 py-2">
                    <button disabled={busy || r.is_absent} onClick={() => void saveActuals(r.child_id)}
                      className="rounded-lg bg-emerald-600 px-3 py-1 text-xs font-semibold text-white hover:bg-emerald-700 disabled:opacity-40">保存</button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    );
  }

  function MonthView() {
    const daysInMonth = new Date(year, month, 0).getDate();
    const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);
    // 園児ごとに日→row をまとめる。
    const byChild = new Map<string, { name: string; cls: string | null; days: Map<number, Row> }>();
    for (const r of rows) {
      const d = new Date(r.business_date).getDate();
      if (!byChild.has(r.child_id)) byChild.set(r.child_id, { name: r.child_name, cls: r.class_name, days: new Map() });
      byChild.get(r.child_id)!.days.set(d, r);
    }
    const children = [...byChild.entries()];
    return (
      <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
        <table className="text-xs">
          <thead>
            <tr className="border-b border-slate-200 text-slate-500">
              <th className="sticky left-0 bg-white px-2 py-2 text-left">園児</th>
              {days.map((d) => <th key={d} className="px-1 py-2 text-center">{d}</th>)}
            </tr>
          </thead>
          <tbody>
            {children.length === 0 && <tr><td colSpan={daysInMonth + 1} className="px-3 py-6 text-center text-slate-400">この月の記録はありません</td></tr>}
            {children.map(([cid, c]) => (
              <tr key={cid} className="border-b border-slate-100">
                <td className="sticky left-0 bg-white px-2 py-1 font-medium text-slate-700 whitespace-nowrap">{c.name}<span className="ml-1 text-slate-400">{c.cls ?? ""}</span></td>
                {days.map((d) => {
                  const r = c.days.get(d);
                  if (!r) return <td key={d} className="px-1 py-1 text-center text-slate-300">·</td>;
                  if (r.is_absent) return <td key={d} className="px-1 py-1 text-center font-bold text-slate-400" title={r.absence_reason ?? "欠席"}>欠</td>;
                  const anoms = anomByKey.get(anomKey(r.child_id, r.business_date)) ?? [];
                  const miss = anoms.length > 0;
                  return (
                    <td key={d} className={`px-1 py-1 text-center ${miss ? "bg-red-100 font-bold text-red-600" : "text-slate-600"}`}
                      title={miss ? `要確認: ${anoms.join(" / ")}` : `${hhmm(r.in_time) || "—"} 〜 ${hhmm(r.depart_time) || "—"}`}>
                      {miss ? "!" : "◯"}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  }
}

export default function ChildcareAttendancePage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-500">読み込み中…</div>}>
      <AttendanceContent />
    </Suspense>
  );
}
