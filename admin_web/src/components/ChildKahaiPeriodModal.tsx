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
  const [err, setErr] = useState<string | null>(null);
  const [editId, setEditId] = useState<string | null>(null); // 編集中の期間
  const [editStart, setEditStart] = useState("");
  const [editEnd, setEditEnd] = useState("");
  const [editNote, setEditNote] = useState("");

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const s = createClient();
      const { data, error } = await s.rpc("fetch_child_kahai_periods", { p_child_id: childId });
      if (cancelled) return;
      if (error) { setErr(`取得エラー: ${error.message}`); return; }
      setPeriods((data ?? []) as Period[]);
    })();
    return () => { cancelled = true; };
  }, [childId, reload]);

  async function add() {
    if (!start) { setErr("開始日を入力してください"); return; }
    setBusy(true);
    setErr(null);
    const s = createClient();
    const { error } = await s.rpc("add_child_kahai_period", { p_child_id: childId, p_start: start, p_end: end || null, p_note: note || null });
    setBusy(false);
    if (error) { setErr(`登録できません: ${error.message}`); return; }
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
  function startEdit(p: Period) {
    setEditId(p.id); setEditStart(p.start_date); setEditEnd(p.end_date ?? ""); setEditNote(p.note ?? ""); setErr(null);
  }
  // 期間の後からの変更(開始/終了日・メモ)。終了日を早める短縮もここで行う。
  async function saveEdit(id: string) {
    if (!editStart) { setErr("開始日を入力してください"); return; }
    setBusy(true); setErr(null);
    const s = createClient();
    const { error } = await s.rpc("update_child_kahai_period", { p_id: id, p_start: editStart, p_end: editEnd || null, p_note: editNote || null });
    setBusy(false);
    if (error) { setErr(`変更できません: ${error.message}`); return; }
    setEditId(null);
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
        {err && <p className="mt-2 rounded-lg bg-red-50 p-2 text-sm font-medium text-red-600">{err}</p>}

        <div className="mt-3 space-y-2">
          {periods.length === 0 && <p className="text-sm text-slate-400">加配の履歴はありません</p>}
          {periods.map((p) => (
            <div key={p.id} className="rounded-lg border border-slate-200 p-2 text-sm">
              {editId === p.id ? (
                <div className="flex flex-wrap items-end gap-2">
                  <label className="text-xs text-slate-500">開始日
                    <input type="date" value={editStart} onChange={(e) => setEditStart(e.target.value)} className="mt-0.5 block rounded border border-slate-300 px-2 py-1 text-sm" />
                  </label>
                  <label className="text-xs text-slate-500">終了日(空=継続中)
                    <input type="date" value={editEnd} onChange={(e) => setEditEnd(e.target.value)} className="mt-0.5 block rounded border border-slate-300 px-2 py-1 text-sm" />
                  </label>
                  <label className="flex-1 text-xs text-slate-500">メモ
                    <input type="text" value={editNote} onChange={(e) => setEditNote(e.target.value)} className="mt-0.5 block w-full rounded border border-slate-300 px-2 py-1 text-sm" />
                  </label>
                  <button onClick={() => saveEdit(p.id)} disabled={busy} className="rounded-lg bg-violet-600 px-3 py-1 text-xs font-semibold text-white hover:bg-violet-700 disabled:opacity-50">保存</button>
                  <button onClick={() => setEditId(null)} className="rounded-lg border border-slate-300 px-3 py-1 text-xs text-slate-500">キャンセル</button>
                </div>
              ) : (
                <div className="flex flex-wrap items-center gap-2">
                  <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${isActive(p) ? "bg-violet-50 text-violet-700" : "bg-slate-100 text-slate-500"}`}>
                    {isActive(p) ? "適用中" : "期間外"}
                  </span>
                  <span className="font-medium text-slate-700">{p.start_date} 〜 {p.end_date ?? "継続中"}</span>
                  {p.note && <span className="text-xs text-slate-500">{p.note}</span>}
                  <div className="ml-auto flex items-center gap-3">
                    <button onClick={() => startEdit(p)} className="text-xs font-semibold text-sky-600 hover:underline">編集</button>
                    <button onClick={() => del(p.id)} className="text-xs text-red-500 hover:underline">削除</button>
                  </div>
                </div>
              )}
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
