"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import type { ChildcareOffice, ParentRequestRow } from "@/lib/types";
import { PARENT_REQUEST_TYPE_LABELS } from "@/lib/types";

export default function ChildcareParentRequestsPage() {
  const [offices, setOffices] = useState<ChildcareOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [selectedOffice, setSelectedOffice] = useState<string>("");

  const [requests, setRequests] = useState<ParentRequestRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [busyRequestId, setBusyRequestId] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_childcare_offices").then(({ data, error }) => {
      if (error) {
        setOfficesError(error.message);
        return;
      }
      const list = (data ?? []) as ChildcareOffice[];
      setOffices(list);
      if (list.length > 0) setSelectedOffice(list[0].office_id);
    });
  }, []);

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
      .rpc("fetch_pending_parent_requests", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRequests((data ?? []) as ParentRequestRow[]);
      });
  }, [selectedOffice, reloadToken]);

  async function approve(request: ParentRequestRow) {
    setBusyRequestId(request.request_id);
    const supabase = createClient();
    const { error } = await supabase.rpc("approve_parent_request", {
      p_request_id: request.request_id,
      p_decision_reason: null,
    });
    setBusyRequestId(null);
    if (error) {
      setRowsError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function reject(request: ParentRequestRow) {
    const reason = window.prompt("差し戻し理由を入力してください(必須)");
    if (!reason) return;
    setBusyRequestId(request.request_id);
    const supabase = createClient();
    const { error } = await supabase.rpc("reject_parent_request", {
      p_request_id: request.request_id,
      p_decision_reason: reason,
    });
    setBusyRequestId(null);
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
        <h2 className="text-lg font-bold text-slate-800">保護者申請の承認</h2>

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
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        <div className="space-y-4">
          {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}
          {!isLoading && requests.length === 0 && (
            <p className="text-sm text-slate-400">承認待ちの申請はありません</p>
          )}
          {requests.map((req) => (
            <div key={req.request_id} className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <h3 className="text-base font-bold text-slate-800">
                    {req.child_display_name}
                    <span className="ml-2 rounded-full bg-sky-50 px-2 py-0.5 text-xs font-semibold text-sky-700">
                      {PARENT_REQUEST_TYPE_LABELS[req.request_type]}
                    </span>
                  </h3>
                  <p className="text-xs text-slate-500">
                    申請者: {req.guardian_name} ・ 対象日: {req.target_date}
                  </p>
                </div>
                <p className="text-xs text-slate-400">
                  申請日時: {new Date(req.created_at).toLocaleString("ja-JP")}
                </p>
              </div>

              <div className="rounded-xl bg-slate-50 p-4 text-sm">
                {Object.entries(req.details ?? {}).length === 0 && (
                  <p className="text-slate-400">詳細情報はありません</p>
                )}
                {Object.entries(req.details ?? {}).map(([key, value]) => (
                  <p key={key} className="text-slate-700">
                    <span className="font-medium text-slate-500">{key}: </span>
                    {String(value)}
                  </p>
                ))}
              </div>

              <div className="flex gap-2">
                <button
                  onClick={() => reject(req)}
                  disabled={busyRequestId === req.request_id}
                  className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-50"
                >
                  差し戻す
                </button>
                <button
                  onClick={() => approve(req)}
                  disabled={busyRequestId === req.request_id}
                  className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                >
                  承認する
                </button>
              </div>
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
