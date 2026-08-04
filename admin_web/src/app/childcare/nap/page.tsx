"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { currentDate } from "@/lib/datetime";
import type { NapSessionRow, NapCheck } from "@/lib/types";
import { NAP_BODY_POSITIONS } from "@/lib/types";

// 5分床(UTC整列)。
function floor5(d: Date): Date {
  const t = new Date(d);
  t.setUTCSeconds(0, 0);
  t.setUTCMinutes(t.getUTCMinutes() - (t.getUTCMinutes() % 5));
  return t;
}

// 入眠〜min(起床, now, 入眠+4h) の5分スロット(切り上げ初回)。過去日で起床未登録でもグリッドが膨張しない。
function slotsFor(row: NapSessionRow): Date[] {
  if (!row.sleep_start_at) return [];
  const start = new Date(row.sleep_start_at);
  let first = floor5(start);
  if (first.getTime() < start.getTime()) first = new Date(first.getTime() + 5 * 60000);
  const now = new Date();
  const cap = new Date(start.getTime() + 4 * 60 * 60000);
  const wake = row.wake_up_at ? new Date(row.wake_up_at) : null;
  const upper = new Date(Math.min(wake ? wake.getTime() : cap.getTime(), now.getTime(), cap.getTime()));
  const slots: Date[] = [];
  for (let t = first; t.getTime() <= upper.getTime(); t = new Date(t.getTime() + 5 * 60000)) slots.push(t);
  return slots;
}

function hm(d: Date): string {
  return d.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });
}

// 過去スロットの未チェック判定(Date.now はレンダー本体で呼べないためモジュール関数に隔離)。
function isPastMissing(check: NapCheck | null, slot: Date): boolean {
  return !check && slot.getTime() < Date.now();
}

function ChildcareNapPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();
  const { classes, selectedClass, setSelectedClass } = useChildcareClass(selectedOffice);
  const [businessDate, setBusinessDate] = useState(currentDate());
  const [rows, setRows] = useState<NapSessionRow[]>([]);
  const [reloadToken, setReloadToken] = useState(0);
  const [editing, setEditing] = useState<{ row: NapSessionRow; slot: Date; existing: NapCheck | null } | null>(null);

  useEffect(() => {
    function load() {
      if (!selectedOffice) return;
      createClient()
        .rpc("fetch_nap_board", {
          p_office_id: selectedOffice,
          p_class_id: selectedClass === "" ? null : selectedClass,
          p_session_date: businessDate,
        })
        .then(({ data }) => setRows((data ?? []) as NapSessionRow[]));
    }
    load();
  }, [selectedOffice, selectedClass, businessDate, reloadToken]);

  async function saveCheck(
    row: NapSessionRow,
    slot: Date,
    body: string,
    breathing: boolean,
    complexion: boolean,
    bedding: boolean,
  ): Promise<boolean> {
    const { error } = await createClient().rpc("record_nap_check", {
      p_session_id: row.session_id,
      p_slot_at: slot.toISOString(),
      p_body_position: body,
      p_breathing: breathing,
      p_complexion: complexion,
      p_bedding: bedding,
    });
    if (error) return false;
    setReloadToken((t) => t + 1);
    return true;
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
        <h2 className="text-lg font-bold text-slate-800">午睡チェック(閲覧・修正)</h2>
        <p className="text-xs text-slate-500">
          過去日・30分超の修正は主任以上のみ可能です(修正は監査に残ります)。当日30分以内は一般職員も記入できます。
        </p>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices?.map((o) => (
                <option key={o.office_id} value={o.office_id}>
                  {o.office_name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">クラス</label>
            <select
              value={selectedClass}
              onChange={(e) => setSelectedClass(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="">全クラス</option>
              {classes.map((c) => (
                <option key={c.class_id} value={c.class_id}>
                  {c.class_name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">対象日</label>
            <input
              type="date"
              value={businessDate}
              onChange={(e) => setBusinessDate(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
        </div>

        {rows.length === 0 && <p className="text-sm text-slate-400">午睡セッションがありません。</p>}

        <div className="space-y-3">
          {rows.map((row) => {
            const slots = slotsFor(row);
            return (
              <div key={row.session_id} className="rounded-2xl bg-white p-4 shadow-sm">
                <div className="mb-2 text-sm font-semibold text-slate-800">
                  {row.display_name}
                  {row.honorific_suffix ?? ""} <span className="text-slate-400">/ {row.class_name}</span>
                  {row.sleep_start_at && (
                    <span className="ml-2 text-xs text-slate-500">入眠 {hm(new Date(row.sleep_start_at))}</span>
                  )}
                  {row.wake_up_at && (
                    <span className="ml-2 text-xs text-slate-500">起床 {hm(new Date(row.wake_up_at))}</span>
                  )}
                </div>
                <div className="flex gap-2 overflow-x-auto pb-1">
                  {slots.map((slot) => {
                    const check = row.checks.find((c) => new Date(c.slot_at).getTime() === slot.getTime()) ?? null;
                    const pastMissing = isPastMissing(check, slot);
                    return (
                      <button
                        key={slot.toISOString()}
                        onClick={() => setEditing({ row, slot, existing: check })}
                        className={`flex min-w-[56px] flex-col items-center rounded-lg px-2 py-1 text-xs ${
                          check
                            ? "bg-emerald-50 text-emerald-700"
                            : pastMissing
                              ? "bg-red-50 text-red-600"
                              : "bg-slate-50 text-slate-400"
                        }`}
                      >
                        <span className="text-[10px] text-slate-400">{hm(slot)}</span>
                        <span className="font-semibold">
                          {check ? (NAP_BODY_POSITIONS[check.body_position] ?? check.body_position) : pastMissing ? "未" : "—"}
                        </span>
                      </button>
                    );
                  })}
                  {slots.length === 0 && <span className="text-xs text-slate-400">入眠未登録</span>}
                </div>
              </div>
            );
          })}
        </div>
      </main>

      {editing && (
        <NapCheckModal
          childName={`${editing.row.display_name}${editing.row.honorific_suffix ?? ""}`}
          slot={editing.slot}
          existing={editing.existing}
          onClose={() => setEditing(null)}
          onSave={async (body, breathing, complexion, bedding) => {
            const ok = await saveCheck(editing.row, editing.slot, body, breathing, complexion, bedding);
            if (ok) setEditing(null);
            return ok;
          }}
        />
      )}
    </div>
  );
}

function NapCheckModal({
  childName,
  slot,
  existing,
  onClose,
  onSave,
}: {
  childName: string;
  slot: Date;
  existing: NapCheck | null;
  onClose: () => void;
  onSave: (body: string, breathing: boolean, complexion: boolean, bedding: boolean) => Promise<boolean>;
}) {
  const [body, setBody] = useState(existing?.body_position ?? "supine");
  const [breathing, setBreathing] = useState(existing?.breathing ?? true);
  const [complexion, setComplexion] = useState(existing?.complexion ?? true);
  const [bedding, setBedding] = useState(existing?.bedding ?? true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">
          {childName} {hm(slot)}
        </h3>
        <div className="mt-4">
          <label className="mb-1 block text-xs font-medium text-slate-500">身体の向き</label>
          <div className="flex flex-wrap gap-2">
            {Object.entries(NAP_BODY_POSITIONS).map(([k, v]) => (
              <button
                key={k}
                onClick={() => setBody(k)}
                className={`rounded-lg border px-3 py-1 text-sm ${
                  body === k ? "border-sky-400 bg-sky-50 text-sky-700" : "border-slate-300 text-slate-600"
                }`}
              >
                {v}
              </button>
            ))}
          </div>
        </div>
        <label className="mt-3 flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={breathing} onChange={(e) => setBreathing(e.target.checked)} /> 呼吸を確認
        </label>
        <label className="mt-2 flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={complexion} onChange={(e) => setComplexion(e.target.checked)} /> 顔色を確認
        </label>
        <label className="mt-2 flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={bedding} onChange={(e) => setBedding(e.target.checked)} /> 寝具の状態を確認
        </label>
        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}
        <div className="mt-6 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50"
          >
            キャンセル
          </button>
          <button
            onClick={async () => {
              setSaving(true);
              setError(null);
              const ok = await onSave(body, breathing, complexion, bedding);
              if (!ok) {
                setSaving(false);
                setError("保存に失敗しました(過去日・30分超は主任以上のみ)");
              }
            }}
            disabled={saving}
            className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-50"
          >
            {saving ? "保存中…" : "保存"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function ChildcareNapPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareNapPageContent />
    </Suspense>
  );
}
