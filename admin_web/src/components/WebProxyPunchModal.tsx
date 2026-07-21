"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { PUNCH_TYPE_LABELS, type PunchType } from "@/lib/types";

type Props = {
  employees: { id: string; name: string }[];
  onClose: () => void;
  onSaved: () => void;
};

/// Web代理打刻(現在時刻のみ)。過去日時の修正は勤怠一覧の「修正」ボタン
/// (correct_daily_attendance)を使う。
export function WebProxyPunchModal({ employees, onClose, onSaved }: Props) {
  const [employeeId, setEmployeeId] = useState(employees[0]?.id ?? "");
  const [punchType, setPunchType] = useState<PunchType>("clock_in");
  const [note, setNote] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!employeeId) {
      setErrorMessage("対象職員を選択してください");
      return;
    }
    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("record_web_proxy_punch", {
      p_employee_id: employeeId,
      p_punch_type: punchType,
      p_note: note.trim() || null,
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
        <h2 className="mb-1 text-base font-bold text-slate-800">Web代理打刻</h2>
        <p className="mb-4 text-sm text-slate-500">
          現在時刻で打刻を記録します。過去日時の修正は一覧の「修正」ボタンを使ってください。
        </p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">対象職員</label>
            <select
              value={employeeId}
              onChange={(e) => setEmployeeId(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {employees.length === 0 && <option value="">(当月の勤怠データがある職員のみ選択できます)</option>}
              {employees.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">打刻種別</label>
            <select
              value={punchType}
              onChange={(e) => setPunchType(e.target.value as PunchType)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {(Object.keys(PUNCH_TYPE_LABELS) as PunchType[]).map((key) => (
                <option key={key} value={key}>
                  {PUNCH_TYPE_LABELS[key]}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">備考(任意)</label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
              placeholder="例: スマホ紛失のため電話連絡のうえ代理打刻"
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
              disabled={isSaving || !employeeId}
              className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
            >
              {isSaving ? "記録中…" : "打刻を記録する"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
