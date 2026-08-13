"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { ChildMasterRow } from "@/lib/types";

// 週次標準保育時間(184)。曜日は ISO-8601 = 1:月..7:日(Dart DateTime.weekday と一致)。
// 運営日=月〜土のため、UIは月〜土の6行のみ表示する(DBは1〜7のまま。日曜=7 は読み書き対象外)。
// 取得=担当施設の職員 / 設定・削除=主任以上(manages_childcare)。
// 「その曜日は通わない」= 開始・終了とも空で保存 → delete_child_weekly_schedule。
const WEEKDAYS: { n: number; label: string }[] = [
  { n: 1, label: "月" },
  { n: 2, label: "火" },
  { n: 3, label: "水" },
  { n: 4, label: "木" },
  { n: 5, label: "金" },
  { n: 6, label: "土" },
];

type Props = {
  row: ChildMasterRow;
  isManager: boolean;
  onClose: () => void;
  onSaved: () => void;
};

type DayState = { start: string; end: string };

export function ChildWeeklyScheduleModal({ row, isManager, onClose, onSaved }: Props) {
  const [days, setDays] = useState<Record<number, DayState>>(() =>
    Object.fromEntries(WEEKDAYS.map((w) => [w.n, { start: "", end: "" }])),
  );
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    createClient()
      .rpc("fetch_child_weekly_schedule", { p_child_id: row.child_id })
      .then(({ data, error: e }) => {
        if (!alive) return;
        setLoading(false);
        if (e) {
          setError(e.message);
          return;
        }
        const next: Record<number, DayState> = Object.fromEntries(
          WEEKDAYS.map((w) => [w.n, { start: "", end: "" }]),
        );
        for (const r of (data ?? []) as { weekday: number; scheduled_start_at: string | null; scheduled_end_at: string | null }[]) {
          next[r.weekday] = {
            start: r.scheduled_start_at?.slice(0, 5) ?? "",
            end: r.scheduled_end_at?.slice(0, 5) ?? "",
          };
        }
        setDays(next);
      });
    return () => {
      alive = false;
    };
  }, [row.child_id]);

  function update(weekday: number, field: "start" | "end", value: string) {
    setDays((prev) => ({ ...prev, [weekday]: { ...prev[weekday], [field]: value } }));
  }

  async function handleSave() {
    // 各曜日: 両方入力=set / 両方空=delete(通わない) / 片方のみ=検証エラー。
    for (const w of WEEKDAYS) {
      const d = days[w.n];
      if ((d.start && !d.end) || (!d.start && d.end)) {
        setError(`${w.label}曜: 開始と終了は両方入力するか、両方空にしてください`);
        return;
      }
    }
    setSaving(true);
    setError(null);
    const supabase = createClient();
    try {
      for (const w of WEEKDAYS) {
        const d = days[w.n];
        if (d.start && d.end) {
          const { error: e } = await supabase.rpc("set_child_weekly_schedule", {
            p_child_id: row.child_id,
            p_weekday: w.n,
            p_start: d.start,
            p_end: d.end,
          });
          if (e) throw e;
        } else {
          const { error: e } = await supabase.rpc("delete_child_weekly_schedule", {
            p_child_id: row.child_id,
            p_weekday: w.n,
          });
          if (e) throw e;
        }
      }
    } catch (e) {
      setSaving(false);
      setError(`保存に失敗しました(設定は主任以上のみ): ${(e as { message?: string }).message ?? ""}`);
      return;
    }
    setSaving(false);
    onSaved();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-1 text-base font-bold text-slate-800">週次標準保育時間</h2>
        <p className="mb-4 text-sm text-slate-500">
          {row.display_name}
          {row.honorific_suffix ?? ""}
        </p>

        {loading ? (
          <p className="text-sm text-slate-400">読み込み中…</p>
        ) : (
          <>
            <div className="space-y-2">
              {WEEKDAYS.map((w) => (
                <div key={w.n} className="flex items-center gap-2">
                  <span className="w-6 text-sm font-medium text-slate-600">{w.label}</span>
                  <input
                    type="time"
                    value={days[w.n].start}
                    disabled={!isManager}
                    onChange={(e) => update(w.n, "start", e.target.value)}
                    className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                  />
                  <span className="text-slate-400">〜</span>
                  <input
                    type="time"
                    value={days[w.n].end}
                    disabled={!isManager}
                    onChange={(e) => update(w.n, "end", e.target.value)}
                    className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
                  />
                </div>
              ))}
            </div>
            <p className="mt-2 text-xs text-slate-400">
              両方空にして保存すると「その曜日は通わない」になります。{!isManager && "(設定変更は主任以上のみ)"}
            </p>
          </>
        )}

        {error && <p className="mt-3 text-sm font-medium text-red-500">{error}</p>}

        <div className="mt-6 flex justify-end gap-3">
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            {isManager ? "キャンセル" : "閉じる"}
          </button>
          {isManager && (
            <button
              type="button"
              onClick={handleSave}
              disabled={saving || loading}
              className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
            >
              {saving ? "保存中…" : "保存する"}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
