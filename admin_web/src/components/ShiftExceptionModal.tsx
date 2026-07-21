"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { ShiftExceptionRow } from "@/lib/types";

type Props = {
  employeeId: string;
  officeId: string;
  initial: ShiftExceptionRow | null;
  defaultDate: string;
  onClose: () => void;
  onSaved: () => void;
  onDeleted: () => void;
};

export function ShiftExceptionModal({ employeeId, officeId, initial, defaultDate, onClose, onSaved, onDeleted }: Props) {
  const [workDate, setWorkDate] = useState(initial?.work_date ?? defaultDate);
  const [isDayOff, setIsDayOff] = useState(initial?.is_day_off ?? false);
  const [startTime, setStartTime] = useState(initial?.start_time?.slice(0, 5) ?? "09:00");
  const [endTime, setEndTime] = useState(initial?.end_time?.slice(0, 5) ?? "18:00");
  const [breakMinutes, setBreakMinutes] = useState(initial?.break_minutes ?? 60);
  const [note, setNote] = useState(initial?.note ?? "");
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!isDayOff && (!startTime || !endTime)) {
      setErrorMessage("休み以外の場合は開始・終了時刻を入力してください");
      return;
    }
    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("upsert_shift_exception", {
      p_employee_id: employeeId,
      p_work_date: workDate,
      p_is_day_off: isDayOff,
      p_office_id: officeId,
      p_start_time: isDayOff ? null : startTime,
      p_end_time: isDayOff ? null : endTime,
      p_break_minutes: isDayOff ? null : breakMinutes,
      p_note: note.trim() || null,
    });

    setIsSaving(false);
    if (error) {
      setErrorMessage(error.message);
      return;
    }
    onSaved();
  }

  async function handleDelete() {
    setIsDeleting(true);
    setErrorMessage(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("delete_shift_exception", {
      p_employee_id: employeeId,
      p_work_date: workDate,
    });
    setIsDeleting(false);
    if (error) {
      setErrorMessage(error.message);
      return;
    }
    onDeleted();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-1 text-base font-bold text-slate-800">
          {initial ? "イレギュラー例外の編集" : "イレギュラー例外の追加"}
        </h2>
        <p className="mb-4 text-sm text-slate-500">
          特定の日だけ、週次テンプレートと異なる時刻または休みで上書きします。
        </p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">対象日</label>
            <input
              type="date"
              value={workDate}
              disabled={initial !== null}
              onChange={(e) => setWorkDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none disabled:bg-slate-50 disabled:text-slate-400"
            />
          </div>

          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" checked={isDayOff} onChange={(e) => setIsDayOff(e.target.checked)} />
            この日は休み
          </label>

          {!isDayOff && (
            <div className="grid grid-cols-3 gap-3">
              <div>
                <label className="mb-1 block text-sm font-medium text-slate-700">開始時刻</label>
                <input
                  type="time"
                  value={startTime}
                  onChange={(e) => setStartTime(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium text-slate-700">終了時刻</label>
                <input
                  type="time"
                  value={endTime}
                  onChange={(e) => setEndTime(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium text-slate-700">休憩(分)</label>
                <input
                  type="number"
                  min={0}
                  value={breakMinutes}
                  onChange={(e) => setBreakMinutes(Number(e.target.value))}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
            </div>
          )}

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">備考(任意)</label>
            <input
              type="text"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="例: 通院のため午後休"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>

          {errorMessage && <p className="text-sm font-medium text-red-500">{errorMessage}</p>}

          <div className="flex items-center justify-between gap-3 pt-2">
            {initial ? (
              <button
                type="button"
                onClick={handleDelete}
                disabled={isDeleting}
                className="rounded-lg border border-red-200 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
              >
                {isDeleting ? "削除中…" : "この例外を削除"}
              </button>
            ) : (
              <span />
            )}
            <div className="flex gap-3">
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                type="submit"
                disabled={isSaving || !workDate}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isSaving ? "保存中…" : "保存"}
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}
