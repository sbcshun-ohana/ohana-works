"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { currentDate } from "@/lib/datetime";
import type { ChildcareStaff, ClassActivityRow } from "@/lib/types";

const STATUS_LABELS: Record<string, string> = {
  draft: "下書き",
  submitted: "申請中",
  approved: "承認済み",
  rejected: "差し戻し",
};

function ChildcareClassActivitiesPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;

  const [businessDate, setBusinessDate] = useState(currentDate());
  const [rows, setRows] = useState<ClassActivityRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [staff, setStaff] = useState<ChildcareStaff[]>([]);
  const [selectedClassId, setSelectedClassId] = useState<string | null>(null);
  const [form, setForm] = useState({
    today_theme: "",
    activity_content: "",
    class_overview: "",
    class_announcement: "",
    other_notes: "",
  });
  const [isSaving, setIsSaving] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const selectedRow = rows.find((r) => r.class_id === selectedClassId) ?? null;

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
      .rpc("fetch_class_activities_for_office", {
        p_office_id: selectedOffice,
        p_business_date: businessDate,
      })
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRows((data ?? []) as ClassActivityRow[]);
      });
    supabase
      .rpc("fetch_childcare_office_staff", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        if (!error) setStaff((data ?? []) as ChildcareStaff[]);
      });
  }, [selectedOffice, businessDate, reloadToken]);

  useEffect(() => {
    function syncForm() {
      if (!selectedRow) return;
      setForm({
        today_theme: selectedRow.today_theme ?? "",
        activity_content: selectedRow.activity_content ?? "",
        class_overview: selectedRow.class_overview ?? "",
        class_announcement: selectedRow.class_announcement ?? "",
        other_notes: selectedRow.other_notes ?? "",
      });
    }
    syncForm();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedRow?.activity_id, selectedRow?.class_id]);

  async function ensureAndSelect(classId: string) {
    setSelectedClassId(classId);
    const row = rows.find((r) => r.class_id === classId);
    if (row?.activity_id) return;

    const supabase = createClient();
    const { error } = await supabase.rpc("ensure_class_daily_activity", {
      p_class_id: classId,
      p_business_date: businessDate,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function saveContent() {
    if (!selectedRow?.activity_id) return;
    setIsSaving(true);
    setActionError(null);
    const supabase = createClient();
    const { error } = await supabase
      .from("class_daily_activities")
      .update(form)
      .eq("id", selectedRow.activity_id);
    setIsSaving(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function claim() {
    if (!selectedRow?.activity_id) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("claim_class_activity", {
      p_activity_id: selectedRow.activity_id,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function reassign(employeeId: string) {
    if (!selectedRow?.activity_id) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("reassign_class_activity", {
      p_activity_id: selectedRow.activity_id,
      p_new_assignee_employee_id: employeeId,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function submit() {
    if (!selectedRow?.activity_id) return;
    await saveContent();
    const supabase = createClient();
    const { error } = await supabase.rpc("submit_class_activity", {
      p_activity_id: selectedRow.activity_id,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function approve() {
    if (!selectedRow?.activity_id) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("approve_class_activity", {
      p_activity_id: selectedRow.activity_id,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function reject() {
    if (!selectedRow?.activity_id) return;
    const reason = window.prompt("差し戻し理由を入力してください(必須)");
    if (!reason) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("reject_class_activity", {
      p_activity_id: selectedRow.activity_id,
      p_reason: reason,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  const canEditContent = selectedRow?.status === "draft" || selectedRow?.status === "rejected" || isManager;
  const canSubmit = selectedRow?.status === "draft" || selectedRow?.status === "rejected";

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
        <h2 className="text-lg font-bold text-slate-800">クラス活動 入力・申請・承認</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => {
                setSelectedOffice(e.target.value);
                setSelectedClassId(null);
              }}
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
            <label className="mb-1 block text-xs font-medium text-slate-500">対象日</label>
            <input
              type="date"
              value={businessDate}
              onChange={(e) => {
                setBusinessDate(e.target.value);
                setSelectedClassId(null);
              }}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}
        {actionError && <p className="text-sm font-medium text-red-500">{actionError}</p>}

        <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
          <div className="overflow-hidden rounded-2xl bg-white shadow-sm md:col-span-1">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">クラス</th>
                  <th className="px-4 py-3">状態</th>
                </tr>
              </thead>
              <tbody>
                {isLoading && (
                  <tr>
                    <td colSpan={2} className="px-4 py-6 text-center text-slate-400">
                      読み込み中…
                    </td>
                  </tr>
                )}
                {!isLoading &&
                  rows.map((row) => (
                    <tr
                      key={row.class_id}
                      onClick={() => ensureAndSelect(row.class_id)}
                      className={`cursor-pointer border-b border-slate-100 last:border-0 hover:bg-slate-50 ${
                        selectedClassId === row.class_id ? "bg-sky-50" : ""
                      }`}
                    >
                      <td className="px-4 py-3 font-medium text-slate-800">{row.class_name}</td>
                      <td className="px-4 py-3">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                            row.status === "approved"
                              ? "bg-emerald-50 text-emerald-700"
                              : row.status === "rejected"
                                ? "bg-red-50 text-red-600"
                                : row.status === "submitted"
                                  ? "bg-sky-50 text-sky-700"
                                  : "bg-slate-100 text-slate-500"
                          }`}
                        >
                          {row.status ? STATUS_LABELS[row.status] : "未着手"}
                        </span>
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>

          <div className="rounded-2xl bg-white p-4 shadow-sm md:col-span-2">
            {!selectedRow && <p className="text-sm text-slate-400">左のクラスを選択してください</p>}
            {selectedRow && (
              <div className="space-y-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <h3 className="text-base font-bold text-slate-800">{selectedRow.class_name}</h3>
                  <div className="flex items-center gap-2 text-xs text-slate-500">
                    担当: {selectedRow.assignee_name ?? "未割当"}
                    {!selectedRow.assignee_employee_id && (
                      <button
                        onClick={claim}
                        className="rounded-lg border border-slate-300 px-2 py-1 font-medium text-slate-600 hover:bg-slate-100"
                      >
                        自分を担当にする
                      </button>
                    )}
                    {isManager && (
                      <select
                        value=""
                        onChange={(e) => e.target.value && reassign(e.target.value)}
                        className="rounded-lg border border-slate-300 px-2 py-1 text-xs"
                      >
                        <option value="">担当者を変更…</option>
                        {staff.map((s) => (
                          <option key={s.employee_id} value={s.employee_id}>
                            {s.name}
                          </option>
                        ))}
                      </select>
                    )}
                  </div>
                </div>

                {selectedRow.rejected_reason && (
                  <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                    差し戻し理由: {selectedRow.rejected_reason}
                  </div>
                )}

                {([
                  ["today_theme", "今日の活動"],
                  ["activity_content", "活動内容"],
                  ["class_overview", "クラス全体の様子"],
                  ["class_announcement", "クラス全体へのお知らせ"],
                  ["other_notes", "その他"],
                ] as const).map(([key, label]) => (
                  <div key={key}>
                    <label className="mb-1 block text-xs font-medium text-slate-500">{label}</label>
                    <textarea
                      value={form[key]}
                      onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
                      disabled={!canEditContent}
                      rows={key === "activity_content" || key === "class_overview" ? 3 : 2}
                      className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none disabled:bg-slate-50 disabled:text-slate-400"
                    />
                  </div>
                ))}

                <div className="flex flex-wrap gap-2 pt-2">
                  {canEditContent && (
                    <button
                      onClick={saveContent}
                      disabled={isSaving}
                      className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-50"
                    >
                      下書き保存
                    </button>
                  )}
                  {canSubmit && selectedRow.assignee_employee_id && (
                    <button
                      onClick={submit}
                      className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
                    >
                      申請する
                    </button>
                  )}
                  {isManager && selectedRow.status === "submitted" && (
                    <>
                      <button
                        onClick={approve}
                        className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700"
                      >
                        承認する
                      </button>
                      <button
                        onClick={reject}
                        className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50"
                      >
                        差し戻す
                      </button>
                    </>
                  )}
                </div>
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}

export default function ChildcareClassActivitiesPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareClassActivitiesPageContent />
    </Suspense>
  );
}
