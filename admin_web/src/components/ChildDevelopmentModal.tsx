"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { currentDate } from "@/lib/datetime";

type Props = {
  childId: string;
  childName: string;
  officeId: string;
  isManager: boolean;
  onClose: () => void;
};

type Header = {
  child_name: string;
  class_name: string | null;
  birth_date: string | null;
  applicable_band: string | null;
};

type RecordRow = {
  item_id: string;
  age_band_code: string;
  domain_code: string;
  item_name: string;
  observation_point: string | null;
  display_order: number;
  is_achieved: boolean;
  achievement_id: string | null;
  first_achieved_on: string | null;
  method: string | null;
  approved_by_name: string | null;
  target_year_month: string | null;
  has_pending: boolean;
  request_id: string | null;
  requested_by_name: string | null;
  requested_at: string | null;
  request_note: string | null;
};

const AGE_BANDS: { code: string; label: string }[] = [
  { code: "M00_05", label: "0〜5か月" },
  { code: "M06_14", label: "6〜14か月" },
  { code: "M15_23", label: "15〜23か月" },
  { code: "AGE_2", label: "2歳児" },
  { code: "AGE_3", label: "3歳児" },
  { code: "AGE_4", label: "4歳児" },
  { code: "AGE_5", label: "5歳児" },
];
const BAND_LABEL: Record<string, string> = Object.fromEntries(AGE_BANDS.map((b) => [b.code, b.label]));

const DOMAINS: { code: string; label: string; className: string }[] = [
  { code: "health", label: "健康", className: "bg-rose-100 text-rose-700" },
  { code: "relations", label: "人間関係", className: "bg-amber-100 text-amber-700" },
  { code: "environment", label: "環境", className: "bg-emerald-100 text-emerald-700" },
  { code: "language", label: "言葉", className: "bg-sky-100 text-sky-700" },
  { code: "expression", label: "表現", className: "bg-violet-100 text-violet-700" },
];
const DOMAIN_MAP = Object.fromEntries(DOMAINS.map((d) => [d.code, d]));

const METHOD_LABEL: Record<string, string> = {
  manual_request: "申請承認",
  ai_request: "AI候補承認",
  direct: "直接登録",
};

type StateFilter = "all" | "not_achieved" | "achieved" | "pending";

/// 発達記録モーダル(240/239・Phase 3)。管理者Webは主任以上向け。
/// 一覧=fetch_child_development_records、操作=直接登録/承認/差戻し/取消(全てRPC・サーバー側認可)。
export function ChildDevelopmentModal({ childId, childName, officeId, isManager, onClose }: Props) {
  const [header, setHeader] = useState<Header | null>(null);
  const [rows, setRows] = useState<RecordRow[]>([]);
  const [band, setBand] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [domainFilter, setDomainFilter] = useState<string>("all");
  const [stateFilter, setStateFilter] = useState<StateFilter>("all");
  const [hideAchieved, setHideAchieved] = useState(false);

  const [achievedDate, setAchievedDate] = useState(currentDate());
  const [actionError, setActionError] = useState<string | null>(null);
  const [busyItem, setBusyItem] = useState<string | null>(null);

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  // ヘッダ(園児・適用区分)。初回のみ。適用区分を既定バンドにする。
  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_child_development_header", { p_child_id: childId }).then(({ data, error: err }) => {
      if (err) {
        setError(err.message);
        return;
      }
      const h = (Array.isArray(data) ? data[0] : data) as Header | undefined;
      if (h) {
        setHeader(h);
        setBand((prev) => prev ?? h.applicable_band ?? "AGE_2");
      }
    });
  }, [childId]);

  // 一覧(バンド指定)
  useEffect(() => {
    if (!band) return;
    setIsLoading(true);
    setError(null);
    const supabase = createClient();
    supabase
      .rpc("fetch_child_development_records", { p_child_id: childId, p_age_band_code: band })
      .then(({ data, error: err }) => {
        setIsLoading(false);
        if (err) {
          setError(err.message.includes("not authorized") ? "閲覧権限がありません" : err.message);
          setRows([]);
          return;
        }
        setRows((data ?? []) as RecordRow[]);
      });
  }, [childId, band, reloadToken]);

  const filtered = useMemo(() => {
    return rows.filter((r) => {
      if (domainFilter !== "all" && r.domain_code !== domainFilter) return false;
      if (hideAchieved && r.is_achieved) return false;
      if (stateFilter === "achieved" && !r.is_achieved) return false;
      if (stateFilter === "not_achieved" && (r.is_achieved || r.has_pending)) return false;
      if (stateFilter === "pending" && !r.has_pending) return false;
      return true;
    });
  }, [rows, domainFilter, stateFilter, hideAchieved]);

  const achievedCount = rows.filter((r) => r.is_achieved).length;
  const pendingCount = rows.filter((r) => r.has_pending).length;

  async function runAction(itemKey: string, fn: () => Promise<{ error: { message: string } | null }>) {
    setBusyItem(itemKey);
    setActionError(null);
    const { error: err } = await fn();
    setBusyItem(null);
    if (err) {
      setActionError(err.message.includes("not authorized") ? "この操作は主任以上のみ可能です" : err.message);
      return;
    }
    reload();
  }

  function registerDirect(r: RecordRow) {
    const supabase = createClient();
    runAction(r.item_id, async () => {
      const { error } = await supabase.rpc("register_development_achievement_direct", {
        p_child_id: childId,
        p_item_id: r.item_id,
        p_first_achieved_on: achievedDate,
        p_target_year_month: null,
      });
      return { error };
    });
  }

  function approve(r: RecordRow) {
    if (!r.request_id) return;
    const supabase = createClient();
    runAction(r.item_id, async () => {
      const { error } = await supabase.rpc("decide_development_achievement_request", {
        p_request_id: r.request_id,
        p_approve: true,
        p_note: null,
        p_first_achieved_on: achievedDate,
        p_target_year_month: null,
      });
      return { error };
    });
  }

  function returnRequest(r: RecordRow) {
    if (!r.request_id) return;
    const note = window.prompt("差し戻しの理由(任意)") ?? null;
    const supabase = createClient();
    runAction(r.item_id, async () => {
      const { error } = await supabase.rpc("decide_development_achievement_request", {
        p_request_id: r.request_id,
        p_approve: false,
        p_note: note,
        p_first_achieved_on: null,
        p_target_year_month: null,
      });
      return { error };
    });
  }

  function cancel(r: RecordRow) {
    if (!r.achievement_id) return;
    if (!window.confirm(`「${r.item_name}」の達成を取り消します。よろしいですか?`)) return;
    const reason = window.prompt("取消の理由(任意)") ?? null;
    const supabase = createClient();
    runAction(r.item_id, async () => {
      const { error } = await supabase.rpc("cancel_development_achievement", {
        p_achievement_id: r.achievement_id,
        p_reason: reason,
      });
      return { error };
    });
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="max-h-[88vh] w-full max-w-3xl overflow-y-auto rounded-2xl bg-white shadow-lg">
        <div className="sticky top-0 z-10 flex items-center justify-between border-b border-slate-200 bg-white px-6 py-3">
          <div>
            <h2 className="text-base font-bold text-slate-800">発達記録: {childName}</h2>
            <p className="text-xs text-slate-500">
              {header?.class_name ?? "クラス未所属"}
              {header?.applicable_band && ` / 適用区分: ${BAND_LABEL[header.applicable_band] ?? header.applicable_band}`}
              {` / 達成 ${achievedCount}件`}
              {pendingCount > 0 && ` / 申請中 ${pendingCount}件`}
            </p>
          </div>
          <button onClick={onClose} className="text-sm text-slate-500 hover:text-slate-800">
            閉じる
          </button>
        </div>

        <div className="p-6">
          {/* バンド切替(過去区分閲覧) */}
          <div className="mb-3 flex flex-wrap items-center gap-1">
            {AGE_BANDS.map((b) => {
              const isCurrent = header?.applicable_band === b.code;
              const active = band === b.code;
              return (
                <button
                  key={b.code}
                  onClick={() => setBand(b.code)}
                  className={`rounded-lg border px-2.5 py-1 text-xs font-medium ${
                    active
                      ? "border-sky-300 bg-sky-50 text-sky-700"
                      : "border-slate-200 text-slate-500 hover:bg-slate-50"
                  }`}
                >
                  {b.label}
                  {isCurrent && <span className="ml-1 text-[10px] text-sky-500">●適用中</span>}
                </button>
              );
            })}
          </div>

          {/* 絞り込み */}
          <div className="mb-3 flex flex-wrap items-center gap-3 rounded-xl bg-slate-50 p-3 text-xs">
            <label className="flex items-center gap-1">
              領域:
              <select
                value={domainFilter}
                onChange={(e) => setDomainFilter(e.target.value)}
                className="rounded-md border border-slate-300 px-2 py-1"
              >
                <option value="all">全て</option>
                {DOMAINS.map((d) => (
                  <option key={d.code} value={d.code}>
                    {d.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="flex items-center gap-1">
              状態:
              <select
                value={stateFilter}
                onChange={(e) => setStateFilter(e.target.value as StateFilter)}
                className="rounded-md border border-slate-300 px-2 py-1"
              >
                <option value="all">全て</option>
                <option value="not_achieved">未達成</option>
                <option value="achieved">達成済み</option>
                <option value="pending">申請中</option>
              </select>
            </label>
            <label className="flex items-center gap-1">
              <input type="checkbox" checked={hideAchieved} onChange={(e) => setHideAchieved(e.target.checked)} />
              達成済みを非表示
            </label>
            {isManager && (
              <label className="ml-auto flex items-center gap-1">
                達成日:
                <input
                  type="date"
                  value={achievedDate}
                  onChange={(e) => setAchievedDate(e.target.value)}
                  className="rounded-md border border-slate-300 px-2 py-1"
                />
              </label>
            )}
          </div>

          {actionError && <p className="mb-2 text-sm font-medium text-red-600">{actionError}</p>}
          {error && <p className="mb-2 text-sm font-medium text-red-600">{error}</p>}
          {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}

          <div className="space-y-2">
            {!isLoading && filtered.length === 0 && (
              <p className="rounded-xl bg-slate-50 p-4 text-sm text-slate-400">該当する項目がありません</p>
            )}
            {filtered.map((r) => {
              const dom = DOMAIN_MAP[r.domain_code];
              const busy = busyItem === r.item_id;
              return (
                <div
                  key={r.item_id}
                  className={`rounded-xl border p-3 ${
                    r.is_achieved ? "border-emerald-200 bg-emerald-50/40" : "border-slate-200 bg-white"
                  }`}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span
                          className={`rounded-md px-2 py-0.5 text-xs font-semibold ${dom?.className ?? "bg-slate-100 text-slate-600"}`}
                        >
                          {dom?.label ?? r.domain_code}
                        </span>
                        <p className="font-medium text-slate-800">{r.item_name}</p>
                      </div>
                      {r.observation_point && (
                        <p className="mt-0.5 text-xs text-slate-500">{r.observation_point}</p>
                      )}
                      {r.is_achieved && (
                        <p className="mt-1 text-xs text-emerald-700">
                          達成済み{r.first_achieved_on && ` (${r.first_achieved_on})`}
                          {r.approved_by_name && ` / 承認: ${r.approved_by_name}`}
                          {r.method && ` / ${METHOD_LABEL[r.method] ?? r.method}`}
                        </p>
                      )}
                      {r.has_pending && !r.is_achieved && (
                        <p className="mt-1 text-xs text-amber-700">
                          申請中{r.requested_by_name && ` (申請: ${r.requested_by_name})`}
                          {r.request_note && ` / ${r.request_note}`}
                        </p>
                      )}
                    </div>

                    {isManager && (
                      <div className="flex shrink-0 flex-col items-end gap-1">
                        {r.has_pending && !r.is_achieved && (
                          <div className="flex gap-1">
                            <button
                              onClick={() => approve(r)}
                              disabled={busy}
                              className="rounded-lg bg-emerald-600 px-3 py-1 text-xs font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                            >
                              承認
                            </button>
                            <button
                              onClick={() => returnRequest(r)}
                              disabled={busy}
                              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-60"
                            >
                              差戻し
                            </button>
                          </div>
                        )}
                        {!r.is_achieved && !r.has_pending && (
                          <button
                            onClick={() => registerDirect(r)}
                            disabled={busy}
                            className="rounded-lg border border-emerald-300 px-3 py-1 text-xs font-medium text-emerald-700 hover:bg-emerald-50 disabled:opacity-60"
                          >
                            達成登録
                          </button>
                        )}
                        {r.is_achieved && (
                          <button
                            onClick={() => cancel(r)}
                            disabled={busy}
                            className="rounded-lg border border-red-300 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                          >
                            取消
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
