"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { currentDate } from "@/lib/datetime";

type QueueRow = {
  request_id: string;
  child_id: string;
  child_name: string;
  class_name: string | null;
  item_id: string;
  item_name: string;
  domain_code: string;
  age_band_code: string;
  source: string;
  note: string | null;
  requested_by_name: string | null;
  requested_at: string;
};

const DOMAIN_LABEL: Record<string, string> = {
  health: "健康",
  relations: "人間関係",
  environment: "環境",
  language: "言葉",
  expression: "表現",
};

/// 達成申請の承認キュー(§9.3・239/240)。主任以上向け。自施設の承認待ちを一覧し、
/// 承認(達成確定)/差し戻しを一覧から実行する。承認・差戻しはRPCがサーバー側で再認可・再検証する。
export function DevelopmentApprovalPanel({ officeId }: { officeId: string }) {
  const [rows, setRows] = useState<QueueRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [achievedDate, setAchievedDate] = useState(currentDate());

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    if (!officeId) return;
    setIsLoading(true);
    setError(null);
    const supabase = createClient();
    supabase.rpc("fetch_development_approval_queue", { p_office_id: officeId }).then(({ data, error: err }) => {
      setIsLoading(false);
      if (err) {
        // 主任未満は not authorized。パネル自体を出さない運用なので静かに空表示。
        setError(err.message.includes("not authorized") ? null : err.message);
        setRows([]);
        return;
      }
      setRows((data ?? []) as QueueRow[]);
    });
  }, [officeId, reloadToken]);

  async function decide(row: QueueRow, approve: boolean) {
    setBusy(row.request_id);
    setActionError(null);
    const note = approve ? null : window.prompt("差し戻しの理由(任意)") ?? null;
    const supabase = createClient();
    const { error: err } = await supabase.rpc("decide_development_achievement_request", {
      p_request_id: row.request_id,
      p_approve: approve,
      p_note: note,
      p_first_achieved_on: approve ? achievedDate : null,
      p_target_year_month: null,
    });
    setBusy(null);
    if (err) {
      setActionError(err.message);
      return;
    }
    reload();
  }

  if (!isLoading && rows.length === 0 && !error) return null;

  return (
    <section className="rounded-2xl border-2 border-amber-300 bg-amber-50 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-bold text-amber-900">発達記録・達成申請の承認待ち({rows.length}件)</h3>
        <label className="flex items-center gap-1 text-xs font-medium text-amber-800">
          達成日:
          <input
            type="date"
            value={achievedDate}
            onChange={(e) => setAchievedDate(e.target.value)}
            className="rounded-md border border-amber-300 bg-white px-2 py-1"
          />
        </label>
      </div>
      {error && <p className="mt-2 text-sm font-medium text-red-600">{error}</p>}
      {actionError && <p className="mt-2 text-sm font-medium text-red-600">{actionError}</p>}

      <div className="mt-3 space-y-2">
        {rows.map((r) => (
          <div key={r.request_id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-white p-3">
            <div className="min-w-0">
              <p className="text-sm font-semibold text-slate-800">
                {r.child_name}
                {r.class_name && <span className="ml-1 text-xs font-normal text-slate-400">{r.class_name}</span>}
              </p>
              <p className="text-sm text-slate-700">
                <span className="mr-1 rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-500">
                  {DOMAIN_LABEL[r.domain_code] ?? r.domain_code}
                </span>
                {r.item_name}
              </p>
              <p className="text-xs text-slate-400">
                申請: {r.requested_by_name ?? "不明"} / {new Date(r.requested_at).toLocaleString("ja-JP")}
                {r.source === "ai_candidate" && " / AI候補"}
                {r.note && ` / ${r.note}`}
              </p>
            </div>
            <div className="flex shrink-0 gap-2">
              <button
                onClick={() => decide(r, true)}
                disabled={busy === r.request_id}
                className="rounded-lg bg-emerald-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
              >
                承認
              </button>
              <button
                onClick={() => decide(r, false)}
                disabled={busy === r.request_id}
                className="rounded-lg border border-slate-300 px-4 py-1.5 text-xs font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-60"
              >
                差戻し
              </button>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
