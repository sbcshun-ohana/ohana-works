"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import type { ParentRequestRow } from "@/lib/types";
import { PARENT_REQUEST_TYPE_LABELS, ABSENCE_KIND_LABELS } from "@/lib/types";

function ChildcareParentRequestsPageContent() {
  // 施設選択はヘッダーに集約。selectedOffice は useChildcareOffices が ?office= に追随して供給する。
  const { offices, officesError, selectedOffice } = useChildcareOffices();

  const [requests, setRequests] = useState<ParentRequestRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [busyRequestId, setBusyRequestId] = useState<string | null>(null);
  // 202: 身分証画像の署名付きURL(request_id単位・表示ボタン押下時に発行)
  const [docUrlByRequest, setDocUrlByRequest] = useState<Record<string, string>>({});

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

  async function showIdDocument(request: ParentRequestRow) {
    if (!request.id_document_path || docUrlByRequest[request.request_id]) return;
    const supabase = createClient();
    const { data, error } = await supabase.storage
      .from("pickup-id-documents")
      .createSignedUrl(request.id_document_path, 300);
    if (error) {
      setRowsError(`身分証画像の取得に失敗しました: ${error.message}`);
      return;
    }
    setDocUrlByRequest((m) => ({ ...m, [request.request_id]: data.signedUrl }));
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
        <h2 className="text-lg font-bold text-slate-800">保護者からの連絡の承認</h2>

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
                    {req.request_type === "pickup_person_change" &&
                      (req.pickup_id_verified ? (
                        <span className="ml-2 rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-700">
                          ✓ 身分証確認済み
                        </span>
                      ) : req.id_document_path ? (
                        <span className="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800">
                          初回・要実物確認
                        </span>
                      ) : (
                        <span className="ml-2 rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">
                          身分証なし
                        </span>
                      ))}
                  </h3>
                  <p className="text-xs text-slate-500">
                    申請者: {req.guardian_name} ・ 対象日: {req.target_date}
                    {req.end_date ? `〜${req.end_date}` : ""}
                    {req.absence_kind ? ` ・${ABSENCE_KIND_LABELS[req.absence_kind]}` : ""}
                    {req.medication_kinds && req.medication_kinds.length > 0
                      ? ` ・薬: ${req.medication_kinds.join("、")}`
                      : ""}
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

              {req.id_document_path && (
                <div className="space-y-2">
                  {!docUrlByRequest[req.request_id] ? (
                    <button
                      onClick={() => showIdDocument(req)}
                      className="rounded-lg border border-sky-300 px-4 py-2 text-sm font-medium text-sky-700 hover:bg-sky-50"
                    >
                      身分証明書を表示
                    </button>
                  ) : (
                    // 署名付きURL(5分)。next/imageは外部署名URL非対応のため素imgを使う。
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={docUrlByRequest[req.request_id]}
                      alt="身分証明書"
                      className="max-h-80 rounded-xl border border-slate-200"
                    />
                  )}
                </div>
              )}

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

export default function ChildcareParentRequestsPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareParentRequestsPageContent />
    </Suspense>
  );
}
