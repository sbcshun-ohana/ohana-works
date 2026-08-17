"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { currentDate } from "@/lib/datetime";
import type { ChildcareClass, ChildMasterRow } from "@/lib/types";

type Props = {
  row: ChildMasterRow;
  classes: ChildcareClass[];
  onClose: () => void;
  onSaved: () => void;
};

/// 正式入園(218 promote_provisional_child)。仮登録児にクラスと入園日を設定して在籍中にする。
/// 以後は登園ボード・在園児一覧に表示される。
export function PromoteProvisionalChildModal({ row, classes, onClose, onSaved }: Props) {
  const [classId, setClassId] = useState("");
  const [startDate, setStartDate] = useState(row.enrollment_date ?? currentDate());
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const missingBasics = !row.birth_date || !row.gender;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!classId || !startDate) {
      setErrorMessage("クラスと入園日を選択してください");
      return;
    }
    setIsSaving(true);
    setErrorMessage(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("promote_provisional_child", {
      p_child_id: row.child_id,
      p_class_id: classId,
      p_start_date: startDate,
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
        <h2 className="mb-1 text-base font-bold text-slate-800">正式入園</h2>
        <p className="mb-4 text-sm text-slate-600">{row.full_name}</p>
        {missingBasics && (
          <p className="mb-4 rounded-lg bg-amber-50 p-3 text-xs text-amber-800">
            生年月日・性別が未登録です。入園フォームの承認または園側での登録が済んでいるかご確認ください(このまま正式入園も可能です)。
          </p>
        )}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">所属クラス</label>
            <select
              required
              value={classId}
              onChange={(e) => setClassId(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="">選択してください</option>
              {classes.map((c) => (
                <option key={c.class_id} value={c.class_id}>
                  {c.class_name}({c.age_group})
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">入園日(在籍開始日)</label>
            <input
              required
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">正式入園すると登園ボード・在園児一覧に表示されるようになります。</p>
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
              {isSaving ? "処理中…" : "正式入園にする"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
