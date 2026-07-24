"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { parseClassAge } from "@/components/CreateChildModal";
import type { ChildcareClass, ChildMasterRow } from "@/lib/types";

type Props = {
  classes: ChildcareClass[];
  rows: ChildMasterRow[];
  onClose: () => void;
  onSaved: () => void;
};

type PromoteResult = { child_id: string; success: boolean; message: string };

export function BulkPromoteChildrenModal({ classes, rows, onClose, onSaved }: Props) {
  const [sourceClassId, setSourceClassId] = useState("");
  const [destinationClassId, setDestinationClassId] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [checkedChildIds, setCheckedChildIds] = useState<Set<string>>(new Set());
  const [isConfirming, setIsConfirming] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [results, setResults] = useState<PromoteResult[] | null>(null);

  const sourceChildren = rows.filter((r) => r.class_id === sourceClassId);

  function handleSourceClassChange(classId: string) {
    setSourceClassId(classId);
    setCheckedChildIds(new Set(rows.filter((r) => r.class_id === classId).map((c) => c.child_id)));

    // 通常の進級は「現在のクラスの1つ上の年齢区分」への移動なので、該当クラスがあれば提案する
    // (無ければ提案せず、手動選択に委ねる)。
    const sourceClass = classes.find((c) => c.class_id === classId);
    const sourceAge = sourceClass ? parseClassAge(sourceClass.age_group) : null;
    if (sourceAge != null) {
      const suggested = classes.find((c) => parseClassAge(c.age_group) === sourceAge + 1);
      setDestinationClassId(suggested ? suggested.class_id : "");
    } else {
      setDestinationClassId("");
    }
  }

  function toggleChild(childId: string) {
    setCheckedChildIds((prev) => {
      const next = new Set(prev);
      if (next.has(childId)) next.delete(childId);
      else next.add(childId);
      return next;
    });
  }

  const destinationClass = classes.find((c) => c.class_id === destinationClassId);
  const checkedChildren = sourceChildren.filter((c) => checkedChildIds.has(c.child_id));

  function handleRequestConfirm(event: React.FormEvent) {
    event.preventDefault();
    setErrorMessage(null);
    if (!destinationClassId || !startDate) {
      setErrorMessage("進級先クラスと開始日を入力してください");
      return;
    }
    if (endDate && endDate < startDate) {
      setErrorMessage("終了日は開始日以降にしてください");
      return;
    }
    if (checkedChildren.length === 0) {
      setErrorMessage("進級させる園児を1名以上選択してください");
      return;
    }
    setIsConfirming(true);
  }

  async function handleConfirm() {
    setIsSaving(true);
    setErrorMessage(null);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("bulk_promote_children", {
      p_child_ids: checkedChildren.map((c) => c.child_id),
      p_destination_class_id: destinationClassId,
      p_start_date: startDate,
      p_end_date: endDate || null,
    });
    setIsSaving(false);
    if (error) {
      setErrorMessage(error.message);
      setIsConfirming(false);
      return;
    }
    setResults((data ?? []) as PromoteResult[]);
  }

  function childLabel(childId: string) {
    const row = rows.find((r) => r.child_id === childId);
    return row ? `${row.display_name}${row.honorific_suffix ?? ""}` : childId;
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="max-h-[85vh] w-full max-w-2xl overflow-y-auto rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-4 text-base font-bold text-slate-800">翌年度への進級一括登録</h2>

        {results ? (
          <div className="space-y-4">
            <ul className="space-y-2">
              {results.map((r) => (
                <li
                  key={r.child_id}
                  className={`rounded-lg px-3 py-2 text-sm ${
                    r.success ? "bg-emerald-50 text-emerald-700" : "bg-red-50 text-red-600"
                  }`}
                >
                  {childLabel(r.child_id)}: {r.success ? "登録しました" : `スキップ(${r.message})`}
                </li>
              ))}
            </ul>
            <div className="flex justify-end">
              <button
                onClick={onSaved}
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600"
              >
                閉じる
              </button>
            </div>
          </div>
        ) : isConfirming ? (
          <div className="space-y-4">
            <p className="text-sm text-slate-700">
              {checkedChildren.length}名を{destinationClass?.class_name}
              ({startDate}〜{endDate || "無期限"})に登録します。よろしいですか?
            </p>
            <ul className="max-h-40 list-disc space-y-1 overflow-y-auto pl-5 text-sm text-slate-600">
              {checkedChildren.map((c) => (
                <li key={c.child_id}>
                  {c.display_name}
                  {c.honorific_suffix ?? ""}
                </li>
              ))}
            </ul>
            {errorMessage && <p className="text-sm font-medium text-red-500">{errorMessage}</p>}
            <div className="flex justify-end gap-3">
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
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
              >
                {isSaving ? "登録中…" : "登録する"}
              </button>
            </div>
          </div>
        ) : (
          <form onSubmit={handleRequestConfirm} className="space-y-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-slate-700">現在のクラス</label>
              <select
                value={sourceClassId}
                onChange={(e) => handleSourceClassChange(e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              >
                <option value="">選択してください</option>
                {classes.map((c) => (
                  <option key={c.class_id} value={c.class_id}>
                    {c.class_name}
                  </option>
                ))}
              </select>
            </div>

            {sourceClassId && (
              <div>
                <label className="mb-1 block text-sm font-medium text-slate-700">
                  進級対象の園児({checkedChildren.length}/{sourceChildren.length}名選択中)
                </label>
                {sourceChildren.length === 0 ? (
                  <p className="text-sm text-slate-400">このクラスに在籍園児がいません</p>
                ) : (
                  <ul className="max-h-48 space-y-1 overflow-y-auto rounded-lg border border-slate-200 p-3">
                    {sourceChildren.map((c) => (
                      <li key={c.child_id} className="flex items-center gap-2 text-sm">
                        <input
                          type="checkbox"
                          checked={checkedChildIds.has(c.child_id)}
                          onChange={() => toggleChild(c.child_id)}
                        />
                        <span>
                          {c.display_name}
                          {c.honorific_suffix ?? ""}
                        </span>
                        <span className="text-xs text-slate-400">({c.enrollment_status})</span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}

            <div>
              <label className="mb-1 block text-sm font-medium text-slate-700">進級先クラス</label>
              <select
                value={destinationClassId}
                onChange={(e) => setDestinationClassId(e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              >
                <option value="">選択してください</option>
                {classes.map((c) => (
                  <option key={c.class_id} value={c.class_id}>
                    {c.class_name}
                  </option>
                ))}
              </select>
            </div>

            <div className="flex gap-3">
              <div className="flex-1">
                <label className="mb-1 block text-sm font-medium text-slate-700">開始日</label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
              <div className="flex-1">
                <label className="mb-1 block text-sm font-medium text-slate-700">終了日(任意)</label>
                <input
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
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
                className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600"
              >
                確認画面へ
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
