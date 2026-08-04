"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { currentDate } from "@/lib/datetime";
import type { NapSessionRow, NapCheck, NapInterval } from "@/lib/types";
import { NAP_BODY_POSITIONS } from "@/lib/types";

// 午睡区間RPCの例外メッセージを日本語表示へ。
function friendlyNapError(msg: string | undefined): string {
  const m = msg ?? "";
  if (m.includes("not authorized")) return "この操作を行う権限がありません(30分超・過去日は主任以上)";
  if (m.includes("wake before sleep")) return "起床時刻は入眠時刻より後にしてください";
  if (m.includes("not found")) return "対象が見つかりません";
  return "操作に失敗しました";
}

// businessDate(YYYY-MM-DD)+ HH:MM を JST の ISO 文字列に。
function toIso(businessDate: string, time: string): string {
  return `${businessDate}T${time}:00+09:00`;
}
function hmLocal(iso: string): string {
  return new Date(iso).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });
}
function nowHm(): string {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

// 5分床(UTC整列)。
function floor5(d: Date): Date {
  const t = new Date(d);
  t.setUTCSeconds(0, 0);
  t.setUTCMinutes(t.getUTCMinutes() - (t.getUTCMinutes() % 5));
  return t;
}

// 各睡眠区間 [入眠, min(起床, now, 入眠+4h)] の5分スロットを連結(覚醒中の隙間は含めない)。
function slotsFor(row: NapSessionRow): Date[] {
  const now = new Date();
  const ranges: [Date, Date | null][] =
    row.intervals.length > 0
      ? row.intervals.map((i) => [new Date(i.sleep_start_at), i.wake_up_at ? new Date(i.wake_up_at) : null])
      : row.sleep_start_at
        ? [[new Date(row.sleep_start_at), row.wake_up_at ? new Date(row.wake_up_at) : null]]
        : [];
  const slots: Date[] = [];
  for (const [start, wake] of ranges) {
    let first = floor5(start);
    if (first.getTime() < start.getTime()) first = new Date(first.getTime() + 5 * 60000);
    const cap = new Date(start.getTime() + 4 * 60 * 60000);
    const upper = new Date(Math.min(wake ? wake.getTime() : cap.getTime(), now.getTime(), cap.getTime()));
    for (let t = first; t.getTime() <= upper.getTime(); t = new Date(t.getTime() + 5 * 60000)) slots.push(t);
  }
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
  const [intervalEdit, setIntervalEdit] = useState<{ interval: NapInterval } | null>(null);
  const [addTarget, setAddTarget] = useState<{ childId: string; name: string } | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  function showToast(m: string) {
    setToast(m);
    window.setTimeout(() => setToast((c) => (c === m ? null : c)), 3500);
  }

  // 起床(開いている最終区間に起床時刻を書く)
  async function setWake(interval: NapInterval, time: string) {
    const { error } = await createClient().rpc("set_nap_interval", {
      p_interval_id: interval.id,
      p_sleep_start_at: interval.sleep_start_at,
      p_wake_up_at: toIso(businessDate, time),
    });
    if (error) showToast(friendlyNapError(error.message));
    else {
      showToast("起床を記録しました");
      setReloadToken((t) => t + 1);
    }
  }

  // 再入眠(新しい区間を追加)/ 入眠追加
  async function addInterval(childId: string, sleepTime: string, wakeTime?: string) {
    const { error } = await createClient().rpc("add_nap_interval", {
      p_child_id: childId,
      p_sleep_start_at: toIso(businessDate, sleepTime),
      p_wake_up_at: wakeTime ? toIso(businessDate, wakeTime) : null,
    });
    if (error) showToast(friendlyNapError(error.message));
    else {
      showToast("入眠を記録しました");
      setReloadToken((t) => t + 1);
    }
  }

  async function saveInterval(interval: NapInterval, sleepTime: string, wakeTime: string): Promise<boolean> {
    const { error } = await createClient().rpc("set_nap_interval", {
      p_interval_id: interval.id,
      p_sleep_start_at: toIso(businessDate, sleepTime),
      p_wake_up_at: wakeTime ? toIso(businessDate, wakeTime) : null,
    });
    if (error) {
      showToast(friendlyNapError(error.message));
      return false;
    }
    showToast("区間を更新しました");
    setReloadToken((t) => t + 1);
    return true;
  }

  async function deleteInterval(interval: NapInterval) {
    if (!window.confirm("この区間を削除します。よろしいですか?")) return;
    const { error } = await createClient().rpc("delete_nap_interval", { p_interval_id: interval.id });
    if (error) showToast(friendlyNapError(error.message));
    else {
      showToast("区間を削除しました");
      setReloadToken((t) => t + 1);
    }
  }

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

        {selectedClass !== "" && (
          <button
            onClick={() => setAddTarget({ childId: "", name: "" })}
            className="rounded-lg border border-sky-300 bg-sky-50 px-3 py-1.5 text-xs font-semibold text-sky-700 hover:bg-sky-100"
          >
            + 入眠を追加(園児選択)
          </button>
        )}

        {rows.length === 0 && <p className="text-sm text-slate-400">午睡セッションがありません。</p>}

        <div className="space-y-3">
          {rows.map((row) => {
            const slots = slotsFor(row);
            const lastOpen = row.intervals.find((i) => !i.wake_up_at);
            const allWoken = row.intervals.length > 0 && row.intervals.every((i) => i.wake_up_at);
            return (
              <div key={row.session_id} className="rounded-2xl bg-white p-4 shadow-sm">
                <div className="mb-2 flex flex-wrap items-center gap-2 text-sm font-semibold text-slate-800">
                  <span>
                    {row.display_name}
                    {row.honorific_suffix ?? ""} <span className="text-slate-400">/ {row.class_name}</span>
                  </span>
                  {/* 区間(入眠-起床)の一覧・編集・削除 */}
                  {row.intervals.map((iv) => (
                    <span key={iv.id} className="flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-xs font-normal text-slate-600">
                      {hmLocal(iv.sleep_start_at)}-{iv.wake_up_at ? hmLocal(iv.wake_up_at) : "就寝中"}
                      <button onClick={() => setIntervalEdit({ interval: iv })} className="text-sky-600 hover:underline">編集</button>
                      <button onClick={() => deleteInterval(iv)} className="text-red-500 hover:underline">削除</button>
                    </span>
                  ))}
                  {lastOpen && (
                    <button onClick={() => setWake(lastOpen, nowHm())} className="rounded border border-emerald-300 px-2 py-0.5 text-xs text-emerald-700 hover:bg-emerald-50">
                      起床(現在時刻)
                    </button>
                  )}
                  {allWoken && (
                    <button onClick={() => addInterval(row.child_id, nowHm())} className="rounded border border-sky-300 px-2 py-0.5 text-xs text-sky-700 hover:bg-sky-50">
                      再入眠(現在時刻)
                    </button>
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

      {intervalEdit && (
        <NapIntervalEditModal
          interval={intervalEdit.interval}
          onClose={() => setIntervalEdit(null)}
          onSave={async (sleepTime, wakeTime) => {
            const ok = await saveInterval(intervalEdit.interval, sleepTime, wakeTime);
            if (ok) setIntervalEdit(null);
          }}
        />
      )}

      {addTarget && (
        <NapAddIntervalModal
          classId={selectedClass}
          businessDate={businessDate}
          onClose={() => setAddTarget(null)}
          onAdd={async (childId, sleepTime, wakeTime) => {
            await addInterval(childId, sleepTime, wakeTime || undefined);
            setAddTarget(null);
          }}
        />
      )}

      {toast && (
        <div className="fixed bottom-6 left-1/2 z-[60] -translate-x-1/2 rounded-xl bg-slate-800 px-4 py-2 text-sm font-semibold text-white shadow-lg">
          {toast}
        </div>
      )}
    </div>
  );
}

// 区間の時刻編集(入眠・起床)。
function NapIntervalEditModal({
  interval,
  onClose,
  onSave,
}: {
  interval: NapInterval;
  onClose: () => void;
  onSave: (sleepTime: string, wakeTime: string) => void;
}) {
  const [sleep, setSleep] = useState(hmLocal(interval.sleep_start_at));
  const [wake, setWake] = useState(interval.wake_up_at ? hmLocal(interval.wake_up_at) : "");
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">区間の時刻を編集</h3>
        <div className="mt-4 flex gap-3">
          <div>
            <label className="mb-1 block text-xs text-slate-500">入眠</label>
            <input type="time" value={sleep} onChange={(e) => setSleep(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">起床(空=就寝中)</label>
            <input type="time" value={wake} onChange={(e) => setWake(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
        </div>
        <div className="mt-6 flex justify-end gap-2">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">キャンセル</button>
          <button onClick={() => onSave(sleep, wake)} className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600">保存</button>
        </div>
      </div>
    </div>
  );
}

// 入眠を追加(クラスの園児を選んで入眠[+任意で起床])。
function NapAddIntervalModal({
  classId,
  businessDate,
  onClose,
  onAdd,
}: {
  classId: string;
  businessDate: string;
  onClose: () => void;
  onAdd: (childId: string, sleepTime: string, wakeTime: string) => void;
}) {
  const [children, setChildren] = useState<{ child_id: string; display_name: string; honorific_suffix: string | null }[]>([]);
  const [childId, setChildId] = useState("");
  const [sleep, setSleep] = useState(nowHm());
  const [wake, setWake] = useState("");

  useEffect(() => {
    function load() {
      createClient()
        .rpc("fetch_class_children", { p_class_id: classId, p_business_date: businessDate })
        .then(({ data }) => setChildren((data ?? []) as { child_id: string; display_name: string; honorific_suffix: string | null }[]));
    }
    load();
  }, [classId, businessDate]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">入眠を追加</h3>
        <div className="mt-4 space-y-3">
          <div>
            <label className="mb-1 block text-xs text-slate-500">園児</label>
            <select value={childId} onChange={(e) => setChildId(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">選択</option>
              {children.map((c) => (
                <option key={c.child_id} value={c.child_id}>{c.display_name}{c.honorific_suffix ?? ""}</option>
              ))}
            </select>
          </div>
          <div className="flex gap-3">
            <div>
              <label className="mb-1 block text-xs text-slate-500">入眠</label>
              <input type="time" value={sleep} onChange={(e) => setSleep(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
            </div>
            <div>
              <label className="mb-1 block text-xs text-slate-500">起床(任意)</label>
              <input type="time" value={wake} onChange={(e) => setWake(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
            </div>
          </div>
        </div>
        <div className="mt-6 flex justify-end gap-2">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">キャンセル</button>
          <button onClick={() => childId && onAdd(childId, sleep, wake)} className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-50" disabled={!childId}>
            追加
          </button>
        </div>
      </div>
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
