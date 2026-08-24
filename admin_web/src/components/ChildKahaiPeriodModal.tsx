"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

// 加配(個人案対象)の適用期間・履歴の編集(291)。加配になる期間・外れる期間を複数登録できる。
type Period = { id: string; start_date: string; end_date: string | null; note: string | null };

export function ChildKahaiPeriodModal({ childId, childName, onClose }: { childId: string; childName: string; onClose: () => void }) {
  const [periods, setPeriods] = useState<Period[]>([]);
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const s = createClient();
      const { data } = await s.rpc("fetch_child_kahai_periods", { p_child_id: childId });
      if (!cancelled) setPeriods((data ?? []) as Period[]);
    })();
    return () => { cancelled = true; };
  }, [childId, reload]);

  async function add() {
    if (!start) { alert("開始日を入力してください"); return; }
    setBusy(true);
    const s = createClient();
    const { error } = await s.rpc("add_child_kahai_period", { p_child_id: childId, p_start: start, p_end: end || null, p_note: note || null });
    setBusy(false);
    if (error) { alert(`登録できません: ${error.message}`); return; }
    setStart(""); setEnd(""); setNote("");
    setReload((t) => t + 1);
  }
  async function del(id: string) {
    if (!window.confirm("この加配期間を削除しますか?")) return;
    const s = createClient();
    const { error } = await s.rpc("delete_child_kahai_period", { p_id: id });
    if (error) { alert(`削除できません: ${error.message}`); return; }
    setReload((t) => t + 1);
  }

  const today = new Date().toISOString().slice(0, 10);
  const isActive = (p: Period) => p.start_date <= today && (!p.end_date || p.end_date >= today);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={onClose}>
      <div className="w-full max-w-lg rounded-2xl bg-white p-5 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h3 className="text-base font-bold text-slate-800">加配(個人案対象)の期間 — {childName}</h3>
          <button onClick={onClose} className="text-sm text-slate-400 hover:text-slate-600">閉じる</button>
        </div>
        <p className="mt-1 text-xs text-slate-400">加配になる期間を登録します。外れたら終了日を入れて履歴として残します。期間中はその月の月案に個人案が必要になります。</p>

        <div className="mt-3 space-y-2">
          {periods.length === 0 && <p className="text-sm text-slate-400">加配の履歴はありません</p>}
          {periods.map((p) => (
            <div key={p.id} className="flex flex-wrap items-center gap-2 rounded-lg border border-slate-200 p-2 text-sm">
              <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${isActive(p) ? "bg-violet-50 text-violet-700" : "bg-slate-100 text-slate-500"}`}>
                {isActive(p) ? "適用中" : "期間外"}
              </span>
              <span className="font-medium text-slate-700">{p.start_date} 〜 {p.end_date ?? "継続中"}</span>
              {p.note && <span className="text-xs text-slate-500">{p.note}</span>}
              <button onClick={() => del(p.id)} className="ml-auto text-xs text-red-500 hover:underline">削除</button>
            </div>
          ))}
        </div>

        <div className="mt-4 rounded-xl bg-slate-50 p-3">
          <p className="mb-2 text-sm font-semibold text-slate-600">加配期間を追加</p>
          <div className="flex flex-wrap items-end gap-2">
            <label className="text-xs text-slate-500">開始日
              <input type="date" value={start} onChange={(e) => setStart(e.target.value)} className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1 text-sm" />
            </label>
            <label className="text-xs text-slate-500">終了日(任意)
              <input type="date" value={end} onChange={(e) => setEnd(e.target.value)} className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1 text-sm" />
            </label>
            <label className="flex-1 text-xs text-slate-500">メモ(任意)
              <input type="text" value={note} onChange={(e) => setNote(e.target.value)} placeholder="例: ◯◯支援のため" className="mt-0.5 block w-full rounded-lg border border-slate-300 px-2 py-1 text-sm" />
            </label>
            <button onClick={add} disabled={busy} className="rounded-lg bg-violet-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-violet-700 disabled:opacity-50">追加</button>
          </div>
        </div>
      </div>
    </div>
  );
}
