"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { fromDatetimeLocalValue, toDatetimeLocalValue } from "@/lib/datetime";
import { CORRECTABLE_FIELDS, type AttendanceRow, type CorrectableFieldKey } from "@/lib/types";

type Props = {
  row: AttendanceRow;
  onClose: () => void;
  onSaved: () => void;
};

export function CorrectAttendanceModal({ row, onClose, onSaved }: Props) {
  const [field, setField] = useState<CorrectableFieldKey>("actual_clock_in_at");
  const fieldDef = CORRECTABLE_FIELDS.find((f) => f.key === field)!;

  const [timestampValue, setTimestampValue] = useState(
    toDatetimeLocalValue(row[field] as string | null),
  );
  const [intValue, setIntValue] = useState(String(row.approved_break_minutes ?? ""));
  const [reason, setReason] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  function handleFieldChange(nextField: CorrectableFieldKey) {
    setField(nextField);
    const nextDef = CORRECTABLE_FIELDS.find((f) => f.key === nextField)!;
    if (nextDef.kind === "timestamp") {
      setTimestampValue(toDatetimeLocalValue(row[nextField] as string | null));
    } else {
      setIntValue(String(row.approved_break_minutes ?? ""));
    }
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!reason.trim()) {
      setErrorMessage("修正理由を入力してください");
      return;
    }
    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("correct_daily_attendance", {
      p_employee_id: row.employee_id,
      p_work_date: row.work_date,
      p_field: field,
      p_reason: reason.trim(),
      p_new_timestamp_value:
        fieldDef.kind === "timestamp" ? fromDatetimeLocalValue(timestampValue) : null,
      p_new_int_value: fieldDef.kind === "int" ? (intValue === "" ? null : Number(intValue)) : null,
    });

    setIsSaving(false);
    if (error) {
      setErrorMessage(error.message);
      return;
    }
    onSaved();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-1 text-base font-bold text-slate-800">勤怠修正</h2>
        <p className="mb-4 text-sm text-slate-500">
          {row.employee_name} / {row.work_date}
        </p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">修正項目</label>
            <select
              value={field}
              onChange={(e) => handleFieldChange(e.target.value as CorrectableFieldKey)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {CORRECTABLE_FIELDS.map((f) => (
                <option key={f.key} value={f.key}>
                  {f.label}
                </option>
              ))}
            </select>
          </div>

          {fieldDef.kind === "timestamp" ? (
            <div>
              <label className="mb-1 block text-sm font-medium text-slate-700">新しい時刻</label>
              <input
                type="datetime-local"
                value={timestampValue}
                onChange={(e) => setTimestampValue(e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
              <p className="mt-1 text-xs text-slate-400">空欄のまま保存すると未設定(null)になります</p>
            </div>
          ) : (
            <div>
              <label className="mb-1 block text-sm font-medium text-slate-700">新しい休憩時間(分)</label>
              <input
                type="number"
                min={0}
                value={intValue}
                onChange={(e) => setIntValue(e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
          )}

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">修正理由(必須)</label>
            <textarea
              required
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              placeholder="例: 6/12退勤打刻漏れ。主任確認済み"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>

          {errorMessage && <p className="text-sm font-medium text-red-500">{errorMessage}</p>}

          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
            >
              キャンセル
            </button>
            <button
              type="submit"
              disabled={isSaving}
              className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
            >
              {isSaving ? "保存中…" : "保存する"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
