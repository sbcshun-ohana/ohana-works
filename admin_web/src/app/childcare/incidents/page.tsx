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
  const [busy, setBusy] = useState(false);
  const [showLookups, setShowLookups] = useState(false);

  useEffect(() => {
    function begin() {
      if (!selectedOffice) return null;
      setIsLoading(true);
      setRowsError(null);
      return createClient();
    }
    const supabase = begin();
    if (!supabase) return;
    supabase
      .rpc("fetch_incident_reports", {
        p_office_id: selectedOffice,
        p_status: statusFilter || null,
        p_report_type: typeFilter || null,
      })
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRows((data ?? []) as IncidentRow[]);
      });
  }, [selectedOffice, statusFilter, typeFilter, reloadToken]);

  const openDetail = useCallback(async (id: string) => {
    setDetailId(id);
    setDetail(null);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("fetch_incident_report_detail", { p_id: id });
    if (!error) setDetail(data as IncidentDetail);
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
          <button
            onClick={() => setShowLookups(true)}
            className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            ルックアップ管理
          </button>
        </div>
        <p className="text-xs text-slate-400">報告書の作成は Ohana Kids(iPad)で行います。ここでは一覧・詳細確認・承認・差し戻しを行います。</p>

        <div className="flex gap-3">
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
                    {r.closure_status === "open" ? (
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
          busy={busy}
          onClose={() => { setDetailId(null); setDetail(null); }}
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
    </div>
  );
}

function DetailDrawer({
  detail,
  report,
  busy,
  onClose,
  onSubmit,
  onChiefApprove,
  onApprove,
  onReject,
  onCancel,
}: {
  detail: IncidentDetail | null;
  report: Record<string, unknown> | null;
  busy: boolean;
  onClose: () => void;
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
                    head={fmtDateTime(c["contacted_at"])}
                    body={`${REACTION_KINDS[String(c["reaction_kind"])] ?? ""}${c["contact_book_written"] ? "(連絡帳記入あり)" : ""}${c["reaction_text"] ? `  ${c["reaction_text"]}` : ""}`}
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

            <Section title="承認情報">
              <KV k="主任承認" v={(detail["chief_approved_by_name"] as string) ?? "-"} />
              <KV k="園長承認" v={(detail["approved_by_name"] as string) ?? "-"} />
            </Section>

            <div className="mt-6 flex flex-wrap justify-end gap-2 border-t border-slate-100 pt-4">
              {s === "draft" && (
                <button disabled={busy} onClick={onSubmit} className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">申請する</button>
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

export default function ChildcareIncidentsPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareIncidentsPageContent />
    </Suspense>
  );
}
