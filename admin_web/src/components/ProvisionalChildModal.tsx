"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Props = {
  officeId: string;
  onClose: () => void;
  onSaved: () => void;
};

/// 仮登録(入園予定)モーダル。園児名だけで作成できる(M6 Phase1)。
/// クラス在籍を作らないため、登園ボードや在園児一覧には表示されない。
/// 基本情報(生年月日・性別等)は入園フォーム(Phase2)または正式登録時に補完する。
export function ProvisionalChildModal({ officeId, onClose, onSaved }: Props) {
  const [fullName, setFullName] = useState("");
  const [nameKana, setNameKana] = useState("");
  const [plannedStartDate, setPlannedStartDate] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!fullName.trim()) {
      setErrorMessage("園児名を入力してください");
      return;
    }
    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("create_provisional_child", {
      p_office_id: officeId,
      p_full_name: fullName.trim(),
      p_name_kana: nameKana.trim() || null,
      p_planned_start_date: plannedStartDate || null,
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
        <h2 className="mb-1 text-base font-bold text-slate-800">仮登録(入園予定)</h2>
        <p className="mb-4 text-xs text-slate-400">
          園児名だけで登録できます。登園ボードや在園児一覧には表示されません。
          保護者への招待QRの発行は、登録後に入園予定の一覧から行えます。
        </p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">園児名</label>
            <input
              required
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              placeholder="例: 山田 太郎"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">ふりがな(任意)</label>
            <input
              value={nameKana}
              onChange={(e) => setNameKana(e.target.value)}
              placeholder="例: やまだたろう"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">入園予定日(任意)</label>
            <input
              type="date"
              value={plannedStartDate}
              onChange={(e) => setPlannedStartDate(e.target.value)}
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
              {isSaving ? "登録中…" : "仮登録する"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
