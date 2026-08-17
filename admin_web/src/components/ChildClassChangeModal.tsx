"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { estimateCohortAge, parseClassAge } from "@/components/CreateChildModal";
import { currentDate } from "@/lib/datetime";
import type { ChildcareClass, ChildMasterRow } from "@/lib/types";

type Props = {
  row: ChildMasterRow;
  classes: ChildcareClass[];
  onClose: () => void;
  onSaved: () => void;
};

type HistoryRow = {
  class_id: string;
  class_name: string;
  effective_start_date: string;
  effective_end_date: string | null;
};

/// 個別クラス変更(223)。年度途中の転クラス・誤登録修正用。
/// 変更日の前日で旧クラス在籍を閉じて新クラス在籍を開始する(履歴は削除しない=下の履歴一覧に残る)。
/// 年度切替は従来どおり「翌年度への進級一括登録」を使う。
export function ChildClassChangeModal({ row, classes, onClose, onSaved }: Props) {
  const [history, setHistory] = useState<HistoryRow[]>([]);
  const [classId, setClassId] = useState("");
  const [effectiveDate, setEffectiveDate] = useState(currentDate());
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_child_class_history", { p_child_id: row.child_id }).then(({ data, error }) => {
      if (!error) setHistory((data ?? []) as HistoryRow[]);
    });
  }, [row.child_id]);

  const selectedClass = classes.find((c) => c.class_id === classId);
  const classAge = selectedClass ? parseClassAge(selectedClass.age_group) : null;
  const cohortAge = row.birth_date ? estimateCohortAge(row.birth_date, effectiveDate) : null;
  const showAgeMismatchWarning = classAge != null && cohortAge != null && Math.abs(classAge - cohortAge) >= 2;
  const suggestedClass =
    cohortAge != null ? classes.find((c) => parseClassAge(c.age_group) === cohortAge) : undefined;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!classId || !effectiveDate) {
      setErrorMessage("クラスと変更日を選択してください");
      return;
    }
    if (!window.confirm(`${row.display_name}${row.honorific_suffix ?? ""}のクラスを ${selectedClass?.class_name} へ変更しますか?(${effectiveDate}付・現在の在籍は履歴として残ります)`)) return;
    setIsSaving(true);
    setErrorMessage(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("change_child_class", {
      p_child_id: row.child_id,
      p_class_id: classId,
      p_effective_date: effectiveDate,
    });
    setIsSaving(false);
    if (error) {
      setErrorMessage(
        error.message.includes("already in this class")
          ? "変更日時点で既にこのクラスに在籍しています"
          : error.message,
      );
      return;
    }
    onSaved();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="max-h-[85vh] w-full max-w-md overflow-y-auto rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-1 text-base font-bold text-slate-800">クラス変更</h2>
        <p className="mb-4 text-sm text-slate-600">
          {row.display_name}
          {row.honorific_suffix ?? ""}(現在: {row.class_name ?? "クラス未所属"})
        </p>

        <div className="mb-4 rounded-xl border border-slate-200 p-3">
          <p className="mb-2 text-xs font-bold text-slate-500">クラス在籍履歴</p>
          {history.length === 0 && <p className="text-xs text-slate-400">履歴はありません</p>}
          {history.map((h, i) => (
            <div key={i} className="flex justify-between py-0.5 text-sm">
              <span className={h.effective_end_date ? "text-slate-500" : "font-semibold text-slate-800"}>
                {h.class_name}
              </span>
              <span className="text-xs text-slate-400">
                {h.effective_start_date} 〜 {h.effective_end_date ?? "現在"}
              </span>
            </div>
          ))}
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">変更後のクラス</label>
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
            {suggestedClass && !classId && (
              <p className="mt-1 text-xs text-slate-400">
                生年月日からの提案: {suggestedClass.class_name}({cohortAge}歳児)
              </p>
            )}
            {showAgeMismatchWarning && (
              <p className="mt-1 text-xs font-medium text-amber-600">
                生年月日とクラスの年齢区分が大きく異なります。ご確認ください。
              </p>
            )}
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">変更日</label>
            <input
              required
              type="date"
              value={effectiveDate}
              onChange={(e) => setEffectiveDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">
              変更日の前日までは現在のクラスの在籍として履歴に残ります。年度の進級は「翌年度への進級一括登録」をご利用ください。
            </p>
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
              {isSaving ? "変更中…" : "クラスを変更する"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
