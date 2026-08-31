"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 請求管理(請求Phase7b・396のRPCを操作するUI)。
// サイクル実行=主任以上/承認・公開・取消=統括のみ(権限はRPC側で強制・権限外はエラー表示)。
// フロー: サイクル実行→自動チェック確認→承認→公開(期限=公開+10日)。取消→再実行も可能。

type CycleInfo = {
  id: string;
  billing_month: string;
  status: string;
  calculated_at: string | null;
  approved_at: string | null;
  published_at: string | null;
  note: string | null;
};

type InvoiceRow = {
  id: string;
  invoice_no: string;
  child_id: string;
  child_name: string;
  class_name: string | null;
  status: string;
  total_amount: number;
  due_date: string | null;
};

type CheckRow = { check_key: string; severity: string; child_id: string | null; message: string };

type Overview = {
  cycle: CycleInfo | null;
  invoices: InvoiceRow[];
  checks: CheckRow[];
  totals: { invoice_count: number; total_amount: number } | null;
};

type InvoiceItem = {
  id: string;
  category: string;
  description: string;
  target_period: string | null;
  quantity: number;
  unit_amount: number | null;
  amount: number;
  is_manual: boolean;
};

type InvoiceDetail = {
  invoice: {
    id: string;
    invoice_no: string;
    child_name: string;
    billing_month: string;
    status: string;
    total_amount: number;
    paid_amount: number;
    due_date: string | null;
    published_at: string | null;
  };
  items: InvoiceItem[];
};

type SupplyOrderRow = {
  order_id: string;
  child_id: string;
  child_name: string;
  class_name: string | null;
  item_name: string;
  quantity: number;
  status: string;
  note: string | null;
  unit_amount: number | null;
  requested_at: string;
  guardian_name: string | null;
};

// 手動明細で選べる種別(実費系のみ。自動計算系はRPC側でも拒否される)
const MANUAL_CATEGORIES: { value: string; label: string }[] = [
  { value: "supply", label: "備品代" },
  { value: "diaper", label: "おむつ代" },
  { value: "event", label: "行事費" },
  { value: "misc", label: "その他実費" },
];

const CYCLE_STATUS_LABELS: Record<string, { label: string; cls: string }> = {
  draft: { label: "作成中", cls: "bg-slate-100 text-slate-600" },
  review_required: { label: "確認待ち", cls: "bg-amber-100 text-amber-700" },
  approved: { label: "承認済み", cls: "bg-sky-100 text-sky-700" },
  published: { label: "公開済み", cls: "bg-emerald-100 text-emerald-700" },
  cancelled: { label: "取消済み", cls: "bg-slate-200 text-slate-500" },
};

const INVOICE_STATUS_LABELS: Record<string, string> = {
  draft: "下書き",
  approved: "承認済み",
  issued: "公開済み",
  paid: "支払済み",
  partially_paid: "一部入金",
  overdue: "期限超過",
  cancelled: "取消",
};

function yen(n: number | null | undefined): string {
  if (n === null || n === undefined) return "";
  return `¥${n.toLocaleString("ja-JP")}`;
}

function currentMonthYM(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function BillingInvoicesPageContent() {
  const { officesError, selectedOffice } = useChildcareOffices();
  const [month, setMonth] = useState(currentMonthYM());
  const [data, setData] = useState<Overview | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [detail, setDetail] = useState<InvoiceDetail | null>(null);
  const [classFilter, setClassFilter] = useState<string>("");  // ""=全クラス(俊要望 2026-08-31)
  // 手動明細の追加フォーム(下書き請求書のみ・俊要望 2026-08-31)
  const [miCat, setMiCat] = useState("supply");
  const [miDesc, setMiDesc] = useState("");
  const [miQty, setMiQty] = useState("1");
  const [miUnit, setMiUnit] = useState("");
  // 備品注文(401): 申請中の承認/却下と、承認済み(次回請求に合算予定)の把握
  const [supplyOrders, setSupplyOrders] = useState<SupplyOrderRow[]>([]);

  useEffect(() => {
    if (!selectedOffice) return;
    let stale = false;
    createClient()
      .rpc("fetch_supply_orders", { p_office_id: selectedOffice })
      .then(({ data: d, error }) => {
        if (stale) return;
        setSupplyOrders(error ? [] : ((d ?? []) as SupplyOrderRow[]));
      });
    return () => { stale = true; };
  }, [selectedOffice, reloadToken]);

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    if (!selectedOffice || !month) return;
    let stale = false;
    setLoadError(null);
    createClient()
      .rpc("fetch_billing_cycle_overview", { p_office_id: selectedOffice, p_billing_month: `${month}-01` })
      .then(({ data: d, error }) => {
        if (stale) return;
        if (error) {
          setLoadError(
            error.message.includes("feature disabled")
              ? "この施設は請求管理が無効です(機能フラグOFF)"
              : error.message.includes("not authorized")
                ? "このページは主任以上のみ利用できます"
                : error.message,
          );
          setData(null);
          return;
        }
        setData(d as Overview);
      });
    return () => { stale = true; };
  }, [selectedOffice, month, reloadToken]);

  async function runAction(rpcName: string, params: Record<string, unknown>, confirmMsg?: string) {
    if (confirmMsg && !window.confirm(confirmMsg)) return;
    setBusy(true);
    setActionError(null);
    const { error } = await createClient().rpc(rpcName, params);
    setBusy(false);
    if (error) {
      setActionError(
        error.message.includes("not authorized") ? "この操作は統括園長のみ行えます" : error.message,
      );
      return;
    }
    reload();
  }

  async function openDetail(inv: InvoiceRow) {
    const { data: d, error } = await createClient().rpc("fetch_invoice_detail", { p_invoice_id: inv.id });
    if (error) {
      setActionError(error.message);
      return;
    }
    setDetail(d as InvoiceDetail);
  }

  // 明細モーダル内の操作後に、モーダルと一覧の両方を最新化する
  async function refreshDetail(invoiceId: string) {
    const { data: d, error } = await createClient().rpc("fetch_invoice_detail", { p_invoice_id: invoiceId });
    if (!error) setDetail(d as InvoiceDetail);
    reload();
  }

  async function handleAddManualItem(invoiceId: string, category: string, description: string, quantity: number, unitAmount: number) {
    setBusy(true);
    const { error } = await createClient().rpc("add_manual_invoice_item", {
      p_invoice_id: invoiceId,
      p_category: category,
      p_description: description,
      p_quantity: quantity,
      p_unit_amount: unitAmount,
    });
    setBusy(false);
    if (error) {
      window.alert(`追加に失敗しました: ${error.message}`);
      return;
    }
    await refreshDetail(invoiceId);
  }

  async function handleDeleteManualItem(invoiceId: string, item: InvoiceItem) {
    if (!window.confirm(`「${item.description}」を削除しますか?`)) return;
    const { error } = await createClient().rpc("delete_manual_invoice_item", { p_item_id: item.id });
    if (error) {
      window.alert(`削除に失敗しました: ${error.message}`);
      return;
    }
    await refreshDetail(invoiceId);
  }

  const cycle = data?.cycle ?? null;
  const cycleStatus = cycle ? CYCLE_STATUS_LABELS[cycle.status] : null;
  const errorChecks = (data?.checks ?? []).filter((c) => c.severity === "error");
  const warnChecks = (data?.checks ?? []).filter((c) => c.severity === "warning");
  const infoChecks = (data?.checks ?? []).filter((c) => c.severity === "info");
  const classNames = Array.from(
    new Set((data?.invoices ?? []).map((i) => i.class_name).filter((n): n is string => !!n)),
  ).sort();
  const visibleInvoices = (data?.invoices ?? []).filter(
    (i) => !classFilter || i.class_name === classFilter,
  );

  return (
    <div className="min-h-screen bg-slate-50">
      <AppHeader />
      <main className="mx-auto max-w-5xl px-6 py-6">
        <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="text-xl font-bold text-slate-800">請求管理</h2>
            <p className="mt-1 text-sm text-slate-500">
              サイクル実行(当月の月極+前月の給食・延長実績)→チェック確認→承認→公開の順に進めます。承認・公開は統括園長のみ。
            </p>
          </div>
          <label className="text-xs font-semibold text-slate-500">
            請求月
            <input
              type="month"
              value={month}
              onChange={(e) => setMonth(e.target.value)}
              className="ml-2 rounded-lg border border-slate-300 px-2 py-1.5 text-sm font-normal text-slate-800"
            />
          </label>
        </div>

        {officesError && <p className="mb-4 text-sm font-medium text-red-500">{officesError}</p>}
        {loadError && (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-medium text-red-600">
            {loadError}
          </div>
        )}

        {data && !loadError && (
          <div className="space-y-5">
            {/* サイクル状態と操作 */}
            <section className="rounded-xl border border-slate-200 bg-white p-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <h3 className="text-sm font-bold text-slate-700">{month.replace("-", "年")}月分サイクル</h3>
                  {cycleStatus ? (
                    <span className={`rounded px-2 py-0.5 text-xs font-semibold ${cycleStatus.cls}`}>
                      {cycleStatus.label}
                    </span>
                  ) : (
                    <span className="rounded bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">未実行</span>
                  )}
                  {data.totals && cycle && (
                    <span className="text-sm text-slate-600">
                      {data.totals.invoice_count}件 / 合計 <span className="font-bold tabular-nums">{yen(data.totals.total_amount)}</span>
                    </span>
                  )}
                </div>
                <div className="flex gap-2">
                  {!cycle && (
                    <button
                      onClick={() => runAction("run_billing_cycle",
                        { p_office_id: selectedOffice, p_billing_month: `${month}-01` },
                        `${month.replace("-", "年")}月分の請求サイクルを実行しますか?(下書き作成・保護者にはまだ見えません)`)}
                      disabled={busy}
                      className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
                    >
                      サイクル実行
                    </button>
                  )}
                  {cycle?.status === "review_required" && (
                    <>
                      <button
                        onClick={() => runAction("approve_billing_cycle", { p_cycle_id: cycle.id },
                          "内容を確認しました。承認しますか?(統括園長のみ)")}
                        disabled={busy}
                        className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
                      >
                        承認する
                      </button>
                      <button
                        onClick={() => {
                          const reason = window.prompt("取消理由を入力してください(修正して再実行できます)");
                          if (reason) void runAction("cancel_billing_cycle", { p_cycle_id: cycle.id, p_reason: reason });
                        }}
                        disabled={busy}
                        className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                      >
                        取消
                      </button>
                    </>
                  )}
                  {cycle?.status === "approved" && (
                    <>
                      <button
                        onClick={() => runAction("publish_billing_cycle", { p_cycle_id: cycle.id },
                          "保護者へ公開しますか?(支払期限=公開日+10日)")}
                        disabled={busy}
                        className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                      >
                        保護者へ公開
                      </button>
                      <button
                        onClick={() => {
                          const reason = window.prompt("取消理由を入力してください");
                          if (reason) void runAction("cancel_billing_cycle", { p_cycle_id: cycle.id, p_reason: reason });
                        }}
                        disabled={busy}
                        className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                      >
                        取消
                      </button>
                    </>
                  )}
                  {/* 公開済みの差し戻し(俊要望 2026-08-31): 統括のみ・入金済みがあればRPC側で拒否・
                      保護者へ取り下げ通知が送られる */}
                  {cycle?.status === "published" && (
                    <button
                      onClick={() => {
                        const reason = window.prompt(
                          "公開済みの請求を差し戻します。\n保護者アプリから見えなくなり、取り下げのお知らせが送られます。\n(入金済みの請求がある場合は差し戻せません)\n\n差し戻し理由を入力してください:");
                        if (reason) void runAction("cancel_billing_cycle", { p_cycle_id: cycle.id, p_reason: reason });
                      }}
                      disabled={busy}
                      className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                    >
                      差し戻し(取消)
                    </button>
                  )}
                </div>
              </div>
              {actionError && <p className="mt-2 text-sm font-medium text-red-500">{actionError}</p>}
            </section>

            {/* 備品注文(401): 保護者からの注文を承認/却下。承認分は次回サイクルで自動合算 */}
            {supplyOrders.length > 0 && (
              <section className="rounded-xl border border-slate-200 bg-white p-4">
                <h3 className="text-sm font-bold text-slate-700">
                  備品注文
                  {supplyOrders.filter((o) => o.status === "requested").length > 0 && (
                    <span className="ml-2 rounded bg-amber-100 px-1.5 py-0.5 text-xs font-semibold text-amber-700">
                      申請中 {supplyOrders.filter((o) => o.status === "requested").length}件
                    </span>
                  )}
                </h3>
                <table className="mt-2 w-full text-sm">
                  <tbody>
                    {supplyOrders.map((o) => (
                      <tr key={o.order_id} className="border-t border-slate-100">
                        <td className="py-1.5 pr-2 text-slate-600">{o.class_name ?? ""}</td>
                        <td className="py-1.5 pr-2 font-medium text-slate-700">{o.child_name}</td>
                        <td className="py-1.5 pr-2 text-slate-700">
                          {o.item_name} × {o.quantity}
                          {o.note && <span className="ml-1 text-xs text-slate-400">({o.note})</span>}
                        </td>
                        <td className="py-1.5 pr-2">
                          <span className={`rounded px-1.5 py-0.5 text-xs font-semibold ${
                            o.status === "requested" ? "bg-amber-100 text-amber-700"
                            : o.status === "approved" ? "bg-emerald-50 text-emerald-700"
                            : o.status === "rejected" ? "bg-red-100 text-red-600"
                            : "bg-slate-200 text-slate-500"}`}>
                            {o.status === "requested" ? "申請中"
                              : o.status === "approved" ? (o.unit_amount !== null ? `承認済み(次回請求 ${yen(o.unit_amount * o.quantity)})` : "承認済み")
                              : o.status === "rejected" ? "却下" : "取消"}
                          </span>
                        </td>
                        <td className="py-1.5 text-right">
                          {o.status === "requested" && (
                            <div className="flex justify-end gap-1.5">
                              <button
                                onClick={() => runAction("approve_supply_order", { p_order_id: o.order_id },
                                  `${o.child_name}さんの「${o.item_name} × ${o.quantity}」を承認しますか?(次回請求に合算・保護者へ通知)`)}
                                disabled={busy}
                                className="rounded border border-sky-200 px-2 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-50 disabled:opacity-60"
                              >
                                承認
                              </button>
                              <button
                                onClick={() => {
                                  const reason = window.prompt(`「${o.item_name}」の却下理由(保護者へ通知されます):`);
                                  if (reason) void runAction("reject_supply_order", { p_order_id: o.order_id, p_reason: reason });
                                }}
                                disabled={busy}
                                className="rounded border border-red-200 px-2 py-1 text-xs text-red-500 hover:bg-red-50 disabled:opacity-60"
                              >
                                却下
                              </button>
                            </div>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </section>
            )}

            {/* 自動チェック */}
            {cycle && (errorChecks.length > 0 || warnChecks.length > 0 || infoChecks.length > 0) && (
              <section className="rounded-xl border border-slate-200 bg-white p-4">
                <h3 className="text-sm font-bold text-slate-700">
                  自動チェック
                  {errorChecks.length > 0 && (
                    <span className="ml-2 rounded bg-red-100 px-1.5 py-0.5 text-xs font-semibold text-red-600">
                      エラー{errorChecks.length}(解消するまで承認できません)
                    </span>
                  )}
                </h3>
                <ul className="mt-2 space-y-1">
                  {[...errorChecks, ...warnChecks, ...infoChecks].map((c, idx) => (
                    <li key={idx} className="flex items-start gap-2 text-sm">
                      <span className={`mt-0.5 rounded px-1.5 py-0.5 text-xs font-semibold ${
                        c.severity === "error" ? "bg-red-100 text-red-600"
                        : c.severity === "warning" ? "bg-amber-100 text-amber-700"
                        : "bg-slate-100 text-slate-500"}`}>
                        {c.severity === "error" ? "エラー" : c.severity === "warning" ? "警告" : "情報"}
                      </span>
                      <span className="text-slate-700">{c.message}</span>
                    </li>
                  ))}
                </ul>
              </section>
            )}

            {/* 請求一覧 */}
            {cycle && (
              <section className="overflow-hidden rounded-xl border border-slate-200 bg-white">
                <div className="flex items-center justify-between border-b border-slate-100 px-4 py-2">
                  <label className="flex items-center gap-1.5 text-xs font-semibold text-slate-500">
                    クラス:
                    <select
                      value={classFilter}
                      onChange={(e) => setClassFilter(e.target.value)}
                      className="rounded-md border border-slate-300 bg-white px-2 py-1 text-sm font-normal text-slate-800"
                    >
                      <option value="">全クラス</option>
                      {classNames.map((n) => (
                        <option key={n} value={n}>{n}</option>
                      ))}
                    </select>
                  </label>
                  <span className="text-xs text-slate-400">
                    {classFilter ? `${visibleInvoices.length}件を表示` : `全${(data.invoices ?? []).length}件`}
                  </span>
                </div>
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-xs text-slate-400">
                      <th className="px-4 py-2 font-medium">請求番号</th>
                      <th className="px-2 py-2 font-medium">クラス</th>
                      <th className="px-2 py-2 font-medium">園児</th>
                      <th className="px-2 py-2 text-right font-medium">金額</th>
                      <th className="px-2 py-2 font-medium">状態</th>
                      <th className="px-2 py-2 font-medium">支払期限</th>
                      <th className="px-4 py-2 text-right font-medium"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {visibleInvoices.map((inv) => (
                      <tr key={inv.id} className="border-t border-slate-100">
                        <td className="px-4 py-2 font-mono text-xs text-slate-600">{inv.invoice_no}</td>
                        <td className="px-2 py-2 text-slate-600">{inv.class_name ?? ""}</td>
                        <td className="px-2 py-2 font-medium text-slate-700">{inv.child_name}</td>
                        <td className="px-2 py-2 text-right font-semibold tabular-nums text-slate-800">{yen(inv.total_amount)}</td>
                        <td className="px-2 py-2">
                          <span className={`rounded px-1.5 py-0.5 text-xs font-semibold ${
                            inv.status === "issued" ? "bg-emerald-50 text-emerald-700"
                            : inv.status === "cancelled" ? "bg-slate-200 text-slate-500"
                            : "bg-slate-100 text-slate-600"}`}>
                            {INVOICE_STATUS_LABELS[inv.status] ?? inv.status}
                          </span>
                        </td>
                        <td className="px-2 py-2 tabular-nums text-slate-600">{inv.due_date ?? ""}</td>
                        <td className="px-4 py-2 text-right">
                          <div className="flex justify-end gap-1.5">
                            <button
                              onClick={() => openDetail(inv)}
                              className="rounded border border-slate-200 px-2 py-1 text-xs text-slate-500 hover:bg-slate-50"
                            >
                              明細
                            </button>
                            {/* 個別差し戻し・再発行(俊要望 2026-08-31): 公開済みサイクルで1件単位の修正を可能に */}
                            {cycle?.status === "published" && inv.status === "issued" && (
                              <button
                                onClick={() => {
                                  const reason = window.prompt(
                                    `${inv.child_name}さんの請求(${inv.invoice_no})を差し戻します。\n保護者には取り下げのお知らせが送られます。\n\n差し戻し理由:`);
                                  if (reason) void runAction("cancel_invoice", { p_invoice_id: inv.id, p_reason: reason });
                                }}
                                disabled={busy}
                                className="rounded border border-red-200 px-2 py-1 text-xs text-red-500 hover:bg-red-50 disabled:opacity-60"
                              >
                                差し戻し
                              </button>
                            )}
                            {cycle?.status === "published" && inv.status === "cancelled" &&
                              !visibleInvoices.some((o) => o.child_id === inv.child_id && o.status !== "cancelled") && (
                              <button
                                onClick={() => runAction("rebuild_child_invoice",
                                  { p_cycle_id: cycle.id, p_child_id: inv.child_id },
                                  `${inv.child_name}さんの請求を再発行しますか?(修正後の内容で下書きを作り直します)`)}
                                disabled={busy}
                                className="rounded border border-sky-200 px-2 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-50 disabled:opacity-60"
                              >
                                再発行
                              </button>
                            )}
                            {cycle?.status === "published" && inv.status === "draft" && (
                              <button
                                onClick={() => runAction("approve_invoice", { p_invoice_id: inv.id },
                                  `${inv.child_name}さんの請求(${yen(inv.total_amount)})を承認しますか?`)}
                                disabled={busy}
                                className="rounded border border-sky-200 px-2 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-50 disabled:opacity-60"
                              >
                                承認
                              </button>
                            )}
                            {cycle?.status === "published" && inv.status === "approved" && (
                              <button
                                onClick={() => runAction("publish_invoice", { p_invoice_id: inv.id },
                                  `${inv.child_name}さんへ公開しますか?(公開通知が送られます・期限=今日+10日)`)}
                                disabled={busy}
                                className="rounded bg-emerald-600 px-2 py-1 text-xs font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                              >
                                公開
                              </button>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                    {visibleInvoices.length === 0 && (
                      <tr><td colSpan={7} className="px-4 py-3 text-sm text-slate-400">請求書はありません</td></tr>
                    )}
                  </tbody>
                </table>
              </section>
            )}
          </div>
        )}
      </main>

      {/* 明細モーダル */}
      {detail && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
          <div className="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-xl bg-white p-5 shadow-xl">
            <div className="flex items-center justify-between">
              <h3 className="text-base font-bold text-slate-800">
                {detail.invoice.child_name}
                <span className="ml-2 font-mono text-xs font-normal text-slate-500">{detail.invoice.invoice_no}</span>
              </h3>
              <button
                onClick={() => setDetail(null)}
                className="rounded-lg border border-slate-300 px-3 py-1 text-sm text-slate-600 hover:bg-slate-50"
              >
                閉じる
              </button>
            </div>
            <table className="mt-3 w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-slate-400">
                  <th className="py-1 pr-2 font-medium">内容</th>
                  <th className="py-1 pr-2 font-medium">対象</th>
                  <th className="py-1 pr-2 text-right font-medium">数量</th>
                  <th className="py-1 pr-2 text-right font-medium">単価</th>
                  <th className="py-1 text-right font-medium">金額</th>
                </tr>
              </thead>
              <tbody>
                {detail.items.map((it) => (
                  <tr key={it.id} className="border-t border-slate-100">
                    <td className="py-1.5 pr-2 text-slate-700">
                      {it.description}
                      {it.is_manual && (
                        <span className="ml-1.5 rounded bg-sky-50 px-1 py-0.5 text-xs text-sky-600">手動</span>
                      )}
                    </td>
                    <td className="py-1.5 pr-2 text-xs text-slate-500">{it.target_period ?? ""}</td>
                    <td className="py-1.5 pr-2 text-right tabular-nums text-slate-600">{it.quantity}</td>
                    <td className="py-1.5 pr-2 text-right tabular-nums text-slate-600">{yen(it.unit_amount)}</td>
                    <td className="py-1.5 text-right font-semibold tabular-nums text-slate-800">
                      {yen(it.amount)}
                      {detail.invoice.status === "draft" && it.is_manual && (
                        <button
                          onClick={() => void handleDeleteManualItem(detail.invoice.id, it)}
                          className="ml-2 text-xs text-red-400 hover:text-red-600"
                          title="手動明細を削除"
                        >
                          ×
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr className="border-t-2 border-slate-300">
                  <td colSpan={4} className="py-2 pr-2 text-right font-bold text-slate-700">合計</td>
                  <td className="py-2 text-right font-bold tabular-nums text-slate-900">{yen(detail.invoice.total_amount)}</td>
                </tr>
              </tfoot>
            </table>
            {detail.invoice.due_date && (
              <p className="mt-2 text-xs text-slate-500">支払期限: {detail.invoice.due_date}</p>
            )}

            {/* 手動明細の追加(下書きのみ・統括のみ=RPC側で強制)。備品もれ・行事費などの実費 */}
            {detail.invoice.status === "draft" && (
              <div className="mt-4 rounded-lg border border-sky-100 bg-sky-50/50 p-3">
                <p className="mb-2 text-xs font-bold text-slate-600">明細を追加(備品もれ・行事費などの実費)</p>
                <div className="flex flex-wrap items-end gap-2">
                  <label className="text-xs text-slate-600">
                    種別
                    <select value={miCat} onChange={(e) => setMiCat(e.target.value)}
                      className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                      {MANUAL_CATEGORIES.map((c) => (
                        <option key={c.value} value={c.value}>{c.label}</option>
                      ))}
                    </select>
                  </label>
                  <label className="text-xs text-slate-600">
                    内容
                    <input type="text" value={miDesc} onChange={(e) => setMiDesc(e.target.value)}
                      placeholder="例: 帽子(7月分もれ)"
                      className="mt-0.5 block w-44 rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                  </label>
                  <label className="text-xs text-slate-600">
                    数量
                    <input type="number" min={1} value={miQty} onChange={(e) => setMiQty(e.target.value)}
                      className="mt-0.5 block w-16 rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                  </label>
                  <label className="text-xs text-slate-600">
                    単価(円)
                    <input type="number" min={0} value={miUnit} onChange={(e) => setMiUnit(e.target.value)}
                      className="mt-0.5 block w-24 rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                  </label>
                  <button
                    onClick={() => {
                      const qty = Number(miQty);
                      const unit = Number(miUnit);
                      if (!miDesc.trim() || miUnit.trim() === "" || !Number.isFinite(qty) || qty <= 0
                          || !Number.isInteger(unit) || unit < 0) {
                        window.alert("内容・数量(1以上)・単価(0円以上の整数)を入力してください");
                        return;
                      }
                      void handleAddManualItem(detail.invoice.id, miCat, miDesc.trim(), qty, unit)
                        .then(() => { setMiDesc(""); setMiQty("1"); setMiUnit(""); });
                    }}
                    disabled={busy}
                    className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
                  >
                    追加
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default function BillingInvoicesPage() {
  return (
    <Suspense fallback={null}>
      <BillingInvoicesPageContent />
    </Suspense>
  );
}
