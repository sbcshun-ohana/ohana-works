"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { currentDate } from "@/lib/datetime";
import type { ClassChild } from "@/lib/types";

function ChildcareAttendancePageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();
  // クラス必須のページ。?class= をタブ切替で引き継ぎつつ、無ければ先頭クラス既定。
  const { classes, selectedClass, setSelectedClass } = useChildcareClass(selectedOffice, { defaultToFirst: true });

  const [businessDate, setBusinessDate] = useState(currentDate());
  const [children, setChildren] = useState<ClassChild[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [savingChildId, setSavingChildId] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    function loadChildren() {
      if (!selectedClass) {
        setChildren([]);
        return;
      }
      setIsLoading(true);
      setRowsError(null);
      const supabase = createClient();
      return supabase.rpc("fetch_class_children", {
        p_class_id: selectedClass,
        p_business_date: businessDate,
      });
    }

    loadChildren()?.then(({ data, error }) => {
      setIsLoading(false);
      if (error) {
        setRowsError(error.message);
        return;
      }
      setChildren((data ?? []) as ClassChild[]);
    });
  }, [selectedClass, businessDate, reloadToken]);

  async function toggleAbsence(child: ClassChild) {
    setSavingChildId(child.child_id);
    const supabase = createClient();
    const nextIsAbsent = !child.is_absent;
    const reason = nextIsAbsent ? window.prompt("欠席理由を入力してください(任意)") ?? "" : null;
    const { error } = await supabase.rpc("set_child_daily_attendance", {
      p_child_id: child.child_id,
      p_business_date: businessDate,
      p_is_absent: nextIsAbsent,
      p_absence_reason: reason,
    });
    setSavingChildId(null);
    if (error) {
      setRowsError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

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
        <h2 className="text-lg font-bold text-slate-800">当日の欠席選択</h2>

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

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-4 py-3">園児</th>
                <th className="px-4 py-3">在籍状況</th>
                <th className="px-4 py-3">出欠</th>
                <th className="px-4 py-3">欠席理由</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr>
                  <td colSpan={5} className="px-4 py-6 text-center text-slate-400">
                    読み込み中…
                  </td>
                </tr>
              )}
              {!isLoading && children.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-4 py-6 text-center text-slate-400">
                    在籍園児がいません
                  </td>
                </tr>
              )}
              {!isLoading &&
                children.map((child) => (
                  <tr
                    key={child.child_id}
                    className="border-b border-slate-100 last:border-0 hover:bg-slate-50"
                  >
                    <td className="px-4 py-3 font-medium text-slate-800">
                      {child.display_name}
                      {child.honorific_suffix ?? ""}
                    </td>
                    <td className="px-4 py-3 text-slate-500">{child.enrollment_status}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                          child.is_absent ? "bg-red-50 text-red-600" : "bg-emerald-50 text-emerald-700"
                        }`}
                      >
                        {child.is_absent ? "欠席" : "出席"}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-slate-500">{child.absence_reason ?? "—"}</td>
                    <td className="px-4 py-3 text-right">
                      <button
                        onClick={() => toggleAbsence(child)}
                        disabled={savingChildId === child.child_id}
                        className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-40"
                      >
                        {child.is_absent ? "出席に戻す" : "欠席にする"}
                      </button>
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}

export default function ChildcareAttendancePage() {
  return (
    <Suspense fallback={null}>
      <ChildcareAttendancePageContent />
    </Suspense>
  );
}
