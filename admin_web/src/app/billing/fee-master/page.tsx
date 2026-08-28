"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

/// 料金マスター(請求Phase2・388)。閲覧=主任以上、登録・改訂=統括園長以上(can_edit)。
/// 単価は版管理: 改訂=新版追加+旧版autoクローズ(書き換え禁止)。未来日付の最新版のみ取消可。
/// 契約プラン・月極延長・閉園超過は閲覧のみ(改訂はPhase3で契約と一緒に扱う)。

type RateVersion = {
  id: string;
  version: number;
  amount: number;
  effective_from: string;
  effective_to: string | null;
  approved_by_name: string | null;
  approved_at: string | null;
  source_note: string | null;
  is_future: boolean;
};

type FeeItem = {
  id: string;
  category: string;
  name: string;
  calc_unit: string;
  display_note: string | null;
  sort_order: number;
  is_active: boolean;
  current_amount: number | null;
  current_version: number | null;
  current_effective_from: string | null;
  current_effective_to: string | null;
  versions: RateVersion[];
};

type ContractPlan = {
  id: string;
  name: string;
  cert_type: string | null;
  age_band: string | null;
  usage_start: string;
  usage_end: string;
  saturday_usage_end: string | null;
  monthly_fee_item: string | null;
  monthly_amount: number | null;
  overtime_fee_item: string | null;
  overtime_amount: number | null;
  overtime_calc_unit: string | null;
  effective_from: string;
  effective_to: string | null;
  is_active: boolean;
};

type MonthlyExtensionPlan = {
  id: string;
  name: string;
  coverage_end: string;
  fee_item: string;
  amount: number | null;
  effective_from: string;
  effective_to: string | null;
  is_active: boolean;
};

type ClosingOverrunRule = {
  id: string;
  fee_item: string;
  calc_unit: string;
  amount: number | null;
  enabled_from_fiscal_year: number | null;
  is_active: boolean;
};

type FeeMaster = {
  can_edit: boolean;
  items: FeeItem[];
  plans: ContractPlan[];
  monthly_extension_plans: MonthlyExtensionPlan[];
  closing_overrun_rules: ClosingOverrunRule[];
};

const CATEGORY_LABELS: Record<string, string> = {
  monthly_base: "月極保育料",
  monthly_extension: "月極延長",
  extension: "延長保育(都度)",
  closing_overrun: "閉園時刻超過",
  meal_main: "給食(主食)",
  meal_side: "給食(副食)",
  temp_care: "一時預かり",
  temp_care_meal: "一時預かり給食",
  temp_care_snack: "一時預かりおやつ",
  diaper: "おむつ",
  supply: "備品",
  event: "行事費",
  misc: "その他",
  adjustment_plus: "調整(加算)",
  adjustment_minus: "調整(減算)",
};

const CALC_UNIT_LABELS: Record<string, string> = {
  monthly: "月額",
  per_30min: "30分あたり",
  per_10min: "10分あたり",
  per_day: "1日あたり",
  per_piece: "1個あたり",
  one_time: "都度",
};

const CATEGORY_ORDER = Object.keys(CATEGORY_LABELS);

function yen(amount: number | null | undefined): string {
  if (amount === null || amount === undefined) return "";
  return `¥${amount.toLocaleString("ja-JP")}`;
}

function hhmm(t: string | null): string {
  return t ? t.slice(0, 5) : "";
}

function certLabel(p: ContractPlan): string {
  if (p.cert_type === "standard") return "標準時間認定";
  if (p.cert_type === "short") return "短時間認定";
  if (p.age_band === "age0") return "0歳児";
  if (p.age_band === "age1_2") return "1-2歳児";
  return "";
}

function todayStr(): string {
  const d = new Date();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${m}-${day}`;
}

function FeeMasterPageContent() {
  const { officesError, selectedOffice } = useChildcareOffices();
  const [master, setMaster] = useState<FeeMaster | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);

  // 単価改訂モーダル
  const [reviseTarget, setReviseTarget] = useState<FeeItem | null>(null);
  const [reviseAmount, setReviseAmount] = useState("");
  const [reviseFrom, setReviseFrom] = useState(todayStr());
  const [reviseNote, setReviseNote] = useState("");
  // 品目追加モーダル
  const [addCategory, setAddCategory] = useState<string | null>(null);
  const [addName, setAddName] = useState("");
  const [addCalcUnit, setAddCalcUnit] = useState("per_piece");
  // 履歴モーダル
  const [historyTarget, setHistoryTarget] = useState<FeeItem | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [isActing, setIsActing] = useState(false);
  const [showInactive, setShowInactive] = useState(false);

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    if (!selectedOffice) return;
    let stale = false;
    setIsLoading(true);
    setLoadError(null);
    const supabase = createClient();
    supabase.rpc("fetch_fee_master", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (stale) return;
      setIsLoading(false);
      if (error) {
        setLoadError(
          error.message.includes("feature disabled")
            ? "この施設は請求管理が無効です(機能フラグOFF)"
            : error.message.includes("not authorized")
              ? "このページは主任以上のみ利用できます"
              : error.message,
        );
        setMaster(null);
        return;
      }
      setMaster(data as FeeMaster);
    });
    return () => {
      stale = true;
    };
  }, [selectedOffice, reloadToken]);

  function openRevise(item: FeeItem) {
    setReviseTarget(item);
    setReviseAmount(item.current_amount !== null ? String(item.current_amount) : "");
    setReviseFrom(todayStr());
    setReviseNote("");
    setActionError(null);
  }

  async function handleRevise() {
    if (!reviseTarget) return;
    const amount = Number(reviseAmount);
    if (!Number.isInteger(amount) || amount < 0) {
      setActionError("金額は0以上の整数(円)で入力してください");
      return;
    }
    setIsActing(true);
    setActionError(null);
    const { error } = await createClient().rpc("add_fee_rate_version", {
      p_fee_item_id: reviseTarget.id,
      p_amount: amount,
      p_effective_from: reviseFrom,
      p_source_note: reviseNote.trim() || null,
    });
    setIsActing(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    setReviseTarget(null);
    reload();
  }

  async function handleAddItem() {
    if (!addCategory) return;
    if (!addName.trim()) {
      setActionError("品目名を入力してください");
      return;
    }
    setIsActing(true);
    setActionError(null);
    const { error } = await createClient().rpc("upsert_fee_item", {
      p_office_id: selectedOffice,
      p_id: null,
      p_category: addCategory,
      p_name: addName.trim(),
      p_calc_unit: addCalcUnit,
      p_display_note: null,
      p_sort_order: 0,
      p_is_active: true,
    });
    setIsActing(false);
    if (error) {
      setActionError(error.message.includes("duplicate key") ? "同じ名前の品目が既にあります" : error.message);
      return;
    }
    setAddCategory(null);
    setAddName("");
    reload();
  }

  async function handleToggleActive(item: FeeItem) {
    const verb = item.is_active ? "非表示" : "再表示";
    if (!window.confirm(`「${item.name}」を${verb}にしますか?`)) return;
    const { error } = await createClient().rpc("upsert_fee_item", {
      p_office_id: selectedOffice,
      p_id: item.id,
      p_category: item.category,
      p_name: item.name,
      p_calc_unit: item.calc_unit,
      p_display_note: item.display_note,
      p_sort_order: item.sort_order,
      p_is_active: !item.is_active,
    });
    if (error) {
      window.alert(`変更に失敗しました: ${error.message}`);
      return;
    }
    reload();
  }

  async function handleCancelFuture(item: FeeItem, v: RateVersion) {
    if (!window.confirm(`「${item.name}」の未来版(${v.effective_from}〜 ${yen(v.amount)})を取り消しますか?`)) return;
    const { error } = await createClient().rpc("cancel_future_rate_version", { p_version_id: v.id });
    if (error) {
      window.alert(`取消に失敗しました: ${error.message}`);
      return;
    }
    reload();
  }

  const canEdit = master?.can_edit ?? false;
  const visibleItems = (master?.items ?? []).filter((i) => showInactive || i.is_active);
  const categories = CATEGORY_ORDER.filter((c) => visibleItems.some((i) => i.category === c));
  const inactiveCount = (master?.items ?? []).filter((i) => !i.is_active).length;

  return (
    <div className="min-h-screen bg-slate-50">
      <AppHeader />
      <main className="mx-auto max-w-6xl px-6 py-6">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-xl font-bold text-slate-800">料金マスター</h2>
            <p className="mt-1 text-sm text-slate-500">
              単価の改訂は「新版の追加+旧版を自動で閉じる」方式です(過去の請求は当時の単価で再現)。
              {canEdit ? "" : " 登録・改訂は統括園長のみ行えます(閲覧のみ)。"}
            </p>
          </div>
          {inactiveCount > 0 && (
            <label className="flex items-center gap-1.5 text-sm text-slate-600">
              <input type="checkbox" checked={showInactive} onChange={(e) => setShowInactive(e.target.checked)} />
              非表示の品目も表示({inactiveCount})
            </label>
          )}
        </div>

        {officesError && <p className="mb-4 text-sm font-medium text-red-500">{officesError}</p>}
        {loadError && (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-medium text-red-600">
            {loadError}
          </div>
        )}
        {isLoading && !master && <p className="text-sm text-slate-500">読み込み中…</p>}

        {master && (
          <div className="space-y-6">
            {categories.map((cat) => {
              const items = visibleItems.filter((i) => i.category === cat);
              return (
                <section key={cat} className="rounded-xl border border-slate-200 bg-white">
                  <div className="flex items-center justify-between border-b border-slate-100 px-4 py-2.5">
                    <h3 className="text-sm font-bold text-slate-700">
                      {CATEGORY_LABELS[cat]}
                      <span className="ml-2 text-xs font-normal text-slate-400">{items.length}品目</span>
                    </h3>
                    {canEdit && (
                      <button
                        onClick={() => {
                          setAddCategory(cat);
                          setAddName("");
                          setAddCalcUnit(cat === "supply" || cat === "diaper" ? "per_piece" : "one_time");
                          setActionError(null);
                        }}
                        className="rounded-lg border border-sky-200 bg-sky-50 px-2.5 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-100"
                      >
                        + 品目追加
                      </button>
                    )}
                  </div>
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="text-left text-xs text-slate-400">
                        <th className="px-4 py-1.5 font-medium">品目</th>
                        <th className="px-2 py-1.5 font-medium">単位</th>
                        <th className="px-2 py-1.5 text-right font-medium">現行単価</th>
                        <th className="px-2 py-1.5 font-medium">適用開始</th>
                        <th className="px-2 py-1.5 font-medium">改訂予定</th>
                        <th className="px-4 py-1.5 text-right font-medium">操作</th>
                      </tr>
                    </thead>
                    <tbody>
                      {items.map((item) => {
                        const future = item.versions.find((v) => v.is_future);
                        return (
                          <tr
                            key={item.id}
                            className={`border-t border-slate-100 ${item.is_active ? "" : "opacity-50"}`}
                          >
                            <td className="px-4 py-2 font-medium text-slate-700">
                              {item.name}
                              {!item.is_active && (
                                <span className="ml-2 rounded bg-slate-200 px-1.5 py-0.5 text-xs text-slate-500">非表示</span>
                              )}
                              {item.display_note && (
                                <span className="ml-2 text-xs text-slate-400">{item.display_note}</span>
                              )}
                            </td>
                            <td className="px-2 py-2 text-slate-500">{CALC_UNIT_LABELS[item.calc_unit] ?? item.calc_unit}</td>
                            <td className="px-2 py-2 text-right font-semibold tabular-nums text-slate-800">
                              {item.current_amount !== null ? (
                                yen(item.current_amount)
                              ) : (
                                <span className="rounded bg-amber-100 px-1.5 py-0.5 text-xs font-semibold text-amber-700">未登録</span>
                              )}
                            </td>
                            <td className="px-2 py-2 text-slate-500">{item.current_effective_from ?? ""}</td>
                            <td className="px-2 py-2">
                              {future && (
                                <span className="inline-flex items-center gap-1.5 rounded bg-violet-50 px-1.5 py-0.5 text-xs font-semibold text-violet-700">
                                  {future.effective_from}〜 {yen(future.amount)}
                                  {canEdit && (
                                    <button
                                      onClick={() => handleCancelFuture(item, future)}
                                      className="text-violet-500 underline hover:text-violet-700"
                                    >
                                      取消
                                    </button>
                                  )}
                                </span>
                              )}
                            </td>
                            <td className="px-4 py-2 text-right">
                              <div className="flex justify-end gap-2">
                                {item.versions.length > 0 && (
                                  <button
                                    onClick={() => setHistoryTarget(item)}
                                    className="rounded border border-slate-200 px-2 py-1 text-xs text-slate-500 hover:bg-slate-50"
                                  >
                                    履歴
                                  </button>
                                )}
                                {canEdit && (
                                  <>
                                    <button
                                      onClick={() => openRevise(item)}
                                      className="rounded border border-sky-200 px-2 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-50"
                                    >
                                      {item.current_amount !== null || item.versions.length > 0 ? "単価改訂" : "単価登録"}
                                    </button>
                                    <button
                                      onClick={() => handleToggleActive(item)}
                                      className="rounded border border-slate-200 px-2 py-1 text-xs text-slate-500 hover:bg-slate-50"
                                    >
                                      {item.is_active ? "非表示" : "再表示"}
                                    </button>
                                  </>
                                )}
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </section>
              );
            })}

            {/* 契約プラン(閲覧のみ・改訂はPhase3) */}
            {master.plans.length > 0 && (
              <section className="rounded-xl border border-slate-200 bg-white">
                <div className="border-b border-slate-100 px-4 py-2.5">
                  <h3 className="text-sm font-bold text-slate-700">
                    契約プラン
                    <span className="ml-2 text-xs font-normal text-slate-400">閲覧のみ(プラン改訂は契約管理と一緒に対応予定)</span>
                  </h3>
                </div>
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-xs text-slate-400">
                      <th className="px-4 py-1.5 font-medium">プラン名</th>
                      <th className="px-2 py-1.5 font-medium">区分</th>
                      <th className="px-2 py-1.5 font-medium">利用時間</th>
                      <th className="px-2 py-1.5 text-right font-medium">月額</th>
                      <th className="px-4 py-1.5 text-right font-medium">契約時間外</th>
                    </tr>
                  </thead>
                  <tbody>
                    {master.plans.map((p) => (
                      <tr key={p.id} className="border-t border-slate-100">
                        <td className="px-4 py-2 font-medium text-slate-700">{p.name}</td>
                        <td className="px-2 py-2 text-slate-500">{certLabel(p)}</td>
                        <td className="px-2 py-2 tabular-nums text-slate-600">
                          {hhmm(p.usage_start)}〜{hhmm(p.usage_end)}
                          {p.saturday_usage_end && (
                            <span className="ml-1 text-xs text-slate-400">(土曜〜{hhmm(p.saturday_usage_end)})</span>
                          )}
                        </td>
                        <td className="px-2 py-2 text-right tabular-nums text-slate-800">
                          {p.monthly_fee_item ? yen(p.monthly_amount) : <span className="text-xs text-slate-400">自治体徴収</span>}
                        </td>
                        <td className="px-4 py-2 text-right tabular-nums text-slate-800">
                          {p.overtime_fee_item ? (
                            <>
                              {yen(p.overtime_amount)}
                              <span className="ml-1 text-xs text-slate-400">
                                /{CALC_UNIT_LABELS[p.overtime_calc_unit ?? ""] ?? ""}
                              </span>
                            </>
                          ) : (
                            <span className="text-xs text-slate-400">ー</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </section>
            )}

            {master.monthly_extension_plans.length > 0 && (
              <section className="rounded-xl border border-slate-200 bg-white">
                <div className="border-b border-slate-100 px-4 py-2.5">
                  <h3 className="text-sm font-bold text-slate-700">月極延長プラン<span className="ml-2 text-xs font-normal text-slate-400">閲覧のみ</span></h3>
                </div>
                <table className="w-full text-sm">
                  <tbody>
                    {master.monthly_extension_plans.map((m) => (
                      <tr key={m.id} className="border-t border-slate-100 first:border-t-0">
                        <td className="px-4 py-2 font-medium text-slate-700">{m.name}</td>
                        <td className="px-2 py-2 text-slate-500">〜{hhmm(m.coverage_end)}</td>
                        <td className="px-4 py-2 text-right tabular-nums text-slate-800">{yen(m.amount)}/月</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </section>
            )}

            {master.closing_overrun_rules.length > 0 && (
              <section className="rounded-xl border border-slate-200 bg-white">
                <div className="border-b border-slate-100 px-4 py-2.5">
                  <h3 className="text-sm font-bold text-slate-700">閉園時刻超過(実費)<span className="ml-2 text-xs font-normal text-slate-400">閲覧のみ</span></h3>
                </div>
                <table className="w-full text-sm">
                  <tbody>
                    {master.closing_overrun_rules.map((r) => (
                      <tr key={r.id} className="border-t border-slate-100 first:border-t-0">
                        <td className="px-4 py-2 font-medium text-slate-700">{r.fee_item}</td>
                        <td className="px-2 py-2 text-slate-500">{CALC_UNIT_LABELS[r.calc_unit] ?? r.calc_unit}</td>
                        <td className="px-2 py-2 text-right tabular-nums text-slate-800">{yen(r.amount)}</td>
                        <td className="px-4 py-2 text-right text-xs text-slate-400">
                          {r.enabled_from_fiscal_year ? `${r.enabled_from_fiscal_year}年度〜` : ""}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </section>
            )}
          </div>
        )}
      </main>

      {/* 単価改訂モーダル */}
      {reviseTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
          <div className="w-full max-w-md rounded-xl bg-white p-5 shadow-xl">
            <h3 className="text-base font-bold text-slate-800">
              単価{reviseTarget.current_amount !== null || reviseTarget.versions.length > 0 ? "改訂" : "登録"}: {reviseTarget.name}
            </h3>
            <p className="mt-1 text-xs text-slate-500">
              {CATEGORY_LABELS[reviseTarget.category]} / {CALC_UNIT_LABELS[reviseTarget.calc_unit]}
              {reviseTarget.current_amount !== null && ` / 現行 ${yen(reviseTarget.current_amount)}`}
            </p>
            <div className="mt-4 space-y-3">
              <label className="block text-sm text-slate-600">
                新しい単価(円)
                <input
                  type="number"
                  min={0}
                  value={reviseAmount}
                  onChange={(e) => setReviseAmount(e.target.value)}
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </label>
              <label className="block text-sm text-slate-600">
                適用開始日
                <input
                  type="date"
                  value={reviseFrom}
                  onChange={(e) => setReviseFrom(e.target.value)}
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </label>
              <label className="block text-sm text-slate-600">
                根拠メモ(任意)
                <input
                  type="text"
                  value={reviseNote}
                  onChange={(e) => setReviseNote(e.target.value)}
                  placeholder="例: 2027年度改定・理事会承認"
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </label>
            </div>
            {actionError && <p className="mt-2 text-sm font-medium text-red-500">{actionError}</p>}
            <div className="mt-4 flex justify-end gap-3">
              <button
                onClick={() => setReviseTarget(null)}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                onClick={handleRevise}
                disabled={isActing}
                className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
              >
                {isActing ? "処理中…" : "この内容で確定"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 品目追加モーダル */}
      {addCategory && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
          <div className="w-full max-w-md rounded-xl bg-white p-5 shadow-xl">
            <h3 className="text-base font-bold text-slate-800">品目追加</h3>
            <div className="mt-4 space-y-3">
              <label className="block text-sm text-slate-600">
                区分
                <select
                  value={addCategory}
                  onChange={(e) => setAddCategory(e.target.value)}
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                >
                  {CATEGORY_ORDER.map((c) => (
                    <option key={c} value={c}>
                      {CATEGORY_LABELS[c]}
                    </option>
                  ))}
                </select>
              </label>
              <label className="block text-sm text-slate-600">
                品目名
                <input
                  type="text"
                  value={addName}
                  onChange={(e) => setAddName(e.target.value)}
                  placeholder="例: 上履き"
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </label>
              <label className="block text-sm text-slate-600">
                単位(作成後は変更できません)
                <select
                  value={addCalcUnit}
                  onChange={(e) => setAddCalcUnit(e.target.value)}
                  className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                >
                  {Object.entries(CALC_UNIT_LABELS).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </label>
            </div>
            {actionError && <p className="mt-2 text-sm font-medium text-red-500">{actionError}</p>}
            <div className="mt-4 flex justify-end gap-3">
              <button
                onClick={() => setAddCategory(null)}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                onClick={handleAddItem}
                disabled={isActing}
                className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
              >
                {isActing ? "処理中…" : "追加する"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 単価履歴モーダル */}
      {historyTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
          <div className="w-full max-w-lg rounded-xl bg-white p-5 shadow-xl">
            <h3 className="text-base font-bold text-slate-800">単価履歴: {historyTarget.name}</h3>
            <div className="mt-3 max-h-80 overflow-y-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-slate-400">
                    <th className="py-1.5 pr-2 font-medium">版</th>
                    <th className="py-1.5 pr-2 text-right font-medium">単価</th>
                    <th className="py-1.5 pr-2 font-medium">適用期間</th>
                    <th className="py-1.5 font-medium">承認・根拠</th>
                  </tr>
                </thead>
                <tbody>
                  {historyTarget.versions.map((v) => (
                    <tr key={v.id} className="border-t border-slate-100">
                      <td className="py-2 pr-2 text-slate-500">
                        v{v.version}
                        {v.is_future && (
                          <span className="ml-1 rounded bg-violet-50 px-1 py-0.5 text-xs text-violet-600">予定</span>
                        )}
                      </td>
                      <td className="py-2 pr-2 text-right font-semibold tabular-nums text-slate-800">{yen(v.amount)}</td>
                      <td className="py-2 pr-2 tabular-nums text-slate-600">
                        {v.effective_from}〜{v.effective_to ?? ""}
                      </td>
                      <td className="py-2 text-xs text-slate-500">
                        {v.approved_by_name ?? ""}
                        {v.source_note && <span className="ml-1 text-slate-400">{v.source_note}</span>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="mt-4 flex justify-end">
              <button
                onClick={() => setHistoryTarget(null)}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                閉じる
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function FeeMasterPage() {
  return (
    <Suspense fallback={null}>
      <FeeMasterPageContent />
    </Suspense>
  );
}
