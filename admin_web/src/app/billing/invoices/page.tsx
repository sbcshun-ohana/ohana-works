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
  category: string;
  description: string;
  target_period: string | null;
  quantity: number;
  unit_amount: number | null;
  amount: number;
};

type InvoiceDetail = {
  invoice: {
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

  const cycle = data?.cycle ?? null;
  const cycleStatus = cycle ? CYCLE_STATUS_LABELS[cycle.status] : null;
  const errorChecks = (data?.checks ?? []).filter((c) => c.severity === "error");
  const warnChecks = (data?.checks ?? []).filter((c) => c.severity === "warning");
  const infoChecks = (data?.checks ?? []).filter((c) => c.severity === "info");

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
                          "保護者へ公開しますか?(公開後は取消できません・支払期限=公開日+10日)")}
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
                </div>
              </div>
              {actionError && <p className="mt-2 text-sm font-medium text-red-500">{actionError}</p>}
            </section>

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
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-xs text-slate-400">
                      <th className="px-4 py-2 font-medium">請求番号</th>
                      <th className="px-2 py-2 font-medium">園児</th>
                      <th className="px-2 py-2 text-right font-medium">金額</th>
                      <th className="px-2 py-2 font-medium">状態</th>
                      <th className="px-2 py-2 font-medium">支払期限</th>
                      <th className="px-4 py-2 text-right font-medium"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.invoices.map((inv) => (
                      <tr key={inv.id} className="border-t border-slate-100">
                        <td className="px-4 py-2 font-mono text-xs text-slate-600">{inv.invoice_no}</td>
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
                          <button
                            onClick={() => openDetail(inv)}
                            className="rounded border border-slate-200 px-2 py-1 text-xs text-slate-500 hover:bg-slate-50"
                          >
                            明細
                          </button>
                        </td>
                      </tr>
                    ))}
                    {data.invoices.length === 0 && (
                      <tr><td colSpan={6} className="px-4 py-3 text-sm text-slate-400">請求書はありません</td></tr>
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
                {detail.items.map((it, idx) => (
                  <tr key={idx} className="border-t border-slate-100">
                    <td className="py-1.5 pr-2 text-slate-700">{it.description}</td>
                    <td className="py-1.5 pr-2 text-xs text-slate-500">{it.target_period ?? ""}</td>
                    <td className="py-1.5 pr-2 text-right tabular-nums text-slate-600">{it.quantity}</td>
                    <td className="py-1.5 pr-2 text-right tabular-nums text-slate-600">{yen(it.unit_amount)}</td>
                    <td className="py-1.5 text-right font-semibold tabular-nums text-slate-800">{yen(it.amount)}</td>
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
