"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import Encoding from "encoding-japanese";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { TherapyProvidersModal } from "@/components/TherapyProvidersModal";
import type { TherapyRecordRow } from "@/lib/types";

type Pair = {
  childId: string;
  childName: string;
  providerName: string;
  date: string;
  outAt: string | null;
  returnAt: string | null;
  durationMin: number | null;
  sources: string;
  note: string | null;
  warning: string | null;
};

function jstDate(iso: string): string {
  return new Date(iso).toLocaleDateString("ja-JP", { timeZone: "Asia/Tokyo" });
}
function jstTime(iso: string): string {
  return new Date(iso).toLocaleTimeString("ja-JP", { timeZone: "Asia/Tokyo", hour: "2-digit", minute: "2-digit" });
}

// 外出/戻りを児ごと時系列でペアリング。片方欠落は警告。
function pairEvents(records: TherapyRecordRow[]): Pair[] {
  const byChild = new Map<string, TherapyRecordRow[]>();
  for (const r of records) {
    const arr = byChild.get(r.child_id) ?? [];
    arr.push(r);
    byChild.set(r.child_id, arr);
  }
  const pairs: Pair[] = [];
  for (const [, evs] of byChild) {
    evs.sort((a, b) => a.occurred_at.localeCompare(b.occurred_at));
    let pendingOut: TherapyRecordRow | null = null;
    const name = (e: TherapyRecordRow) => `${e.display_name}${e.honorific_suffix ?? ""}`;
    const flush = (out: TherapyRecordRow) => {
      pairs.push({
        childId: out.child_id, childName: name(out), providerName: out.provider_name,
        date: jstDate(out.occurred_at), outAt: out.occurred_at, returnAt: null, durationMin: null,
        sources: out.source, note: out.correction_note, warning: "戻り未打刻",
      });
    };
    for (const e of evs) {
      if (e.event_type === "out") {
        if (pendingOut) flush(pendingOut);
        pendingOut = e;
      } else {
        // return
        if (pendingOut) {
          const dur = Math.round((new Date(e.occurred_at).getTime() - new Date(pendingOut.occurred_at).getTime()) / 60000);
          pairs.push({
            childId: e.child_id, childName: name(e), providerName: e.provider_name,
            date: jstDate(pendingOut.occurred_at), outAt: pendingOut.occurred_at, returnAt: e.occurred_at,
            durationMin: dur, sources: `${pendingOut.source}/${e.source}`,
            note: [pendingOut.correction_note, e.correction_note].filter(Boolean).join(" / ") || null,
            warning: null,
          });
          pendingOut = null;
        } else {
          pairs.push({
            childId: e.child_id, childName: name(e), providerName: e.provider_name,
            date: jstDate(e.occurred_at), outAt: null, returnAt: e.occurred_at, durationMin: null,
            sources: e.source, note: e.correction_note, warning: "外出未打刻",
          });
        }
      }
    }
    if (pendingOut) flush(pendingOut);
  }
  pairs.sort((a, b) => (a.date + a.childName).localeCompare(b.date + b.childName));
  return pairs;
}

function monthRange(ym: string): { start: string; end: string } {
  const [y, m] = ym.split("-").map(Number);
  const start = `${ym}-01`;
  const end = new Date(y, m, 0).toISOString().slice(0, 10); // 月末
  return { start, end };
}

function ChildcareTherapyRecordsContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();
  const [enabled, setEnabled] = useState(false);
  const [month, setMonth] = useState(new Date().toISOString().slice(0, 7));
  const [childFilter, setChildFilter] = useState("");
  const [records, setRecords] = useState<TherapyRecordRow[]>([]);
  const [reload, setReload] = useState(0);
  const [adding, setAdding] = useState(false);
  const [managingProviders, setManagingProviders] = useState(false);

  useEffect(() => {
    function loadFlag() {
      if (!selectedOffice) return;
      createClient()
        .rpc("is_therapy_outing_enabled_for_office", { p_office_id: selectedOffice })
        .then(({ data }) => setEnabled(Boolean(data)));
    }
    loadFlag();
  }, [selectedOffice]);

  useEffect(() => {
    function load() {
      if (!selectedOffice) return;
      const { start, end } = monthRange(month);
      createClient()
        .rpc("fetch_therapy_records", { p_office_id: selectedOffice, p_start_date: start, p_end_date: end, p_child_id: null })
        .then(({ data }) => setRecords((data ?? []) as TherapyRecordRow[]));
    }
    load();
  }, [selectedOffice, month, reload]);

  const children = useMemo(() => {
    const m = new Map<string, string>();
    for (const r of records) m.set(r.child_id, `${r.display_name}${r.honorific_suffix ?? ""}`);
    return Array.from(m.entries());
  }, [records]);

  const pairs = useMemo(() => {
    const filtered = childFilter ? records.filter((r) => r.child_id === childFilter) : records;
    return pairEvents(filtered);
  }, [records, childFilter]);

  function downloadCsv() {
    const header = ["園児", "事業所", "日付", "外出", "戻り", "所要(分)", "種別", "備考", "警告"];
    const lines = [header.join(",")];
    for (const p of pairs) {
      lines.push([
        p.childName, p.providerName, p.date,
        p.outAt ? jstTime(p.outAt) : "", p.returnAt ? jstTime(p.returnAt) : "",
        p.durationMin != null ? String(p.durationMin) : "", p.sources,
        (p.note ?? "").replace(/,/g, " "), p.warning ?? "",
      ].map((v) => `"${v}"`).join(","));
    }
    const text = lines.join("\r\n");
    const bytes = Encoding.convert(Encoding.stringToCode(text), { to: "SJIS", from: "UNICODE" });
    const blob = new Blob([new Uint8Array(bytes)], { type: "text/csv" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `療育記録_${month}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  async function downloadPdf() {
    const officeName = offices?.find((o) => o.office_id === selectedOffice)?.office_name ?? "";
    const res = await fetch("/api/childcare/therapy-records-pdf", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        officeName,
        month,
        rows: pairs.map((p) => ({
          childName: p.childName, providerName: p.providerName, date: p.date,
          out: p.outAt ? jstTime(p.outAt) : "", ret: p.returnAt ? jstTime(p.returnAt) : "",
          duration: p.durationMin != null ? `${p.durationMin}分` : "", warning: p.warning ?? "",
        })),
      }),
    });
    if (!res.ok) return;
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    window.open(url, "_blank");
  }

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
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">療育外出 記録</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select value={selectedOffice} onChange={(e) => setSelectedOffice(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
              {offices?.map((o) => (
                <option key={o.office_id} value={o.office_id}>{o.office_name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">月</label>
            <input type="month" value={month} onChange={(e) => setMonth(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">園児</label>
            <select value={childFilter} onChange={(e) => setChildFilter(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">全園児</option>
              {children.map(([id, name]) => (
                <option key={id} value={id}>{name}</option>
              ))}
            </select>
          </div>
          <div className="ml-auto flex gap-2">
            {enabled && (
              <>
                <button onClick={() => setManagingProviders(true)} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">
                  事業者マスタ
                </button>
                <button onClick={() => setAdding(true)} className="rounded-lg border border-violet-300 px-4 py-2 text-sm font-semibold text-violet-700 hover:bg-violet-50">
                  手動追加・修正
                </button>
              </>
            )}
            <button onClick={downloadCsv} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">CSV</button>
            <button onClick={downloadPdf} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">PDF</button>
          </div>
        </div>

        {!enabled && <p className="text-sm text-slate-400">この施設では療育外出は無効です。</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-4 py-3">園児</th>
                <th className="px-4 py-3">事業所</th>
                <th className="px-4 py-3">日付</th>
                <th className="px-4 py-3">外出</th>
                <th className="px-4 py-3">戻り</th>
                <th className="px-4 py-3">所要</th>
                <th className="px-4 py-3">種別</th>
                <th className="px-4 py-3">警告</th>
              </tr>
            </thead>
            <tbody>
              {pairs.length === 0 && (
                <tr><td colSpan={8} className="px-4 py-6 text-center text-slate-400">記録がありません</td></tr>
              )}
              {pairs.map((p, i) => (
                <tr key={i} className={`border-b border-slate-100 last:border-0 ${p.warning ? "bg-red-50" : ""}`}>
                  <td className="px-4 py-3 font-medium text-slate-800">{p.childName}</td>
                  <td className="px-4 py-3 text-slate-500">{p.providerName}</td>
                  <td className="px-4 py-3 text-slate-500">{p.date}</td>
                  <td className="px-4 py-3">{p.outAt ? jstTime(p.outAt) : "—"}</td>
                  <td className="px-4 py-3">{p.returnAt ? jstTime(p.returnAt) : "—"}</td>
                  <td className="px-4 py-3">{p.durationMin != null ? `${p.durationMin}分` : "—"}</td>
                  <td className="px-4 py-3 text-xs text-slate-400">{p.sources}</td>
                  <td className="px-4 py-3">
                    {p.warning && <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-600">{p.warning}</span>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>

      {managingProviders && <TherapyProvidersModal onClose={() => setManagingProviders(false)} />}

      {adding && (
        <TherapyManualAddModal
          officeId={selectedOffice}
          childOptions={children}
          onClose={() => setAdding(false)}
          onSaved={() => {
            setAdding(false);
            setReload((t) => t + 1);
          }}
        />
      )}
    </div>
  );
}

function TherapyManualAddModal({
  officeId,
  childOptions,
  onClose,
  onSaved,
}: {
  officeId: string;
  childOptions: [string, string][];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [childId, setChildId] = useState("");
  const [providers, setProviders] = useState<{ id: string; name: string }[]>([]);
  const [providerId, setProviderId] = useState("");
  const [eventType, setEventType] = useState("out");
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [time, setTime] = useState("12:00");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    function load() {
      createClient()
        .from("therapy_providers")
        .select("id, name")
        .eq("is_active", true)
        .order("name")
        .then(({ data }) => setProviders((data ?? []) as { id: string; name: string }[]));
    }
    load();
  }, []);

  async function submit() {
    setError(null);
    if (!childId || !providerId) {
      setError("園児と事業所は必須です");
      return;
    }
    const occurredAt = `${date}T${time}:00+09:00`;
    const { error: e } = await createClient().rpc("record_therapy_event_manual", {
      p_child_id: childId,
      p_provider_id: providerId,
      p_event_type: eventType,
      p_occurred_at: occurredAt,
      p_correction_note: note || null,
    });
    if (e) {
      setError("保存に失敗しました(権限=主任以上をご確認ください)");
      return;
    }
    onSaved();
  }

  void officeId;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">療育記録の手動追加・修正</h3>
        <p className="mt-1 text-xs text-slate-500">上書きせず訂正イベント(staff_manual)として追記されます。</p>
        <div className="mt-4 space-y-3">
          <div>
            <label className="mb-1 block text-xs text-slate-500">園児</label>
            <select value={childId} onChange={(e) => setChildId(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">選択</option>
              {childOptions.map(([id, name]) => (<option key={id} value={id}>{name}</option>))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">事業所</label>
            <select value={providerId} onChange={(e) => setProviderId(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">選択</option>
              {providers.map((p) => (<option key={p.id} value={p.id}>{p.name}</option>))}
            </select>
          </div>
          <div className="flex gap-2">
            <div>
              <label className="mb-1 block text-xs text-slate-500">種別</label>
              <select value={eventType} onChange={(e) => setEventType(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
                <option value="out">外出</option>
                <option value="return">戻り</option>
              </select>
            </div>
            <div>
              <label className="mb-1 block text-xs text-slate-500">日付</label>
              <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
            </div>
            <div>
              <label className="mb-1 block text-xs text-slate-500">時刻</label>
              <input type="time" value={time} onChange={(e) => setTime(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
            </div>
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">備考(訂正理由)</label>
            <input value={note} onChange={(e) => setNote(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
        </div>
        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}
        <div className="mt-6 flex justify-end gap-2">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">キャンセル</button>
          <button onClick={submit} className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600">保存</button>
        </div>
      </div>
    </div>
  );
}

export default function ChildcareTherapyRecordsPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareTherapyRecordsContent />
    </Suspense>
  );
}
