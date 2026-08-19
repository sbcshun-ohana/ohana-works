"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// ---- ラベル定義(Kids側 incident_common.dart と対応) ----
const REPORT_TYPES: Record<string, string> = {
  hiyari: "ヒヤリハット",
  minor: "事故報告書・園内対応(軽症)",
  hospital: "事故報告書・病院搬送(重大事故)",
};
const STATUSES: Record<string, string> = {
  draft: "下書き",
  submitted: "申請中(主任承認待ち)",
  chief_approved: "主任承認済(園長承認待ち)",
  approved: "承認済",
};
const REACTION_KINDS: Record<string, string> = {
  understood: "状況をご説明しご理解いただけた",
  other: "その他",
};
const PROGRESS_KINDS: Record<string, string> = { ok: "大丈夫です", other: "その他" };
const DOCTOR_INSTRUCTIONS: Record<string, string> = { can_attend: "今後の登園可", cannot_attend: "登園不可" };
const CAUSE_KEYS: Record<string, string> = {
  child_behavior: "子どもの状況・行動",
  environment: "環境・設備",
  objects: "物・遊具",
  care_rules: "保育・対応・ルール",
};
const LOOKUP_KINDS: { kind: string; label: string }[] = [
  { kind: "place", label: "発生場所" },
  { kind: "injury_site", label: "受傷部位" },
  { kind: "med_department", label: "診察科" },
  { kind: "med_exam", label: "受診内容" },
  { kind: "med_treatment", label: "処置内容" },
  { kind: "med_prescription", label: "処方薬" },
];

type IncidentRow = {
  id: string;
  office_id: string;
  office_name: string;
  report_type: string;
  status: string;
  occurred_on: string | null;
  occurred_at: string | null;
  place_label: string | null;
  closure_status: string | null;
  child_names: string | null;
  created_by_name: string | null;
  submitted_at: string | null;
  approved_at: string | null;
  updated_at: string | null;
};

type IncidentDetail = Record<string, unknown>;
type LookupOption = { id: string; kind: string; label: string; sort_order: number };

function fmtDate(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? String(iso) : d.toLocaleDateString("ja-JP");
}
function fmtTime(t: string | null | undefined): string {
  if (!t) return "";
  const parts = String(t).split(":");
  return parts.length >= 2 ? `${parts[0]}:${parts[1]}` : String(t);
}
function fmtDateTime(iso: unknown): string {
  if (!iso) return "";
  const d = new Date(String(iso));
  return Number.isNaN(d.getTime()) ? String(iso) : d.toLocaleString("ja-JP");
}

function typeBadgeClass(t: string): string {
  if (t === "hospital") return "bg-red-100 text-red-700";
  if (t === "minor") return "bg-orange-100 text-orange-700";
  return "bg-sky-100 text-sky-700";
}
function statusBadgeClass(s: string): string {
  if (s === "approved") return "bg-emerald-100 text-emerald-700";
  if (s === "submitted" || s === "chief_approved") return "bg-orange-100 text-orange-700";
  return "bg-slate-100 text-slate-600";
}

function ChildcareIncidentsPageContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();

  const [rows, setRows] = useState<IncidentRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [typeFilter, setTypeFilter] = useState<string>("");
  const [statusFilter, setStatusFilter] = useState<string>("");
  const [reloadToken, setReloadToken] = useState(0);

  const [detailId, setDetailId] = useState<string | null>(null);
  const [detail, setDetail] = useState<IncidentDetail | null>(null);
  const [closure, setClosure] = useState<Record<string, unknown> | null>(null);
  const [busy, setBusy] = useState(false);
  const [showLookups, setShowLookups] = useState(false);
  const [formOpen, setFormOpen] = useState(false);
  const [formReportId, setFormReportId] = useState<string | null>(null);
  const [openOnly, setOpenOnly] = useState(false);
  const [openCount, setOpenCount] = useState(0);

  useEffect(() => {
    function begin() {
      if (!selectedOffice) return null;
      setIsLoading(true);
      setRowsError(null);
      return createClient();
    }
    const supabase = begin();
    if (!supabase) return;
    void supabase.rpc("count_open_incident_reports", { p_office_id: selectedOffice }).then(({ data }) => {
      setOpenCount(typeof data === "number" ? data : 0);
    });
    const query = openOnly
      ? supabase.rpc("fetch_open_incident_reports", { p_office_id: selectedOffice })
      : supabase.rpc("fetch_incident_reports", {
          p_office_id: selectedOffice,
          p_status: statusFilter || null,
          p_report_type: typeFilter || null,
        });
    query.then(({ data, error }) => {
      setIsLoading(false);
      if (error) {
        setRowsError(error.message);
        return;
      }
      setRows((data ?? []) as IncidentRow[]);
    });
  }, [selectedOffice, statusFilter, typeFilter, reloadToken, openOnly]);

  const openDetail = useCallback(async (id: string) => {
    setDetailId(id);
    setDetail(null);
    setClosure(null);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("fetch_incident_report_detail", { p_id: id });
    if (!error) setDetail(data as IncidentDetail);
    const { data: cData } = await supabase.rpc("fetch_incident_closure", { p_id: id });
    const cRow = Array.isArray(cData) ? (cData[0] as Record<string, unknown>) : null;
    setClosure(cRow ?? null);
  }, []);

  async function runAction(fn: (s: ReturnType<typeof createClient>) => Promise<{ error: { message: string } | null }>, ok: string) {
    setBusy(true);
    const supabase = createClient();
    const { error } = await fn(supabase);
    setBusy(false);
    if (error) {
      alert(`操作できません: ${error.message}`);
      return;
    }
    alert(ok);
    setReloadToken((t) => t + 1);
    if (detailId) void openDetail(detailId);
  }

  const report = (detail?.["report"] as Record<string, unknown>) ?? null;

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
      <main className="flex-1 space-y-5 p-6">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-slate-800">ヒヤリハット・事故報告</h2>
          <div className="flex gap-2">
            <button
              onClick={() => setShowLookups(true)}
              className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-slate-50"
            >
              ルックアップ管理
            </button>
            <button
              onClick={() => { setFormReportId(null); setFormOpen(true); }}
              className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-sky-700"
            >
              新規作成
            </button>
          </div>
        </div>
        <p className="text-xs text-slate-400">報告書の作成・申請・承認・差し戻し・保護者対応クローズを行えます(作成は Ohana Kids(iPad)からも可能です)。</p>

        <div className="flex flex-wrap items-center gap-3">
          <button
            onClick={() => setOpenOnly((v) => !v)}
            className={`rounded-lg px-3 py-1.5 text-sm font-semibold ${openOnly ? "bg-red-600 text-white" : "border border-slate-300 text-slate-600 hover:bg-slate-50"}`}
          >
            未クローズの事故報告のみ{openCount > 0 ? `(${openCount})` : ""}
          </button>
          {!openOnly && (
            <>
              <select
                value={typeFilter}
                onChange={(e) => setTypeFilter(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm"
              >
                <option value="">すべての種別</option>
                {Object.entries(REPORT_TYPES).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm"
              >
                <option value="">すべての状態</option>
                {Object.entries(STATUSES).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
            </>
          )}
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-slate-100 text-xs text-slate-400">
              <tr>
                <th className="px-3 py-2">種別</th>
                <th className="px-3 py-2">状態</th>
                <th className="px-3 py-2">発生日時</th>
                <th className="px-3 py-2">発生場所</th>
                <th className="px-3 py-2">園児</th>
                <th className="px-3 py-2">記入者</th>
                <th className="px-3 py-2">クローズ</th>
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr><td colSpan={7} className="px-3 py-6 text-center text-slate-400">読み込み中…</td></tr>
              )}
              {!isLoading && rows.length === 0 && (
                <tr><td colSpan={7} className="px-3 py-6 text-center text-slate-400">報告書はありません</td></tr>
              )}
              {rows.map((r) => (
                <tr
                  key={r.id}
                  onClick={() => void openDetail(r.id)}
                  className="cursor-pointer border-b border-slate-50 hover:bg-slate-50"
                >
                  <td className="px-3 py-2">
                    <span className={`rounded px-2 py-0.5 text-xs font-semibold ${typeBadgeClass(r.report_type)}`}>
                      {REPORT_TYPES[r.report_type] ?? r.report_type}
                    </span>
                  </td>
                  <td className="px-3 py-2">
                    <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${statusBadgeClass(r.status)}`}>
                      {STATUSES[r.status] ?? r.status}
                    </span>
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap">{fmtDate(r.occurred_on)} {fmtTime(r.occurred_at)}</td>
                  <td className="px-3 py-2">{r.place_label ?? ""}</td>
                  <td className="px-3 py-2">{r.child_names ?? ""}</td>
                  <td className="px-3 py-2">{r.created_by_name ?? ""}</td>
                  <td className="px-3 py-2">
                    {openOnly ? (
                      (() => {
                        const days = (r as unknown as Record<string, unknown>)["days_elapsed"];
                        const missing = ((r as unknown as Record<string, unknown>)["missing"] as string[]) ?? [];
                        return (
                          <div>
                            <span className={`text-xs font-bold ${typeof days === "number" && days >= 3 ? "text-red-600" : "text-slate-500"}`}>
                              経過{String(days ?? "")}日
                            </span>
                            {missing.length > 0 && (
                              <div className="text-xs text-red-500">不足: {missing.join("、")}</div>
                            )}
                          </div>
                        );
                      })()
                    ) : r.closure_status === "open" ? (
                      <span className="text-xs font-semibold text-red-600">未クローズ</span>
                    ) : r.closure_status === "closed" ? (
                      <span className="text-xs text-slate-400">クローズ済</span>
                    ) : (
                      ""
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>

      {detailId && (
        <DetailDrawer
          detail={detail}
          report={report}
          closure={closure}
          busy={busy}
          onClose={() => { setDetailId(null); setDetail(null); setClosure(null); }}
          onEdit={() => { setFormReportId(detailId); setFormOpen(true); }}
          onCloseReport={() => {
            const note = window.prompt("保護者対応クローズのコメント(任意・空でも可)") ?? "";
            void runAction(async (s) => {
              const { error } = await s.rpc("close_incident_report", { p_id: detailId, p_note: note || null });
              return { error };
            }, "クローズしました");
          }}
          onReopen={() => {
            const reason = window.prompt("クローズ解除の理由(必須)");
            if (!reason) return;
            void runAction(async (s) => {
              const { error } = await s.rpc("reopen_incident_closure", { p_id: detailId, p_reason: reason });
              return { error };
            }, "クローズを解除しました");
          }}
          onSubmit={() => runAction(async (s) => {
            const { error } = await s.rpc("submit_incident_report", { p_id: detailId });
            return { error };
          }, "申請しました")}
          onChiefApprove={() => runAction(async (s) => {
            const { error } = await s.rpc("chief_approve_incident_report", { p_id: detailId });
            return { error };
          }, "主任承認しました")}
          onApprove={() => runAction(async (s) => {
            const { error } = await s.rpc("approve_incident_report", { p_id: detailId });
            return { error };
          }, "承認しました")}
          onReject={() => {
            const reason = window.prompt("差し戻しの理由を入力してください");
            if (!reason) return;
            void runAction(async (s) => {
              const { error } = await s.rpc("reject_incident_report", { p_id: detailId, p_reason: reason });
              return { error };
            }, "差し戻しました");
          }}
          onCancel={() => {
            const reason = window.prompt("承認取消の理由を入力してください");
            if (!reason) return;
            void runAction(async (s) => {
              const { error } = await s.rpc("cancel_incident_approval", { p_id: detailId, p_reason: reason });
              return { error };
            }, "承認を取り消しました");
          }}
        />
      )}

      {showLookups && <LookupManager onClose={() => setShowLookups(false)} />}

      {formOpen && selectedOffice && (
        <IncidentFormDrawer
          officeId={selectedOffice}
          reportId={formReportId}
          onClose={() => setFormOpen(false)}
          onSaved={() => {
            setFormOpen(false);
            setReloadToken((t) => t + 1);
            if (detailId) void openDetail(detailId);
          }}
        />
      )}
    </div>
  );
}

function DetailDrawer({
  detail,
  report,
  closure,
  busy,
  onClose,
  onEdit,
  onCloseReport,
  onReopen,
  onSubmit,
  onChiefApprove,
  onApprove,
  onReject,
  onCancel,
}: {
  detail: IncidentDetail | null;
  report: Record<string, unknown> | null;
  closure: Record<string, unknown> | null;
  busy: boolean;
  onClose: () => void;
  onEdit: () => void;
  onCloseReport: () => void;
  onReopen: () => void;
  onSubmit: () => void;
  onChiefApprove: () => void;
  onApprove: () => void;
  onReject: () => void;
  onCancel: () => void;
}) {
  const s = (report?.["status"] as string) ?? "";
  const rt = (report?.["report_type"] as string) ?? "";
  const g = (k: string): string => {
    const v = report?.[k];
    return v == null || v === "" ? "" : String(v);
  };
  const arr = (k: string): Record<string, unknown>[] => (detail?.[k] as Record<string, unknown>[]) ?? [];
  const causes = (report?.["causes"] as Record<string, unknown>) ?? {};
  const counts = (report?.["staff_counts"] as Record<string, unknown>) ?? {};

  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/30" onClick={onClose}>
      <div className="h-full w-full max-w-2xl overflow-y-auto bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
        {!detail || !report ? (
          <p className="text-slate-400">読み込み中…</p>
        ) : (
          <>
            <div className="mb-4 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className={`rounded px-2 py-0.5 text-xs font-semibold ${typeBadgeClass(rt)}`}>{REPORT_TYPES[rt] ?? rt}</span>
                <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${statusBadgeClass(s)}`}>{STATUSES[s] ?? s}</span>
              </div>
              <button onClick={onClose} className="text-slate-400 hover:text-slate-600">✕</button>
            </div>

            {g("rejected_reason") && s === "draft" && (
              <div className="mb-4 rounded-lg bg-red-50 p-3 text-sm text-red-700">差し戻し理由: {g("rejected_reason")}</div>
            )}

            <Section title="基本情報">
              <KV k="発生日時" v={`${fmtDate(g("occurred_on"))} ${fmtTime(g("occurred_at"))}`} />
              <KV k="発生場所" v={(detail["place_label"] as string) ?? "-"} />
              <KV k="記入者" v={(detail["created_by_name"] as string) ?? "-"} />
              <KV
                k="対象園児"
                v={arr("children").map((c) => (c["child_name_snapshot"] as string) ?? "").filter(Boolean).join("、") || "-"}
              />
            </Section>

            <Section title="発生状況">
              <KV k="いつ" v={g("situation_when")} />
              <KV k="どこで" v={g("situation_where")} />
              <KV k="何をしたとき" v={g("situation_what")} />
              <KV k="どうなった" v={g("situation_result")} />
            </Section>

            <Section title="現場の人員">
              <KV k="人数" v={`保育士 ${counts["hoiku"] ?? 0}名 / 園児 ${counts["jido"] ?? 0}名 / 目撃者 ${counts["witness"] ?? 0}名`} />
            </Section>

            <Section title="原因・問題点">
              {Object.entries(CAUSE_KEYS)
                .filter(([k]) => causes[k])
                .map(([k, label]) => <KV key={k} k={label} v={String(causes[k])} />)}
            </Section>

            {rt !== "hiyari" && (
              <Section title="発生後の対応">
                <KV k="受傷部位" v={(detail["injury_site_label"] as string) ?? "-"} />
                <KV k="受傷内容" v={g("injury_detail")} />
                <KV k="応急処置" v={g("first_aid")} />
              </Section>
            )}

            <Section title="経過と観察記録">
              {arr("progress_logs").length === 0 ? (
                <p className="text-sm text-slate-400">記録なし</p>
              ) : (
                arr("progress_logs").map((p, i) => (
                  <LogLine
                    key={i}
                    head={fmtDateTime(p["logged_at"])}
                    body={`${PROGRESS_KINDS[String(p["report_kind"])] ?? ""}${p["report_text"] ? `  ${p["report_text"]}` : ""}`}
                  />
                ))
              )}
            </Section>

            <Section title="保護者連絡">
              {arr("guardian_contacts").length === 0 ? (
                <p className="text-sm text-slate-400">記録なし</p>
              ) : (
                arr("guardian_contacts").map((c, i) => (
                  <LogLine
                    key={i}
                    head={`${fmtDateTime(c["contacted_at"])}  ・  ${c["contact_book_written"] ? "連絡帳に記載" : "口頭で直接"}`}
                    body={`${REACTION_KINDS[String(c["reaction_kind"])] ?? ""}${c["reaction_text"] ? `  ${c["reaction_text"]}` : ""}`}
                  />
                ))
              )}
            </Section>

            {rt === "hospital" && (
              <Section title="受診記録">
                {arr("medical_visits").length === 0 ? (
                  <p className="text-sm text-slate-400">記録なし</p>
                ) : (
                  arr("medical_visits").map((m, i) => (
                    <div key={i} className="mb-2 rounded-lg bg-slate-50 p-3 text-sm">
                      <div className="font-semibold">{(m["medical_institution"] as string) ?? "医療機関未記入"}</div>
                      {m["doctor_name"] ? <div>医師: {String(m["doctor_name"])}</div> : null}
                      {m["exam_detail"] ? <div>内容: {String(m["exam_detail"])}</div> : null}
                      {m["doctor_instruction"] ? <div>医師の指示: {DOCTOR_INSTRUCTIONS[String(m["doctor_instruction"])] ?? ""}</div> : null}
                      {m["prescription_present"] ? <div>処方薬あり{m["prescription_detail"] ? `: ${m["prescription_detail"]}` : ""}</div> : null}
                      {m["treatment_period"] ? <div>治療期間: {String(m["treatment_period"])}</div> : null}
                    </div>
                  ))
                )}
              </Section>
            )}

            <Section title="再発防止">
              <p className="text-sm">{g("prevention_text") || "-"}</p>
            </Section>
            {g("note_text") && (
              <Section title="その他">
                <p className="text-sm">{g("note_text")}</p>
              </Section>
            )}

            {rt !== "hiyari" && (
              <Section title="保護者対応(クロージング)">
                {(() => {
                  const cs = closure?.["closure_status"] as string | undefined;
                  const missing = (closure?.["missing"] as string[]) ?? [];
                  if (cs === "closed") {
                    return (
                      <>
                        <KV k="状態" v="クローズ済" />
                        <KV k="クローズ" v={`${(closure?.["closed_by_name"] as string) ?? "-"}  ${fmtDateTime(closure?.["closed_at"])}`} />
                        {closure?.["reopened_at"] ? (
                          <KV k="再オープン" v={`${(closure?.["reopened_by_name"] as string) ?? "-"}  ${fmtDateTime(closure?.["reopened_at"])}`} />
                        ) : null}
                      </>
                    );
                  }
                  if (cs === "open") {
                    return (
                      <>
                        <KV k="状態" v="未クローズ" />
                        <KV k="不足" v={missing.length === 0 ? "なし(クローズ可能)" : missing.join("、")} />
                      </>
                    );
                  }
                  return <KV k="状態" v="-" />;
                })()}
                {closure?.["closure_note"] ? <KV k="メモ" v={String(closure["closure_note"])} /> : null}
              </Section>
            )}

            <Section title="承認情報">
              <KV k="主任承認" v={(detail["chief_approved_by_name"] as string) ?? "-"} />
              <KV k="園長承認" v={(detail["approved_by_name"] as string) ?? "-"} />
            </Section>

            <div className="mt-6 flex flex-wrap justify-end gap-2 border-t border-slate-100 pt-4">
              {s === "draft" && (
                <>
                  <button disabled={busy} onClick={onEdit} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">編集</button>
                  <button disabled={busy} onClick={onSubmit} className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">申請する</button>
                </>
              )}
              {s === "submitted" && (
                <>
                  <button disabled={busy} onClick={onReject} className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">差し戻し</button>
                  <button disabled={busy} onClick={onChiefApprove} className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">主任承認</button>
                </>
              )}
              {s === "chief_approved" && (
                <>
                  <button disabled={busy} onClick={onReject} className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">差し戻し</button>
                  <button disabled={busy} onClick={onApprove} className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">園長承認</button>
                </>
              )}
              {s === "approved" && (
                <button disabled={busy} onClick={onCancel} className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">承認取消</button>
              )}
              {rt !== "hiyari" && s !== "draft" && closure?.["closure_status"] === "open" && (
                <button
                  disabled={busy || closure?.["is_ready"] !== true}
                  onClick={onCloseReport}
                  className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
                  title={closure?.["is_ready"] === true ? "" : "クローズ条件が未充足です"}
                >
                  保護者対応クローズ
                </button>
              )}
              {rt !== "hiyari" && s !== "draft" && closure?.["closure_status"] === "closed" && (
                <button disabled={busy} onClick={onReopen} className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">クローズ解除</button>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-4">
      <h3 className="mb-2 text-sm font-bold text-emerald-700">{title}</h3>
      {children}
    </div>
  );
}
function KV({ k, v }: { k: string; v: string }) {
  return (
    <div className="mb-1 flex text-sm">
      <div className="w-28 shrink-0 text-slate-400">{k}</div>
      <div className="flex-1">{v || "-"}</div>
    </div>
  );
}
function LogLine({ head, body }: { head: string; body: string }) {
  return (
    <div className="mb-1.5 rounded-lg bg-slate-50 p-2 text-sm">
      <div className="text-xs font-semibold text-slate-500">{head}</div>
      <div>{body}</div>
    </div>
  );
}

function LookupManager({ onClose }: { onClose: () => void }) {
  const [kind, setKind] = useState<string>("place");
  const [options, setOptions] = useState<LookupOption[]>([]);
  const [newLabel, setNewLabel] = useState("");
  const [busy, setBusy] = useState(false);
  const [token, setToken] = useState(0);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_incident_lookup_options", { p_kind: kind }).then(({ data }) => {
      setOptions((data ?? []) as LookupOption[]);
    });
  }, [kind, token]);

  async function add() {
    if (!newLabel.trim()) return;
    setBusy(true);
    const supabase = createClient();
    const nextOrder = options.length === 0 ? 10 : Math.max(...options.map((o) => o.sort_order)) + 10;
    const { error } = await supabase.rpc("upsert_incident_lookup_option", {
      p_id: null,
      p_kind: kind,
      p_label: newLabel.trim(),
      p_sort_order: nextOrder,
    });
    setBusy(false);
    if (error) { alert(error.message); return; }
    setNewLabel("");
    setToken((t) => t + 1);
  }

  async function deactivate(id: string) {
    if (!window.confirm("この選択肢を無効化しますか?(既存の記録は保持されます)")) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("set_incident_lookup_option_active", { p_id: id, p_active: false });
    if (error) { alert(error.message); return; }
    setToken((t) => t + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30" onClick={onClose}>
      <div className="max-h-[80vh] w-full max-w-lg overflow-y-auto rounded-2xl bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-base font-bold text-slate-800">ルックアップ管理(管理者以上)</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">✕</button>
        </div>
        <div className="mb-4 flex flex-wrap gap-1">
          {LOOKUP_KINDS.map((k) => (
            <button
              key={k.kind}
              onClick={() => setKind(k.kind)}
              className={`rounded-lg px-3 py-1 text-sm ${kind === k.kind ? "bg-sky-600 text-white" : "bg-slate-100 text-slate-600"}`}
            >
              {k.label}
            </button>
          ))}
        </div>
        <div className="mb-3 flex gap-2">
          <input
            value={newLabel}
            onChange={(e) => setNewLabel(e.target.value)}
            placeholder="新しい選択肢を追加"
            className="flex-1 rounded-lg border border-slate-300 px-3 py-1.5 text-sm"
          />
          <button disabled={busy} onClick={add} className="rounded-lg bg-emerald-600 px-4 py-1.5 text-sm font-semibold text-white disabled:opacity-50">追加</button>
        </div>
        <ul className="divide-y divide-slate-100">
          {options.map((o) => (
            <li key={o.id} className="flex items-center justify-between py-2 text-sm">
              <span>{o.label}</span>
              <button onClick={() => void deactivate(o.id)} className="text-xs text-red-500 hover:underline">無効化</button>
            </li>
          ))}
          {options.length === 0 && <li className="py-4 text-center text-sm text-slate-400">選択肢がありません</li>}
        </ul>
      </div>
    </div>
  );
}

// ---- 新規作成/下書き編集フォーム ----
type MedicalForm = {
  institution: string;
  doctor_name: string;
  department_id: string;
  exam_ids: string[];
  treatment_ids: string[];
  exam_detail: string;
  doctor_instruction: string;
  prescription_present: boolean;
  prescription_ids: string[];
  prescription_detail: string;
  treatment_period: string;
};
function emptyMedical(): MedicalForm {
  return {
    institution: "", doctor_name: "", department_id: "", exam_ids: [], treatment_ids: [],
    exam_detail: "", doctor_instruction: "", prescription_present: false,
    prescription_ids: [], prescription_detail: "", treatment_period: "",
  };
}
type ProgressForm = { logged_at: string; kind: string; text: string };
type GuardianForm = { contacted_at: string; contact_book_written: boolean; reaction_kind: string; text: string };
type ChildRow = { id: string; name: string; class_name: string | null };

function nowLocal(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}
function todayStr(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function IncidentFormDrawer({
  officeId,
  reportId,
  onClose,
  onSaved,
}: {
  officeId: string;
  reportId: string | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [options, setOptions] = useState<Record<string, LookupOption[]>>({});
  const [children, setChildren] = useState<ChildRow[]>([]);
  const [classNames, setClassNames] = useState<string[]>([]); // 年齢順の全クラス
  const [childQuery, setChildQuery] = useState("");
  const [childClassFilter, setChildClassFilter] = useState("");

  const [reportType, setReportType] = useState("hiyari");
  const [occurredOn, setOccurredOn] = useState(todayStr());
  const [occurredAt, setOccurredAt] = useState("10:00");
  const [placeId, setPlaceId] = useState("");
  const [placeOther, setPlaceOther] = useState("");
  const [sWhen, setSWhen] = useState("");
  const [sWhere, setSWhere] = useState("");
  const [sWhat, setSWhat] = useState("");
  const [sResult, setSResult] = useState("");
  const [hoiku, setHoiku] = useState("");
  const [jido, setJido] = useState("");
  const [witness, setWitness] = useState("");
  const [cChild, setCChild] = useState("");
  const [cEnv, setCEnv] = useState("");
  const [cObj, setCObj] = useState("");
  const [cRules, setCRules] = useState("");
  const [injuryId, setInjuryId] = useState("");
  const [injuryDetail, setInjuryDetail] = useState("");
  const [firstAid, setFirstAid] = useState("");
  const [prevention, setPrevention] = useState("");
  const [note, setNote] = useState("");
  const [selChildren, setSelChildren] = useState<string[]>([]);
  const [progress, setProgress] = useState<ProgressForm[]>([]);
  const [guardians, setGuardians] = useState<GuardianForm[]>([]);
  const [medicals, setMedicals] = useState<MedicalForm[]>([]);

  const isAccident = reportType === "minor" || reportType === "hospital";
  const isHospital = reportType === "hospital";
  const opt = (kind: string): LookupOption[] => options[kind] ?? [];

  function changeType(k: string) {
    setReportType(k);
    // 事故報告は経過・保護者連絡が必須のため、最初から1行表示する。
    if (k === "minor" || k === "hospital") {
      setProgress((p) => (p.length === 0 ? [{ logged_at: nowLocal(), kind: "ok", text: "" }] : p));
      setGuardians((g) =>
        g.length === 0 ? [{ contacted_at: nowLocal(), contact_book_written: true, reaction_kind: "understood", text: "" }] : g,
      );
    }
  }

  function prefill(d: IncidentDetail) {
    const r = (d["report"] as Record<string, unknown>) ?? {};
    const str = (k: string) => (r[k] == null ? "" : String(r[k]));
    setReportType(str("report_type") || "hiyari");
    if (r["occurred_on"]) setOccurredOn(String(r["occurred_on"]).slice(0, 10));
    if (r["occurred_at"]) setOccurredAt(String(r["occurred_at"]).slice(0, 5));
    setPlaceId(str("place_option_id"));
    setPlaceOther(str("place_other"));
    setSWhen(str("situation_when"));
    setSWhere(str("situation_where"));
    setSWhat(str("situation_what"));
    setSResult(str("situation_result"));
    const counts = (r["staff_counts"] as Record<string, unknown>) ?? {};
    setHoiku(counts["hoiku"] != null ? String(counts["hoiku"]) : "");
    setJido(counts["jido"] != null ? String(counts["jido"]) : "");
    setWitness(counts["witness"] != null ? String(counts["witness"]) : "");
    const causes = (r["causes"] as Record<string, unknown>) ?? {};
    setCChild((causes["child_behavior"] as string) ?? "");
    setCEnv((causes["environment"] as string) ?? "");
    setCObj((causes["objects"] as string) ?? "");
    setCRules((causes["care_rules"] as string) ?? "");
    setInjuryId(str("injury_site_option_id"));
    setInjuryDetail(str("injury_detail"));
    setFirstAid(str("first_aid"));
    setPrevention(str("prevention_text"));
    setNote(str("note_text"));
    setSelChildren(((d["children"] as Record<string, unknown>[]) ?? []).map((c) => String(c["child_id"])));
    setProgress(((d["progress_logs"] as Record<string, unknown>[]) ?? []).map((p) => ({
      logged_at: p["logged_at"] ? new Date(String(p["logged_at"])).toISOString().slice(0, 16) : nowLocal(),
      kind: String(p["report_kind"] ?? "ok"),
      text: String(p["report_text"] ?? ""),
    })));
    setGuardians(((d["guardian_contacts"] as Record<string, unknown>[]) ?? []).map((g) => ({
      contacted_at: g["contacted_at"] ? new Date(String(g["contacted_at"])).toISOString().slice(0, 16) : nowLocal(),
      contact_book_written: g["contact_book_written"] === true,
      reaction_kind: String(g["reaction_kind"] ?? "understood"),
      text: String(g["reaction_text"] ?? ""),
    })));
    setMedicals(((d["medical_visits"] as Record<string, unknown>[]) ?? []).map((m) => ({
      institution: String(m["medical_institution"] ?? ""),
      doctor_name: String(m["doctor_name"] ?? ""),
      department_id: String(m["department_option_id"] ?? ""),
      exam_ids: ((m["exam_option_ids"] as unknown[]) ?? []).map(String),
      treatment_ids: ((m["treatment_option_ids"] as unknown[]) ?? []).map(String),
      exam_detail: String(m["exam_detail"] ?? ""),
      doctor_instruction: String(m["doctor_instruction"] ?? ""),
      prescription_present: m["prescription_present"] === true,
      prescription_ids: ((m["prescription_option_ids"] as unknown[]) ?? []).map(String),
      prescription_detail: String(m["prescription_detail"] ?? ""),
      treatment_period: String(m["treatment_period"] ?? ""),
    })));
  }

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const supabase = createClient();
      const [{ data: optData }, { data: childData }, { data: classData }] = await Promise.all([
        supabase.rpc("fetch_incident_lookup_options", { p_kind: null }),
        supabase.rpc("fetch_children_for_office_master", { p_office_id: officeId }),
        supabase.rpc("fetch_childcare_classes", { p_office_id: officeId }),
      ]);
      const byKind: Record<string, LookupOption[]> = {};
      for (const o of (optData ?? []) as LookupOption[]) (byKind[o.kind] ??= []).push(o);
      const rows: ChildRow[] = ((childData ?? []) as Record<string, unknown>[])
        .filter((c) => c["enrollment_status"] !== "退園済み")
        .map((c) => ({
          id: String(c["child_id"]),
          name: String(c["display_name"] ?? ""),
          class_name: (c["class_name"] as string) ?? null,
        }));
      // fetch_childcare_classes は age_group 順(はな→そら→…→にじ)
      const classes = ((classData ?? []) as Record<string, unknown>[]).map((c) => String(c["class_name"]));
      if (reportId) {
        const { data: d } = await supabase.rpc("fetch_incident_report_detail", { p_id: reportId });
        if (d && !cancelled) prefill(d as IncidentDetail);
      }
      if (!cancelled) {
        setOptions(byKind);
        setChildren(rows);
        setClassNames(classes);
        setLoading(false);
      }
    }
    void load();
    return () => { cancelled = true; };
  }, [officeId, reportId]);

  function buildPayload(): Record<string, unknown> {
    const nz = (s: string) => (s.trim() === "" ? null : s.trim());
    const ni = (s: string) => (s.trim() === "" ? null : Number(s));
    return {
      office_id: officeId,
      report_type: reportType,
      occurred_on: occurredOn,
      occurred_at: occurredAt || null,
      place_option_id: placeId || null,
      place_other: nz(placeOther),
      situation_when: nz(sWhen),
      situation_where: nz(sWhere),
      situation_what: nz(sWhat),
      situation_result: nz(sResult),
      staff_counts: { hoiku: ni(hoiku), jido: ni(jido), witness: ni(witness) },
      causes: { child_behavior: nz(cChild), environment: nz(cEnv), objects: nz(cObj), care_rules: nz(cRules) },
      injury_site_option_id: isAccident ? injuryId || null : null,
      injury_detail: isAccident ? nz(injuryDetail) : null,
      first_aid: isAccident ? nz(firstAid) : null,
      prevention_text: nz(prevention),
      note_text: nz(note),
      children: selChildren.map((id) => ({ child_id: id })),
      progress_logs: progress.map((p) => ({
        logged_at: new Date(p.logged_at).toISOString(),
        report_kind: p.kind,
        report_text: p.text,
      })),
      guardian_contacts: guardians.map((g) => ({
        contacted_at: new Date(g.contacted_at).toISOString(),
        contact_book_written: g.contact_book_written,
        reaction_kind: g.reaction_kind,
        reaction_text: g.text,
      })),
      medical_visits: isHospital
        ? medicals.map((m) => ({
            medical_institution: nz(m.institution),
            doctor_name: nz(m.doctor_name),
            department_option_id: m.department_id || null,
            exam_option_ids: m.exam_ids,
            treatment_option_ids: m.treatment_ids,
            exam_detail: nz(m.exam_detail),
            doctor_instruction: m.doctor_instruction || null,
            prescription_present: m.prescription_present,
            prescription_option_ids: m.prescription_ids,
            prescription_detail: nz(m.prescription_detail),
            treatment_period: nz(m.treatment_period),
          }))
        : [],
    };
  }

  async function save(): Promise<string | null> {
    setBusy(true);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("save_incident_report", { p_id: reportId, p_payload: buildPayload() });
    setBusy(false);
    if (error) {
      alert(`保存に失敗しました: ${error.message}`);
      return null;
    }
    return data as string;
  }

  async function saveDraft() {
    const id = await save();
    if (id) { alert("下書きを保存しました"); onSaved(); }
  }
  async function submit() {
    const id = await save();
    if (!id) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("submit_incident_report", { p_id: id });
    if (error) {
      const m = error.message;
      alert(m.includes("必須項目") ? m.slice(m.indexOf("必須項目")) : `申請できません: ${m}`);
      return;
    }
    alert("申請しました");
    onSaved();
  }

  const selChildNames = children.filter((c) => selChildren.includes(c.id));
  const childClasses = classNames; // 年齢順の全クラス(在籍児がいないクラスも含む)
  const filteredChildren = children.filter(
    (c) => (childQuery ? c.name.includes(childQuery) : true) && (childClassFilter ? c.class_name === childClassFilter : true),
  );

  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/30" onClick={onClose}>
      <div className="h-full w-full max-w-2xl overflow-y-auto bg-white p-6 shadow-xl" onClick={(e) => e.stopPropagation()}>
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-base font-bold text-slate-800">{reportId ? "報告書の編集" : "報告書の作成"}</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">✕</button>
        </div>
        {loading ? (
          <p className="text-slate-400">読み込み中…</p>
        ) : (
          <>
            <FSection title="1. 基本情報" />
            <div className="mb-3 space-y-1">
              {Object.entries(REPORT_TYPES).map(([k, v]) => (
                <label key={k} className="flex items-center gap-2 text-sm">
                  <input type="radio" name="rt" checked={reportType === k} onChange={() => changeType(k)} />
                  {v}
                </label>
              ))}
            </div>
            <div className="mb-3 flex gap-3">
              <label className="flex-1 text-sm">発生日
                <input type="date" value={occurredOn} onChange={(e) => setOccurredOn(e.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-2 py-1.5" />
              </label>
              <label className="flex-1 text-sm">発生時間
                <input type="time" value={occurredAt} onChange={(e) => setOccurredAt(e.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-2 py-1.5" />
              </label>
            </div>
            <FSelect label="発生場所" value={placeId} onChange={setPlaceId} opts={opt("place")} />
            <FText label="その他の場所(任意)" value={placeOther} onChange={setPlaceOther} />
            <div className="mb-3">
              <div className="mb-1 text-sm text-slate-600">対象園児</div>
              <div className="mb-2 flex flex-wrap gap-1">
                {selChildNames.length === 0 && <span className="text-xs text-slate-400">未選択(職員のみの事案は空でも可)</span>}
                {selChildNames.map((c) => (
                  <span key={c.id} className="flex items-center gap-1 rounded-full bg-sky-100 px-2 py-0.5 text-xs text-sky-700">
                    {c.name}
                    <button onClick={() => setSelChildren((prev) => prev.filter((x) => x !== c.id))} className="text-sky-400">✕</button>
                  </span>
                ))}
              </div>
              <input value={childQuery} onChange={(e) => setChildQuery(e.target.value)} placeholder="氏名で検索" className="mb-1 w-full rounded-lg border border-slate-300 px-2 py-1 text-sm" />
              {childClasses.length > 0 && (
                <div className="mb-1 flex flex-wrap gap-1">
                  <button
                    type="button"
                    onClick={() => setChildClassFilter("")}
                    className={`rounded-full px-2 py-0.5 text-xs ${childClassFilter === "" ? "bg-sky-600 text-white" : "bg-slate-100 text-slate-600"}`}
                  >
                    全クラス
                  </button>
                  {childClasses.map((cn) => (
                    <button
                      key={cn}
                      type="button"
                      onClick={() => setChildClassFilter(cn)}
                      className={`rounded-full px-2 py-0.5 text-xs ${childClassFilter === cn ? "bg-sky-600 text-white" : "bg-slate-100 text-slate-600"}`}
                    >
                      {cn}
                    </button>
                  ))}
                </div>
              )}
              <div className="max-h-40 overflow-y-auto rounded-lg border border-slate-200">
                {filteredChildren.map((c) => (
                  <label key={c.id} className="flex items-center gap-2 px-2 py-1 text-sm hover:bg-slate-50">
                    <input
                      type="checkbox"
                      checked={selChildren.includes(c.id)}
                      onChange={(e) =>
                        setSelChildren((prev) => (e.target.checked ? [...prev, c.id] : prev.filter((x) => x !== c.id)))
                      }
                    />
                    {c.name}
                    {c.class_name && <span className="text-xs text-slate-400">({c.class_name})</span>}
                  </label>
                ))}
              </div>
            </div>

            <FSection title="2. 発生状況" />
            <FArea label="いつ" value={sWhen} onChange={setSWhen} />
            <FArea label="どこで" value={sWhere} onChange={setSWhere} />
            <FArea label="何をしたとき" value={sWhat} onChange={setSWhat} />
            <FArea label="どうなった" value={sResult} onChange={setSResult} />

            <FSection title="3. 現場の人員" />
            <div className="mb-3 flex gap-3">
              <FNum label="保育士(名)" value={hoiku} onChange={setHoiku} />
              <FNum label="園児(名)" value={jido} onChange={setJido} />
              <FNum label="目撃者(名)" value={witness} onChange={setWitness} />
            </div>

            <FSection title="4. 原因・問題点(該当項目のみ)" />
            <FArea label="子どもの状況・行動" value={cChild} onChange={setCChild} />
            <FArea label="環境・設備" value={cEnv} onChange={setCEnv} />
            <FArea label="物・遊具" value={cObj} onChange={setCObj} />
            <FArea label="保育・対応・ルール" value={cRules} onChange={setCRules} />

            {isAccident && (
              <>
                <FSection title="5. 発生後の対応" />
                <FSelect label="受傷部位" value={injuryId} onChange={setInjuryId} opts={opt("injury_site")} />
                <FArea label="受傷内容" value={injuryDetail} onChange={setInjuryDetail} />
                <FArea label="応急処置" value={firstAid} onChange={setFirstAid} />
              </>
            )}

            <FSectionAdd title="6. 経過と観察記録" onAdd={() => setProgress((p) => [...p, { logged_at: nowLocal(), kind: "ok", text: "" }])} />
            {progress.map((p, i) => (
              <div key={i} className="mb-2 rounded-lg border border-slate-200 p-2">
                <div className="mb-1 flex items-center gap-2">
                  <input type="datetime-local" value={p.logged_at} onChange={(e) => setProgress((prev) => prev.map((x, j) => (j === i ? { ...x, logged_at: e.target.value } : x)))} className="rounded border border-slate-300 px-2 py-1 text-sm" />
                  <button onClick={() => setProgress((prev) => prev.filter((_, j) => j !== i))} className="ml-auto text-xs text-red-500">削除</button>
                </div>
                <div className="mb-1 flex gap-3">
                  {Object.entries(PROGRESS_KINDS).map(([k, v]) => (
                    <label key={k} className="flex items-center gap-1 text-sm">
                      <input type="radio" checked={p.kind === k} onChange={() => setProgress((prev) => prev.map((x, j) => (j === i ? { ...x, kind: k } : x)))} />
                      {v}
                    </label>
                  ))}
                </div>
                <input value={p.text} onChange={(e) => setProgress((prev) => prev.map((x, j) => (j === i ? { ...x, text: e.target.value } : x)))} placeholder="報告内容(その他の場合)" className="w-full rounded border border-slate-300 px-2 py-1 text-sm" />
              </div>
            ))}

            <FSectionAdd title="7. 保護者連絡" onAdd={() => setGuardians((g) => [...g, { contacted_at: nowLocal(), contact_book_written: false, reaction_kind: "understood", text: "" }])} />
            {guardians.map((g, i) => (
              <div key={i} className="mb-2 rounded-lg border border-slate-200 p-2">
                <div className="mb-1 flex items-center gap-2">
                  <input type="datetime-local" value={g.contacted_at} onChange={(e) => setGuardians((prev) => prev.map((x, j) => (j === i ? { ...x, contacted_at: e.target.value } : x)))} className="rounded border border-slate-300 px-2 py-1 text-sm" />
                  <button onClick={() => setGuardians((prev) => prev.filter((_, j) => j !== i))} className="ml-auto text-xs text-red-500">削除</button>
                </div>
                <div className="mb-1 flex items-center gap-4 text-sm">
                  <span className="text-slate-500">報告方法</span>
                  <label className="flex items-center gap-1">
                    <input type="radio" checked={g.contact_book_written === true} onChange={() => setGuardians((prev) => prev.map((x, j) => (j === i ? { ...x, contact_book_written: true } : x)))} />
                    連絡帳に記載
                  </label>
                  <label className="flex items-center gap-1">
                    <input type="radio" checked={g.contact_book_written === false} onChange={() => setGuardians((prev) => prev.map((x, j) => (j === i ? { ...x, contact_book_written: false } : x)))} />
                    口頭で直接
                  </label>
                </div>
                <div className="mb-1 flex flex-col gap-1">
                  {Object.entries(REACTION_KINDS).map(([k, v]) => (
                    <label key={k} className="flex items-center gap-1 text-sm">
                      <input type="radio" checked={g.reaction_kind === k} onChange={() => setGuardians((prev) => prev.map((x, j) => (j === i ? { ...x, reaction_kind: k } : x)))} />
                      {v}
                    </label>
                  ))}
                </div>
                <input value={g.text} onChange={(e) => setGuardians((prev) => prev.map((x, j) => (j === i ? { ...x, text: e.target.value } : x)))} placeholder="相手の反応(その他の場合)" className="w-full rounded border border-slate-300 px-2 py-1 text-sm" />
              </div>
            ))}

            {isHospital && (
              <>
                <FSectionAdd title="受診記録" onAdd={() => setMedicals((m) => [...m, emptyMedical()])} />
                {medicals.map((m, i) => (
                  <div key={i} className="mb-2 rounded-lg border border-red-100 bg-red-50/40 p-2">
                    <div className="mb-1 flex justify-end">
                      <button onClick={() => setMedicals((prev) => prev.filter((_, j) => j !== i))} className="text-xs text-red-500">削除</button>
                    </div>
                    <FText label="医療機関名" value={m.institution} onChange={(v) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, institution: v } : x)))} />
                    <FText label="医師名" value={m.doctor_name} onChange={(v) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, doctor_name: v } : x)))} />
                    <FSelect label="診察科" value={m.department_id} onChange={(v) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, department_id: v } : x)))} opts={opt("med_department")} />
                    <FChips label="受診内容" opts={opt("med_exam")} selected={m.exam_ids} onToggle={(id) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, exam_ids: toggle(x.exam_ids, id) } : x)))} />
                    <FChips label="処置内容" opts={opt("med_treatment")} selected={m.treatment_ids} onToggle={(id) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, treatment_ids: toggle(x.treatment_ids, id) } : x)))} />
                    <FArea label="診察・処置の内容(補足)" value={m.exam_detail} onChange={(v) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, exam_detail: v } : x)))} />
                    <div className="mb-1 flex gap-3">
                      {Object.entries(DOCTOR_INSTRUCTIONS).map(([k, v]) => (
                        <label key={k} className="flex items-center gap-1 text-sm">
                          <input type="radio" checked={m.doctor_instruction === k} onChange={() => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, doctor_instruction: k } : x)))} />
                          {v}
                        </label>
                      ))}
                    </div>
                    <label className="mb-1 flex items-center gap-1 text-sm">
                      <input type="checkbox" checked={m.prescription_present} onChange={(e) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, prescription_present: e.target.checked } : x)))} />
                      処方薬あり
                    </label>
                    {m.prescription_present && (
                      <>
                        <FChips label="処方薬" opts={opt("med_prescription")} selected={m.prescription_ids} onToggle={(id) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, prescription_ids: toggle(x.prescription_ids, id) } : x)))} />
                        <FText label="処方薬の内容(補足)" value={m.prescription_detail} onChange={(v) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, prescription_detail: v } : x)))} />
                      </>
                    )}
                    <FText label="治療期間" value={m.treatment_period} onChange={(v) => setMedicals((prev) => prev.map((x, j) => (j === i ? { ...x, treatment_period: v } : x)))} />
                  </div>
                ))}
              </>
            )}

            <FSection title="8. 再発防止" />
            <FArea label="再発防止に向けて" value={prevention} onChange={setPrevention} />
            <FSection title="その他(任意)" />
            <FArea label="その他" value={note} onChange={setNote} />

            <div className="mt-6 flex justify-end gap-2 border-t border-slate-100 pt-4">
              <button disabled={busy} onClick={saveDraft} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 disabled:opacity-50">下書き保存</button>
              <button disabled={busy} onClick={submit} className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">申請する</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

function toggle(arr: string[], id: string): string[] {
  return arr.includes(id) ? arr.filter((x) => x !== id) : [...arr, id];
}
function FSection({ title }: { title: string }) {
  return <h4 className="mb-2 mt-4 text-sm font-bold text-emerald-700">{title}</h4>;
}
function FSectionAdd({ title, onAdd }: { title: string; onAdd: () => void }) {
  return (
    <div className="mb-2 mt-4 flex items-center justify-between">
      <h4 className="text-sm font-bold text-emerald-700">{title}</h4>
      <button onClick={onAdd} className="rounded-lg border border-slate-300 px-2 py-1 text-xs text-slate-600 hover:bg-slate-50">+ 追加</button>
    </div>
  );
}
function FText({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <label className="mb-2 block text-sm">
      <span className="text-slate-600">{label}</span>
      <input value={value} onChange={(e) => onChange(e.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-2 py-1.5" />
    </label>
  );
}
function FArea({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <label className="mb-2 block text-sm">
      <span className="text-slate-600">{label}</span>
      <textarea value={value} onChange={(e) => onChange(e.target.value)} rows={2} className="mt-1 w-full rounded-lg border border-slate-300 px-2 py-1.5" />
    </label>
  );
}
function FNum({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <label className="flex-1 text-sm">
      <span className="text-slate-600">{label}</span>
      <input type="number" value={value} onChange={(e) => onChange(e.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-2 py-1.5" />
    </label>
  );
}
function FSelect({ label, value, onChange, opts }: { label: string; value: string; onChange: (v: string) => void; opts: LookupOption[] }) {
  return (
    <label className="mb-2 block text-sm">
      <span className="text-slate-600">{label}</span>
      <select value={value} onChange={(e) => onChange(e.target.value)} className="mt-1 w-full rounded-lg border border-slate-300 px-2 py-1.5">
        <option value="">未選択</option>
        {opts.map((o) => (
          <option key={o.id} value={o.id}>{o.label}</option>
        ))}
      </select>
    </label>
  );
}
function FChips({ label, opts, selected, onToggle }: { label: string; opts: LookupOption[]; selected: string[]; onToggle: (id: string) => void }) {
  return (
    <div className="mb-2">
      <div className="mb-1 text-xs text-slate-500">{label}</div>
      <div className="flex flex-wrap gap-1">
        {opts.map((o) => (
          <button
            key={o.id}
            onClick={() => onToggle(o.id)}
            className={`rounded-full px-2 py-0.5 text-xs ${selected.includes(o.id) ? "bg-sky-600 text-white" : "bg-slate-100 text-slate-600"}`}
          >
            {o.label}
          </button>
        ))}
      </div>
    </div>
  );
}

export default function ChildcareIncidentsPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareIncidentsPageContent />
    </Suspense>
  );
}
