"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { ChildMasterRow } from "@/lib/types";

type Props = {
  row: ChildMasterRow;
  onClose: () => void;
  onSaved: () => void;
};

export function ChildRequiredPeriodModal({ row, onClose, onSaved }: Props) {
  const [startDate, setStartDate] = useState(row.family_daily_report_required_from ?? "");
  const [endDate, setEndDate] = useState(row.family_daily_report_required_until ?? "");
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (endDate && !startDate) {
      setErrorMessage("終了日を指定する場合は開始日も指定してください");
      return;
    }
    if (startDate && endDate && endDate < startDate) {
      setErrorMessage("終了日は開始日以降にしてください");
      return;
    }
    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("set_family_daily_report_required_period", {
      p_child_id: row.child_id,
      p_start_date: startDate || null,
      p_end_date: endDate || null,
    });

    setIsSaving(false);
    if (error) {
      setErrorMessage(error.message);
      return;
    }
    onSaved();
  }

  async function handleClear() {
    setIsSaving(true);
    setErrorMessage(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("set_family_daily_report_required_period", {
      p_child_id: row.child_id,
      p_start_date: null,
      p_end_date: null,
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
        <h2 className="mb-1 text-base font-bold text-slate-800">連絡帳提出必須の適用期間</h2>
        <p className="mb-4 text-sm text-slate-500">
          {row.display_name}
          {row.honorific_suffix ?? ""}
        </p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">開始日</label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">終了日(任意)</label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">空欄のままにすると無期限になります</p>
          </div>

          {errorMessage && <p className="text-sm font-medium text-red-500">{errorMessage}</p>}

          <div className="flex justify-between gap-3 pt-2">
            <button
              type="button"
              onClick={handleClear}
              disabled={isSaving}
              className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-40"
            >
              設定を解除
            </button>
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
                disabled={isSaving}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isSaving ? "保存中…" : "保存する"}
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}
