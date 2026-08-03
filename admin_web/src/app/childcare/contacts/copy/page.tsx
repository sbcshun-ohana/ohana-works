"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { classOrderIndex, compareByClassThenName } from "@/lib/childcareClassSort";
import { currentDate } from "@/lib/datetime";
import type { DailyContactRow } from "@/lib/types";

function ChildcareContactsCopyPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();
  const { classes, selectedClass, setSelectedClass, selectedClassName } = useChildcareClass(selectedOffice);

  const [businessDate, setBusinessDate] = useState(currentDate());
  const [rows, setRows] = useState<DailyContactRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [copiedChildId, setCopiedChildId] = useState<string | null>(null);

  useEffect(() => {
    function loadRows() {
      if (!selectedOffice) return null;
      setIsLoading(true);
      setRowsError(null);
      return createClient();
    }

    const supabase = loadRows();
    if (!supabase) return;
    supabase
      .rpc("fetch_daily_contacts_for_office", {
        p_office_id: selectedOffice,
        p_business_date: businessDate,
      })
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRows(((data ?? []) as DailyContactRow[]).filter((r) => r.status === "approved"));
      });
  }, [selectedOffice, businessDate, reloadToken]);

  async function copyText(row: DailyContactRow) {
    if (!row.contact_id || !row.current_text) return;
    try {
      await navigator.clipboard.writeText(row.current_text);
    } catch {
      // クリップボードAPIが使えない環境ではコピー操作自体は失敗するが、
      // コピー実施の記録(誰がいつ)は別途残す。
    }
    const supabase = createClient();
    const { error } = await supabase.rpc("mark_child_daily_contact_copied", {
      p_contact_id: row.contact_id,
    });
    if (error) {
      setRowsError(error.message);
      return;
    }
    setCopiedChildId(row.child_id);
    setReloadToken((t) => t + 1);
  }

  const classOrder = classOrderIndex(classes);
  const filteredRows = (selectedClassName === null ? rows : rows.filter((r) => r.class_name === selectedClassName))
    .slice()
    .sort((a, b) =>
      compareByClassThenName(classOrder, a.class_name, a.child_display_name, b.class_name, b.child_display_name),
    );

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">保育業務の施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }
  if (offices !== null && offices.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">保育業務機能が有効な施設がありません。</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">承認済み連絡帳のコピー</h2>
        <p className="text-sm text-slate-500">
          承認済みの連絡帳のみ表示します。コピー先(コドモン等)へ貼り付けてください。
        </p>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices?.map((office) => (
                <option key={office.office_id} value={office.office_id}>
                  {office.office_name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">クラス</label>
            <select
              value={selectedClass}
              onChange={(e) => setSelectedClass(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="">全クラス</option>
              {classes.map((c) => (
                <option key={c.class_id} value={c.class_id}>
                  {c.class_name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">対象日</label>
            <input
              type="date"
              value={businessDate}
              onChange={(e) => setBusinessDate(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}
        {!isLoading && filteredRows.length === 0 && (
          <p className="text-sm text-slate-400">承認済みの連絡帳はまだありません</p>
        )}

        <div className="space-y-4">
          {filteredRows.map((row) => (
            <div key={row.child_id} className="rounded-2xl bg-white p-4 shadow-sm">
              <div className="mb-2 flex items-center justify-between">
                <h3 className="text-base font-bold text-slate-800">
                  {row.child_display_name}
                  {row.child_honorific_suffix ?? ""}
                  <span className="ml-2 text-xs font-normal text-slate-400">{row.class_name}</span>
                </h3>
                <button
                  onClick={() => copyText(row)}
                  className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
                >
                  {copiedChildId === row.child_id ? "コピーしました" : "コピーする"}
                </button>
              </div>
              <p className="whitespace-pre-wrap rounded-xl bg-slate-50 p-4 text-base leading-relaxed text-slate-800">
                {row.current_text}
              </p>
              {row.copied_at && (
                <p className="mt-2 text-xs text-slate-400">
                  最終コピー: {new Date(row.copied_at).toLocaleString("ja-JP")}
                </p>
              )}
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}

export default function ChildcareContactsCopyPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareContactsCopyPageContent />
    </Suspense>
  );
}
