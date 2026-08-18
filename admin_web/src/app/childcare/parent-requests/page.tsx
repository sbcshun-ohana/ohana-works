"use client";

import { Fragment, Suspense, useEffect, useState } from "react";
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
  // 俊指示(2026-08-14): 承認/差し戻し済みも履歴としてこの画面に残す(直近50件・RLS直接select)。
  const [history, setHistory] = useState<
    {
      id: string;
      request_type: string;
      status: "approved" | "rejected";
      target_date: string;
      end_date: string | null;
      absence_kind: string | null;
      details: Record<string, unknown> | null;
      created_at: string;
      approved_at: string | null;
      decision_reason: string | null;
      children: { display_name: string };
    }[]
  >([]);
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
    supabase
      .from("parent_requests")
      .select(
        "id, request_type, status, target_date, end_date, absence_kind, details, created_at, approved_at, decision_reason, children!inner(display_name, office_id)",
      )
      .eq("children.office_id", selectedOffice)
      .in("status", ["approved", "rejected"])
      .order("created_at", { ascending: false })
      .limit(50)
      .then(({ data, error }) => {
        if (!error) setHistory((data ?? []) as unknown as typeof history);
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

  // 差し戻し(reject)は俊指示(2026-08-18)で廃止。保護者からの連絡は受領(承認)のみ。
  // 過去に差し戻された履歴は下部の履歴表に status='rejected' として表示する。

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

        {/* 承認待ち(表形式・列を揃える。俊指示 2026-08-18) */}
        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-slate-200 bg-slate-50 text-xs text-slate-500">
              <tr>
                <th className="px-4 py-2">園児</th>
                <th className="px-4 py-2">種別</th>
                <th className="px-4 py-2">対象日</th>
                <th className="px-4 py-2">申請者</th>
                <th className="px-4 py-2">申請日時</th>
                <th className="px-4 py-2">詳細</th>
                <th className="px-4 py-2 text-right">操作</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {isLoading && (
                <tr>
                  <td colSpan={7} className="px-4 py-6 text-center text-slate-400">読み込み中…</td>
                </tr>
              )}
              {!isLoading && requests.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-4 py-6 text-center text-slate-400">承認待ちの連絡はありません</td>
                </tr>
              )}
              {requests.map((req) => (
                <Fragment key={req.request_id}>
                  <tr className="align-top">
                    <td className="px-4 py-3 font-medium text-slate-800">{req.child_display_name}</td>
                    <td className="px-4 py-3">
                      <div className="flex flex-wrap gap-1">
                        <span className="rounded-full bg-sky-50 px-2 py-0.5 text-xs font-semibold text-sky-700">
                          {PARENT_REQUEST_TYPE_LABELS[req.request_type]}
                        </span>
                        {req.request_type === "absence" && req.details?.["感染症により欠席"] != null && (
                          <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-700">
                            感染症{req.details?.["感染症の種類"] ? `: ${String(req.details["感染症の種類"])}` : ""}
                          </span>
                        )}
                        {req.request_type === "pickup_person_change" &&
                          (req.pickup_id_verified ? (
                            <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-700">
                              ✓ 身分証確認済み
                            </span>
                          ) : req.id_document_path ? (
                            <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800">
                              初回・要実物確認
                            </span>
                          ) : (
                            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">
                              身分証なし
                            </span>
                          ))}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-slate-600">
                      {req.target_date}
                      {req.end_date ? `〜${req.end_date}` : ""}
                      {req.absence_kind ? (
                        <div className="text-xs text-slate-400">{ABSENCE_KIND_LABELS[req.absence_kind]}</div>
                      ) : null}
                      {req.medication_kinds && req.medication_kinds.length > 0 ? (
                        <div className="text-xs text-slate-400">薬: {req.medication_kinds.join("、")}</div>
                      ) : null}
                    </td>
                    <td className="px-4 py-3 text-slate-600">{req.guardian_name}</td>
                    <td className="px-4 py-3 text-xs text-slate-400">
                      {new Date(req.created_at).toLocaleString("ja-JP")}
                    </td>
                    <td className="px-4 py-3">
                      <div className="space-y-0.5">
                        {Object.entries(req.details ?? {}).map(([key, value]) => (
                          <p key={key} className="text-xs text-slate-600">
                            <span className="text-slate-400">{key}: </span>
                            {String(value)}
                          </p>
                        ))}
                        {req.id_document_path && !docUrlByRequest[req.request_id] && (
                          <button
                            onClick={() => showIdDocument(req)}
                            className="mt-1 rounded-lg border border-sky-300 px-2 py-1 text-xs font-medium text-sky-700 hover:bg-sky-50"
                          >
                            身分証を表示
                          </button>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button
                        onClick={() => approve(req)}
                        disabled={busyRequestId === req.request_id}
                        className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                      >
                        承認する
                      </button>
                    </td>
                  </tr>
                  {req.id_document_path && docUrlByRequest[req.request_id] && (
                    <tr>
                      <td colSpan={7} className="px-4 pb-3">
                        {/* 署名付きURL(5分)。next/imageは外部署名URL非対応のため素imgを使う。 */}
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img
                          src={docUrlByRequest[req.request_id]}
                          alt="身分証明書"
                          className="max-h-80 rounded-xl border border-slate-200"
                        />
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>

        {/* 承認/差し戻し履歴(直近50件)。俊指示(2026-08-14): 処理後もこの画面に残す */}
        {history.length > 0 && (
          <div className="rounded-2xl bg-white p-5 shadow-sm">
            <h3 className="mb-3 text-sm font-bold text-slate-700">
              処理済みの履歴 <span className="text-xs font-normal text-slate-400">(直近{history.length}件)</span>
            </h3>
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead className="border-b border-slate-200 text-xs text-slate-500">
                  <tr>
                    <th className="px-3 py-2">園児</th>
                    <th className="px-3 py-2">種別</th>
                    <th className="px-3 py-2">対象日</th>
                    <th className="px-3 py-2">状態</th>
                    <th className="px-3 py-2">処理日時</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {history.map((h) => (
                    <tr key={h.id}>
                      <td className="px-3 py-2 font-medium text-slate-800">{h.children.display_name}</td>
                      <td className="px-3 py-2">
                        <div className="flex flex-wrap gap-1">
                          <span className="rounded-full bg-sky-50 px-2 py-0.5 text-xs font-semibold text-sky-700">
                            {PARENT_REQUEST_TYPE_LABELS[h.request_type as keyof typeof PARENT_REQUEST_TYPE_LABELS] ??
                              h.request_type}
                          </span>
                          {h.request_type === "absence" && h.details?.["感染症により欠席"] != null && (
                            <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-700">
                              感染症{h.details?.["感染症の種類"] ? `: ${String(h.details["感染症の種類"])}` : ""}
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="px-3 py-2 text-slate-600">
                        {h.target_date}
                        {h.end_date ? `〜${h.end_date}` : ""}
                        {h.absence_kind ? (
                          <div className="text-xs text-slate-400">
                            {ABSENCE_KIND_LABELS[h.absence_kind as "sick_absence" | "personal_absence"]}
                          </div>
                        ) : null}
                      </td>
                      <td className="px-3 py-2">
                        {h.status === "approved" ? (
                          <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-700">
                            承認済み
                          </span>
                        ) : (
                          <span
                            className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-700"
                            title={h.decision_reason ?? undefined}
                          >
                            差し戻し{h.decision_reason ? `(${h.decision_reason})` : ""}
                          </span>
                        )}
                      </td>
                      <td className="px-3 py-2 text-xs text-slate-400">
                        {h.approved_at ? new Date(h.approved_at).toLocaleString("ja-JP") : ""}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
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
