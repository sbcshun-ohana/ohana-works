"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// アレルギー管理 Phase 1: 発症報告の確認 → 給食停止(弁当持参)/再開/停止しない判断。migration 271。

type Report = {
  id: string;
  child_id: string;
  child_name: string;
  eaten_food: string | null;
  symptoms: string;
  occurred_at: string | null;
  hospital_plan: string | null;
  status: string;
  review_note: string | null;
  reviewed_at: string | null;
  created_at: string;
  suspended: boolean;
};

type Suspended = { child_id: string; child_name: string; note: string | null; started_at: string };

function fmt(ts: string | null): string {
  if (!ts) return "—";
  const d = new Date(ts);
  return `${d.getMonth() + 1}/${d.getDate()} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function AllergyIncidentsContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;
  const [reports, setReports] = useState<Report[]>([]);
  const [suspended, setSuspended] = useState<Suspended[]>([]);
  const [onlyOpen, setOnlyOpen] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    if (!selectedOffice) return;
    let cancelled = false;
    void (async () => {
      const supabase = createClient();
      const [{ data: r, error: rErr }, { data: s }] = await Promise.all([
        supabase.rpc("fetch_allergy_incident_reports_for_office", { p_office_id: selectedOffice, p_only_open: onlyOpen }),
        supabase.rpc("fetch_meal_suspended_children_for_office", { p_office_id: selectedOffice }),
      ]);
      if (cancelled) return;
      if (rErr) setError(rErr.message);
      else setError(null);
      setReports((r ?? []) as Report[]);
      setSuspended((s ?? []) as Suspended[]);
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedOffice, onlyOpen, reloadToken]);

  async function suspend(childId: string, reportId: string) {
    const note = window.prompt("給食停止(弁当持参)にします。メモ(任意):", "アレルギー確認中") ?? "";
    const supabase = createClient();
    const { error: e } = await supabase.rpc("suspend_child_meal", {
      p_child_id: childId,
      p_incident_report_id: reportId,
      p_note: note || null,
    });
    if (e) setError(e.message);
    else setReloadToken((t) => t + 1);
  }

  async function resume(childId: string) {
    if (!window.confirm("給食を再開します(弁当持参を解除)。よろしいですか?")) return;
    const note = window.prompt("再開のメモ(任意・受診結果など):", "") ?? "";
    const supabase = createClient();
    const { error: e } = await supabase.rpc("resume_child_meal", { p_child_id: childId, p_note: note || null });
    if (e) setError(e.message);
    else setReloadToken((t) => t + 1);
  }

  async function noSuspension(reportId: string) {
    const note = window.prompt("給食停止せず対応済みにします。理由(任意):", "提供食材と無関係のため") ?? "";
    const supabase = createClient();
    const { error: e } = await supabase.rpc("record_incident_no_suspension", { p_incident_report_id: reportId, p_note: note || null });
    if (e) setError(e.message);
    else setReloadToken((t) => t + 1);
  }

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <MealSubNav />
      <main className="flex-1 space-y-5 p-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-bold text-slate-800">アレルギー発症報告</h2>
          <label className="flex cursor-pointer items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" checked={onlyOpen} onChange={(e) => setOnlyOpen(e.target.checked)} className="h-4 w-4" />
            未対応のみ
          </label>
        </div>
        <p className="text-xs text-slate-400">
          保護者からのアレルギー反応の報告です。内容を確認し、必要なら「給食停止(弁当持参)」にしてください(自動では止まりません)。停止/再開は主任以上。
        </p>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}

        {/* 給食停止中の園児(弁当持参) */}
        {suspended.length > 0 && (
          <div className="space-y-2 rounded-2xl border border-red-200 bg-red-50 p-4 shadow-sm">
            <h3 className="text-sm font-bold text-red-700">給食停止中(弁当持参・アレルギー確認中) {suspended.length}名</h3>
            {suspended.map((s) => (
              <div key={s.child_id} className="flex flex-wrap items-center justify-between gap-2 border-t border-red-100 pt-2">
                <span className="text-sm font-semibold text-slate-800">
                  {s.child_name}
                  {s.note ? <span className="ml-2 text-xs font-normal text-slate-500">{s.note}</span> : ""}
                  <span className="ml-2 text-xs font-normal text-slate-400">({fmt(s.started_at)}〜)</span>
                </span>
                {isManager && (
                  <button
                    onClick={() => resume(s.child_id)}
                    className="rounded-lg bg-emerald-600 px-3 py-1 text-xs font-semibold text-white hover:bg-emerald-700"
                  >
                    給食を再開
                  </button>
                )}
              </div>
            ))}
          </div>
        )}

        {/* 発症報告一覧 */}
        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-3 py-3">園児</th>
                <th className="px-3 py-3">食べたもの</th>
                <th className="px-3 py-3">症状</th>
                <th className="px-3 py-3">発生</th>
                <th className="px-3 py-3">受診予定</th>
                <th className="px-3 py-3">状態</th>
                <th className="px-3 py-3">対応</th>
              </tr>
            </thead>
            <tbody>
              {reports.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-3 py-6 text-center text-slate-400">
                    {onlyOpen ? "未対応の発症報告はありません" : "発症報告はありません"}
                  </td>
                </tr>
              )}
              {reports.map((r) => (
                <tr key={r.id} className="border-b border-slate-100 align-top last:border-0">
                  <td className="px-3 py-3 font-medium text-slate-800">{r.child_name}</td>
                  <td className="px-3 py-3 text-slate-600">{r.eaten_food || "—"}</td>
                  <td className="whitespace-pre-wrap px-3 py-3 text-slate-700">{r.symptoms}</td>
                  <td className="px-3 py-3 text-slate-500">{fmt(r.occurred_at)}</td>
                  <td className="px-3 py-3 text-slate-500">{r.hospital_plan || "—"}</td>
                  <td className="px-3 py-3">
                    {r.suspended ? (
                      <span className="rounded-full bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-600">給食停止中</span>
                    ) : r.status === "reported" ? (
                      <span className="rounded-full bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-700">未対応</span>
                    ) : (
                      <span className="text-xs text-slate-400">対応済{r.review_note ? `: ${r.review_note}` : ""}</span>
                    )}
                  </td>
                  <td className="px-3 py-3">
                    {isManager && (
                      <div className="flex flex-wrap gap-2">
                        {!r.suspended && (
                          <button
                            onClick={() => suspend(r.child_id, r.id)}
                            className="rounded-lg bg-red-600 px-3 py-1 text-xs font-semibold text-white hover:bg-red-700"
                          >
                            給食停止
                          </button>
                        )}
                        {r.suspended && (
                          <button
                            onClick={() => resume(r.child_id)}
                            className="rounded-lg bg-emerald-600 px-3 py-1 text-xs font-semibold text-white hover:bg-emerald-700"
                          >
                            再開
                          </button>
                        )}
                        {r.status === "reported" && (
                          <button
                            onClick={() => noSuspension(r.id)}
                            className="rounded-lg border border-slate-300 px-3 py-1 text-xs text-slate-600 hover:bg-slate-50"
                          >
                            停止しない
                          </button>
                        )}
                      </div>
                    )}
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

export default function AllergyIncidentsPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-400">読み込み中…</div>}>
      <AllergyIncidentsContent />
    </Suspense>
  );
}
