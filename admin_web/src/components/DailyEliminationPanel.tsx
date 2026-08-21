"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { currentDate } from "@/lib/datetime";

type EliminationRow = {
  child_id: string;
  child_name: string;
  class_name: string | null;
  handling: string; // 'hold' / 'bento' / 'elimination'
  elimination_targets: string[] | null;
  consent_status: string | null; // 'ok' / 'waived' / 'pending' / null (275)
};

type Summary = {
  common_elimination_allergens: string[];
  elimination_count: number;
  bento_count: number;
  hold_count: number;
};

const HANDLING_LABELS: Record<string, string> = {
  elimination: "共通除去食",
  bento: "弁当持参",
  hold: "給食開始保留",
};

/// 本日の共通除去食(M6 Phase 6・232/233)。施設×提供日の除去対応が必要な児と、
/// 共通除去食で使わないアレルゲン集合を表示する。誤配膳防止のため除去対象を最上部に強調。
export function DailyEliminationPanel({ officeId }: { officeId: string }) {
  const [date, setDate] = useState(currentDate());
  const [summary, setSummary] = useState<Summary | null>(null);
  const [rows, setRows] = useState<EliminationRow[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!officeId) return;
    const supabase = createClient();
    supabase
      .rpc("fetch_daily_elimination_summary", { p_office_id: officeId, p_business_date: date })
      .then(({ data, error: err }) => {
        if (err) {
          setError(err.message);
          return;
        }
        setSummary((Array.isArray(data) ? data[0] : data) as Summary);
      });
    supabase
      .rpc("fetch_daily_elimination_for_office", { p_office_id: officeId, p_business_date: date })
      .then(({ data, error: err }) => {
        if (!err) setRows((data ?? []) as EliminationRow[]);
      });
  }, [officeId, date]);

  const elimination = rows.filter((r) => r.handling === "elimination");
  const bento = rows.filter((r) => r.handling === "bento");
  const hold = rows.filter((r) => r.handling === "hold");
  const allergens = summary?.common_elimination_allergens ?? [];

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-bold text-slate-700">本日の共通除去食(給食の安全確認)</h3>
        <label className="flex items-center gap-2 text-xs font-medium text-slate-500">
          提供日:
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="rounded-lg border border-slate-300 px-2 py-1 text-sm focus:border-sky-400 focus:outline-none"
          />
        </label>
      </div>
      {error && <p className="text-sm font-medium text-red-500">{error}</p>}

      {/* 共通除去対象アレルゲン集合(最上部・強調) */}
      <div className="rounded-2xl border-2 border-violet-300 bg-violet-50 p-4">
        <p className="text-xs font-bold text-violet-700">この日の給食で使わないアレルゲン(共通除去)</p>
        {allergens.length > 0 ? (
          <div className="mt-2 flex flex-wrap gap-2">
            {allergens.map((a) => (
              <span key={a} className="rounded-lg bg-violet-600 px-3 py-1 text-sm font-bold text-white">
                {a}
              </span>
            ))}
          </div>
        ) : (
          <p className="mt-1 text-sm text-slate-500">除去対象はありません(通常の給食で提供できます)</p>
        )}
        <p className="mt-2 text-xs text-slate-500">
          共通除去食 {summary?.elimination_count ?? 0}名 / 弁当持参 {summary?.bento_count ?? 0}名 / 給食開始保留{" "}
          {summary?.hold_count ?? 0}名
        </p>
      </div>

      {/* 対象児カード(誤配膳防止) */}
      {elimination.length > 0 && (
        <div>
          <p className="mb-1 text-xs font-bold text-violet-700">共通除去食の対象児</p>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            {elimination.map((r) => (
              <div key={r.child_id} className="rounded-xl border border-violet-200 bg-white p-3">
                <p className="text-sm font-bold text-slate-800">
                  {r.child_name}
                  {r.class_name && <span className="ml-2 text-xs font-normal text-slate-400">{r.class_name}</span>}
                </p>
                <p className="mt-1 text-sm font-semibold text-violet-700">除去: {(r.elimination_targets ?? []).join("・")}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {bento.length > 0 && (
        <div>
          <p className="mb-1 text-xs font-bold text-amber-700">弁当持参の対象児</p>
          <div className="flex flex-wrap gap-2">
            {bento.map((r) => (
              <span key={r.child_id} className="rounded-lg bg-amber-50 px-3 py-1 text-sm font-semibold text-amber-800">
                {r.child_name}
                {r.class_name && `(${r.class_name})`}
                {r.consent_status === "pending" && (
                  <span className="ml-1 rounded bg-amber-600 px-1.5 py-0.5 text-xs font-bold text-white">同意待ち</span>
                )}
              </span>
            ))}
          </div>
          <p className="mt-1 text-xs text-slate-400">
            「同意待ち」= 除去食の給食会議・保護者同意がまだのため、当面は弁当持参です(同意後に除去食提供へ)。
          </p>
        </div>
      )}

      {hold.length > 0 && (
        <div>
          <p className="mb-1 text-xs font-bold text-red-600">給食開始保留の対象児</p>
          <div className="flex flex-wrap gap-2">
            {hold.map((r) => (
              <span key={r.child_id} className="rounded-lg bg-red-50 px-3 py-1 text-sm font-semibold text-red-700">
                {r.child_name}
                {r.class_name && `(${r.class_name})`}
              </span>
            ))}
          </div>
        </div>
      )}

      {rows.length === 0 && !error && (
        <p className="rounded-xl bg-white p-4 text-sm text-slate-400 shadow-sm">
          この日は除去対応・弁当持参・保留の対象児はいません
        </p>
      )}
    </section>
  );
}
