"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 休園日カレンダー(施設別・375)。定休曜日/祝日は自動、園独自休園日は追加/削除できる。
// 出席簿の開所日数・網掛け・行政報告の日祝欄の基礎マスター。
type Day = { business_date: string; closed: boolean; reason: string | null; label: string | null };

const WD = ["日", "月", "火", "水", "木", "金", "土"];

function ClosureDaysContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const now = new Date();
  const [officeId, setOfficeId] = useState("");
  const [ym, setYm] = useState({ y: now.getFullYear(), m: now.getMonth() + 1 });
  const [days, setDays] = useState<Day[]>([]);
  const [openCount, setOpenCount] = useState<number | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [reload, setReload] = useState(0);
  const effOffice = officeId || selectedOffice;

  useEffect(() => {
    if (!effOffice) return;
    const s = createClient();
    void s.rpc("fetch_office_closure_calendar", { p_office: effOffice, p_year: ym.y, p_month: ym.m })
      .then(({ data, error }) => { if (error) { setErr(error.message); setDays([]); } else { setErr(null); setDays((data ?? []) as Day[]); } });
    void s.rpc("count_office_open_days", { p_office: effOffice, p_year: ym.y, p_month: ym.m })
      .then(({ data }) => setOpenCount((data as number | null) ?? null));
  }, [effOffice, ym, reload]);

  function changeMonth(delta: number) {
    setYm((p) => { const d = new Date(p.y, p.m - 1 + delta, 1); return { y: d.getFullYear(), m: d.getMonth() + 1 }; });
  }

  async function toggle(day: Day) {
    if (busy) return;
    if (day.reason === "holiday" || day.reason === "weekday_off") return; // 祝日・定休は自動(編集不可)
    setBusy(true);
    const s = createClient();
    if (day.reason === "custom") {
      const { error } = await s.rpc("delete_office_closure_day", { p_office: effOffice, p_date: day.business_date });
      setBusy(false);
      if (error) { alert(`解除できません: ${error.message}`); return; }
    } else {
      const note = window.prompt(`${day.business_date} を園の休園日にします。名称(任意):`, "");
      if (note === null) { setBusy(false); return; }
      const { error } = await s.rpc("set_office_closure_day", { p_office: effOffice, p_date: day.business_date, p_note: note || null });
      setBusy(false);
      if (error) { alert(`登録できません: ${error.message}`); return; }
    }
    setReload((n) => n + 1);
  }

  // カレンダーグリッド(先頭の曜日まで空セル)。
  const lead = new Date(ym.y, ym.m - 1, 1).getDay();
  const cells: (Day | null)[] = [...Array<Day | null>(lead).fill(null), ...days];

  function cellClass(day: Day): string {
    if (day.reason === "weekday_off") return "bg-slate-100 text-slate-400";
    if (day.reason === "holiday") return "bg-rose-50 text-rose-500";
    if (day.reason === "custom") return "bg-amber-100 text-amber-800 cursor-pointer hover:ring-2 hover:ring-amber-400";
    return "bg-white text-slate-700 cursor-pointer hover:bg-sky-50"; // 開所
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
      <main className="flex-1 space-y-5 p-6">
        <h2 className="text-lg font-bold text-slate-800">休園日カレンダー</h2>
        {err && <div className="rounded-lg bg-red-50 px-4 py-2 text-sm text-red-600">{err}</div>}

        <div className="flex flex-wrap items-center gap-3">
          <select value={effOffice} onChange={(e) => setOfficeId(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm">
            {(offices ?? []).map((o) => <option key={o.office_id} value={o.office_id}>{o.office_name}</option>)}
          </select>
          <div className="flex items-center gap-2">
            <button onClick={() => changeMonth(-1)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-50">◀</button>
            <span className="min-w-[7rem] text-center font-bold text-slate-800">{ym.y}年{ym.m}月</span>
            <button onClick={() => changeMonth(1)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm hover:bg-slate-50">▶</button>
          </div>
          {openCount !== null && (
            <span className="rounded-lg bg-emerald-50 px-3 py-1.5 text-sm font-semibold text-emerald-700">開所日数 {openCount}日</span>
          )}
        </div>

        <div className="flex flex-wrap gap-3 text-xs text-slate-500">
          <span><span className="mr-1 inline-block h-3 w-3 rounded-sm bg-slate-100 align-middle" />定休日</span>
          <span><span className="mr-1 inline-block h-3 w-3 rounded-sm bg-rose-50 align-middle" />祝日</span>
          <span><span className="mr-1 inline-block h-3 w-3 rounded-sm bg-amber-100 align-middle" />園の休園日(クリックで解除)</span>
          <span><span className="mr-1 inline-block h-3 w-3 rounded-sm border border-slate-200 bg-white align-middle" />開所日(クリックで休園に)</span>
        </div>

        <div className="max-w-3xl overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
          <div className="grid grid-cols-7 border-b border-slate-100 bg-slate-50 text-center text-xs font-semibold">
            {WD.map((w, i) => (
              <div key={w} className={`py-2 ${i === 0 ? "text-rose-500" : i === 6 ? "text-sky-500" : "text-slate-500"}`}>{w}</div>
            ))}
          </div>
          <div className="grid grid-cols-7">
            {cells.map((day, i) => day === null ? (
              <div key={`e${i}`} className="min-h-[70px] border-b border-r border-slate-100 bg-slate-50/40" />
            ) : (
              <div key={day.business_date}
                onClick={() => { void toggle(day); }}
                className={`min-h-[70px] border-b border-r border-slate-100 p-1.5 text-xs transition ${cellClass(day)}`}>
                <div className="font-bold">{Number(day.business_date.slice(8, 10))}</div>
                {day.label && <div className="mt-0.5 leading-tight">{day.label}</div>}
              </div>
            ))}
          </div>
        </div>

        <p className="text-xs text-slate-400">
          定休曜日と祝日は自動判定(編集不可)。園独自の休園日(開園記念日・夏季休園など)は開所日をクリックして登録・解除できます(施設管理者以上)。
          この休園日は出席簿の開所日数・網掛け、行政報告の日祝欄に反映されます。
        </p>
      </main>
    </div>
  );
}

export default function ChildcareClosureDaysPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-500">読み込み中…</div>}>
      <ClosureDaysContent />
    </Suspense>
  );
}
