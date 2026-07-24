"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { currentDate } from "@/lib/datetime";
import type { ChildMasterRow } from "@/lib/types";

type Props = {
  row: ChildMasterRow;
  onClose: () => void;
  onSaved: () => void;
};

export function WithdrawChildModal({ row, onClose, onSaved }: Props) {
  const [withdrawalDate, setWithdrawalDate] = useState(currentDate());
  const [isConfirming, setIsConfirming] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleConfirm() {
    setIsSaving(true);
    setErrorMessage(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("withdraw_child", {
      p_child_id: row.child_id,
      p_withdrawal_date: withdrawalDate,
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
        <h2 className="mb-1 text-base font-bold text-slate-800">退園処理</h2>
        <p className="mb-4 text-sm text-slate-500">
          {row.display_name}
          {row.honorific_suffix ?? ""}
        </p>

        {!isConfirming ? (
          <div className="space-y-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-slate-700">退園日</label>
              <input
                type="date"
                value={withdrawalDate}
                onChange={(e) => setWithdrawalDate(e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
            <div className="flex justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={onClose}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                type="button"
                onClick={() => setIsConfirming(true)}
                disabled={!withdrawalDate}
                className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white hover:bg-red-600 disabled:opacity-60"
              >
                次へ
              </button>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
            <p className="rounded-lg bg-red-50 p-3 text-sm text-red-700">
              {row.display_name}
              {row.honorific_suffix ?? ""}を{withdrawalDate}付で退園処理します。この操作は元に戻せません。よろしいですか?
            </p>
            {errorMessage && <p className="text-sm font-medium text-red-500">{errorMessage}</p>}
            <div className="flex justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={() => setIsConfirming(false)}
                disabled={isSaving}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                戻る
              </button>
              <button
                type="button"
                onClick={handleConfirm}
                disabled={isSaving}
                className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white hover:bg-red-600 disabled:opacity-60"
              >
                {isSaving ? "処理中…" : "退園処理を実行する"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
