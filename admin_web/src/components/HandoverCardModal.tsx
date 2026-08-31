"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

// 引き継ぎカード作成(209)。感染症ON施設のデイリーボード行アイコンから開く。
// iPad同様: 案件作成(create_infection_handover_case)→症状入力→送信(send_handover_card)。
// スナップショット(当日の検温・排便等)はサーバー側で固定される。

const RASH_LOCATIONS = ["顔", "首", "胸", "腹部", "背中", "腕", "手", "脚", "足", "臀部", "全身", "その他"];
const THREE_STATE: { value: string; label: string }[] = [
  { value: "yes", label: "あり" },
  { value: "no", label: "なし" },
  { value: "unchecked", label: "未確認" },
];

type Props = {
  childId: string;
  childName: string;
  onClose: () => void;
  onSent: () => void;
};

export function HandoverCardModal({ childId, childName, onClose, onSent }: Props) {
  const [hives, setHives] = useState("unchecked");
  const [rash, setRash] = useState("unchecked");
  const [rashLocations, setRashLocations] = useState<Set<string>>(new Set());
  const [rashOther, setRashOther] = useState("");
  const [freeNote, setFreeNote] = useState("");
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function toggleLocation(loc: string) {
    setRashLocations((prev) => {
      const next = new Set(prev);
      if (next.has(loc)) next.delete(loc); else next.add(loc);
      return next;
    });
  }

  async function handleSend() {
    setSending(true);
    setError(null);
    const client = createClient();
    const { data: caseId, error: caseErr } = await client.rpc("create_infection_handover_case", {
      p_child_id: childId,
    });
    if (caseErr || !caseId) {
      setSending(false);
      setError(`案件の作成に失敗しました: ${caseErr?.message ?? ""}`);
      return;
    }
    const { error: sendErr } = await client.rpc("send_handover_card", {
      p_case_id: caseId,
      p_hives: hives,
      p_rash: rash,
      p_rash_locations: rash === "yes" && rashLocations.size > 0 ? Array.from(rashLocations) : null,
      p_rash_location_other: rashLocations.has("その他") && rashOther.trim() ? rashOther.trim() : null,
      p_free_note: freeNote.trim() || null,
      p_guardian_message: message.trim() || null,
    });
    setSending(false);
    if (sendErr) {
      setError(`送信に失敗しました: ${sendErr.message}`);
      return;
    }
    onSent();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-xl bg-white p-5 shadow-xl">
        <div className="flex items-center justify-between">
          <h3 className="text-base font-bold text-slate-800">引き継ぎカード作成 — {childName}</h3>
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-3 py-1 text-sm text-slate-600 hover:bg-slate-50">
            閉じる
          </button>
        </div>
        <p className="mt-1 text-xs text-slate-500">
          本日の検温・排便などの記録は送信時に自動で添付されます。
        </p>

        <div className="mt-4 space-y-4">
          {/* 蕁麻疹 */}
          <div>
            <p className="mb-1 text-sm font-semibold text-slate-700">園で確認した症状: 蕁麻疹</p>
            <div className="flex gap-2">
              {THREE_STATE.map((s) => (
                <button key={s.value} onClick={() => setHives(s.value)}
                  className={`rounded-lg border px-3 py-1 text-sm ${hives === s.value
                    ? "border-sky-400 bg-sky-50 font-semibold text-sky-700" : "border-slate-300 text-slate-600 hover:bg-slate-50"}`}>
                  {s.label}
                </button>
              ))}
            </div>
          </div>
          {/* 発疹 */}
          <div>
            <p className="mb-1 text-sm font-semibold text-slate-700">園で確認した症状: 発疹</p>
            <div className="flex gap-2">
              {THREE_STATE.map((s) => (
                <button key={s.value} onClick={() => setRash(s.value)}
                  className={`rounded-lg border px-3 py-1 text-sm ${rash === s.value
                    ? "border-sky-400 bg-sky-50 font-semibold text-sky-700" : "border-slate-300 text-slate-600 hover:bg-slate-50"}`}>
                  {s.label}
                </button>
              ))}
            </div>
            {rash === "yes" && (
              <div className="mt-2">
                <p className="mb-1 text-xs text-slate-500">発疹の部位</p>
                <div className="flex flex-wrap gap-1.5">
                  {RASH_LOCATIONS.map((loc) => (
                    <button key={loc} onClick={() => toggleLocation(loc)}
                      className={`rounded-full border px-2.5 py-0.5 text-xs ${rashLocations.has(loc)
                        ? "border-sky-400 bg-sky-50 font-semibold text-sky-700" : "border-slate-300 text-slate-600 hover:bg-slate-50"}`}>
                      {loc}
                    </button>
                  ))}
                </div>
                {rashLocations.has("その他") && (
                  <input type="text" value={rashOther} onChange={(e) => setRashOther(e.target.value)}
                    placeholder="その他の部位"
                    className="mt-2 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none" />
                )}
              </div>
            )}
          </div>
          {/* 自由記述 */}
          <label className="block text-sm text-slate-600">
            自由記述(園で確認した様子・症状の開始時刻・医療機関への補足)
            <textarea value={freeNote} onChange={(e) => setFreeNote(e.target.value)} rows={3}
              className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none" />
          </label>
          {/* 保護者向け文面 */}
          <label className="block text-sm text-slate-600">
            保護者向け文面(空欄=施設の既定文面を使用)
            <textarea value={message} onChange={(e) => setMessage(e.target.value)} rows={2}
              placeholder="空欄の場合は施設の既定文面(受診への協力依頼)が使われます"
              className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none" />
          </label>
        </div>

        {error && <p className="mt-2 text-sm font-medium text-red-500">{error}</p>}
        <div className="mt-4">
          <button onClick={handleSend} disabled={sending}
            className="w-full rounded-lg bg-sky-600 px-4 py-2.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60">
            {sending ? "送信中…" : "保護者へ送信する"}
          </button>
          <p className="mt-2 text-xs text-slate-400">
            送信すると保護者にプッシュ通知が届き、受診結果の入力を依頼します。訂正が必要な場合は再送信してください。
          </p>
        </div>
      </div>
    </div>
  );
}
