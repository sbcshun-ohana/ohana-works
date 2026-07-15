"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import {
  downloadZenginTransferCsv,
  type PayrollPayer,
  type PayrollRecipient,
} from "@/lib/export/zenginTransferCsv";
import { EventCommutePanel } from "@/components/EventCommutePanel";
import { SpecialDutyAllowancePanel } from "@/components/SpecialDutyAllowancePanel";
import { exportPayrollByOfficeExcel } from "@/lib/export/payrollExport";

function currentYearMonthStr(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

type PayrollRun = {
  id: string;
  target_month: string;
  status: "draft" | "confirmed" | "transferred";
  confirmed_at: string | null;
  transferred_at: string | null;
};

type OfficeOption = { office_id: string; office_name: string };

type PayrollDetailRow = {
  employee_id: string;
  net_pay: number;
  employees: { name: string } | null;
};

type PayrollRunIssue = {
  id: string;
  employee_id: string;
  employee_name: string;
  issue_type: string;
  severity: "error" | "warning";
  message: string;
};

const STATUS_LABEL: Record<PayrollRun["status"], string> = {
  draft: "未確定",
  confirmed: "確定済み",
  transferred: "振込済み",
};

function defaultTransferDate(targetMonth: string): string {
  const [year, month] = targetMonth.split("-").map(Number);
  // 17.1: 支払日は翌月25日(土日祝の前営業日調整は本画面では行わないため管理者が確認・調整する)。
  const nextMonth = new Date(year, month, 25);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${nextMonth.getFullYear()}-${pad(nextMonth.getMonth() + 1)}-${pad(nextMonth.getDate())}`;
}

export default function PayrollPage() {
  const [canManage, setCanManage] = useState<boolean | null>(null);
  const [runs, setRuns] = useState<PayrollRun[]>([]);
  const [runsError, setRunsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const selectedRun = runs.find((r) => r.id === selectedRunId) ?? null;

  const [actionError, setActionError] = useState<string | null>(null);
  const [isActing, setIsActing] = useState(false);

  const [offices, setOffices] = useState<OfficeOption[]>([]);
  const [selectedOfficeId, setSelectedOfficeId] = useState("");
  const [transferDate, setTransferDate] = useState("");
  const [exportError, setExportError] = useState<string | null>(null);
  const [exportNotice, setExportNotice] = useState<string | null>(null);
  const [isExporting, setIsExporting] = useState(false);

  const [isExportingPayrollExcel, setIsExportingPayrollExcel] = useState(false);
  const [payrollExcelError, setPayrollExcelError] = useState<string | null>(null);

  const [payrollDetails, setPayrollDetails] = useState<PayrollDetailRow[]>([]);
  const [payslipError, setPayslipError] = useState<string | null>(null);

  const [issues, setIssues] = useState<PayrollRunIssue[]>([]);
  const [issuesError, setIssuesError] = useState<string | null>(null);

  const [monthlyInputMonth, setMonthlyInputMonth] = useState(currentYearMonthStr());

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("is_labor_manager_plus").then(({ data, error }) => {
      setCanManage(error ? false : Boolean(data));
    });
  }, []);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase
      .from("payroll_runs")
      .select("id, target_month, status, confirmed_at, transferred_at")
      .order("target_month", { ascending: false })
      .then(({ data, error }) => {
        if (error) {
          setRunsError(error.message);
          return;
        }
        setRuns((data ?? []) as PayrollRun[]);
      });
  }, [canManage, reloadToken]);

  useEffect(() => {
    if (!selectedRun) return;
    const supabase = createClient();
    supabase.rpc("compute_payroll_transfer_date", { p_target_month: selectedRun.target_month }).then(({ data, error }) => {
      // RPC失敗時は土日祝未調整のフォールバックを使い、管理者が手動で確認・修正できるようにする。
      setTransferDate(error || !data ? defaultTransferDate(selectedRun.target_month) : (data as string));
    });
  }, [selectedRun]);

  useEffect(() => {
    function sync() {
      if (!selectedRun) {
        setOffices([]);
        setSelectedOfficeId("");
        return null;
      }
      if (selectedRun.status === "draft") {
        setOffices([]);
        return null;
      }
      const supabase = createClient();
      return supabase.rpc("fetch_payroll_run_offices", { p_payroll_run_id: selectedRun.id });
    }

    sync()?.then((result) => {
      if (!result) return;
      const { data, error } = result;
      if (error) {
        setExportError(error.message);
        return;
      }
      const list = (data ?? []) as OfficeOption[];
      setOffices(list);
      setSelectedOfficeId(list[0]?.office_id ?? "");
    });
  }, [selectedRun]);

  useEffect(() => {
    function fetchDetails() {
      if (!selectedRun || selectedRun.status === "draft") {
        setPayrollDetails([]);
        return null;
      }
      const supabase = createClient();
      return supabase
        .from("payroll_details")
        .select("employee_id, net_pay, employees(name)")
        .eq("payroll_run_id", selectedRun.id)
        .order("employee_id");
    }

    fetchDetails()?.then(({ data, error }) => {
      if (error) {
        setPayslipError(error.message);
        return;
      }
      setPayrollDetails((data ?? []) as unknown as PayrollDetailRow[]);
    });
  }, [selectedRun]);

  useEffect(() => {
    if (!selectedRun) {
      setIssues([]);
      return;
    }
    const supabase = createClient();
    supabase.rpc("fetch_payroll_run_issues", { p_payroll_run_id: selectedRun.id }).then(({ data, error }) => {
      if (error) {
        setIssuesError(error.message);
        return;
      }
      setIssues((data ?? []) as PayrollRunIssue[]);
    });
  }, [selectedRun]);

  async function runAction(fn: () => PromiseLike<{ error: { message: string } | null }>) {
    setIsActing(true);
    setActionError(null);
    const { error } = await fn();
    setIsActing(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function handleConfirm(run: PayrollRun) {
    const supabase = createClient();
    await runAction(() => supabase.rpc("confirm_payroll_run", { p_payroll_run_id: run.id }));
  }

  async function handleMarkTransferred(run: PayrollRun) {
    const supabase = createClient();
    await runAction(() => supabase.rpc("mark_payroll_transferred", { p_payroll_run_id: run.id }));
  }

  async function handleUnlock(run: PayrollRun) {
    const reason = window.prompt("確定解除の理由を入力してください(システム最高管理者のみ実行可能):");
    if (!reason || !reason.trim()) return;
    const supabase = createClient();
    await runAction(() =>
      supabase.rpc("unlock_payroll_run", { p_payroll_run_id: run.id, p_reason: reason.trim() }),
    );
  }

  async function handlePayrollExcelExport() {
    if (!selectedRun) return;
    setIsExportingPayrollExcel(true);
    setPayrollExcelError(null);
    try {
      await exportPayrollByOfficeExcel({ payrollRunId: selectedRun.id, targetMonth: selectedRun.target_month });
    } catch (e) {
      setPayrollExcelError(e instanceof Error ? e.message : "エクスポートに失敗しました");
    } finally {
      setIsExportingPayrollExcel(false);
    }
  }

  async function handleExportCsv() {
    if (!selectedRun || !selectedOfficeId) return;
    setIsExporting(true);
    setExportError(null);
    setExportNotice(null);

    const supabase = createClient();
    const [payerRes, recipientsRes] = await Promise.all([
      supabase.rpc("fetch_office_payroll_payer", { p_office_id: selectedOfficeId }),
      supabase.rpc("fetch_payroll_transfer_recipients", {
        p_payroll_run_id: selectedRun.id,
        p_office_id: selectedOfficeId,
      }),
    ]);

    setIsExporting(false);
    if (payerRes.error) {
      setExportError(payerRes.error.message);
      return;
    }
    if (recipientsRes.error) {
      setExportError(recipientsRes.error.message);
      return;
    }
    const payer = (payerRes.data as PayrollPayer[])?.[0];
    if (!payer) {
      setExportError("この施設の支払元口座(bank_accounts)が未設定です");
      return;
    }
    const recipients = (recipientsRes.data ?? []) as PayrollRecipient[];
    const officeName = offices.find((o) => o.office_id === selectedOfficeId)?.office_name ?? "office";
    const { skippedCount } = downloadZenginTransferCsv(
      payer,
      recipients,
      new Date(transferDate),
      `${selectedRun.target_month}_${officeName}`,
    );
    const notices: string[] = [];
    if (!payer.edi_client_code) {
      notices.push("委託者コードが未設定のためゼロ埋めで出力しています。銀行から値が確定次第、支払元口座の設定に登録してください。実際の振込には使用できません。");
    }
    if (skippedCount > 0) {
      notices.push(
        `${skippedCount}名は振込先口座情報(銀行コード・支店コード・カナ名義等)が未登録のため、振込データから除外しました。`,
      );
    }
    if (notices.length > 0) {
      setExportNotice(notices.join(" "));
    }
  }

  if (canManage === null) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-400">読み込み中…</div>
      </div>
    );
  }

  if (!canManage) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">
          この機能を利用する権限がありません(労務管理者以上が必要です)。
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">給与確定・振込データ出力</h2>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <div className="flex items-center justify-between">
            <h3 className="text-base font-bold text-slate-800">月次個別支給の登録・承認</h3>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">対象月</label>
              <input
                type="month"
                value={monthlyInputMonth}
                onChange={(e) => setMonthlyInputMonth(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
          </div>
          <p className="text-xs text-slate-400">
            イベント通勤費・特殊業務手当は、対象月の給与計算を実行する前に登録・承認しておく必要があります。
            承認(confirmed)されていない登録は給与計算に反映されません。
          </p>
        </div>

        <EventCommutePanel month={monthlyInputMonth} />
        <SpecialDutyAllowancePanel month={monthlyInputMonth} />

        {runsError && <p className="text-sm font-medium text-red-500">{runsError}</p>}

        <div className="grid gap-6 lg:grid-cols-[280px_1fr]">
          <div className="space-y-2 rounded-2xl bg-white p-4 shadow-sm">
            {runs.length === 0 && <p className="text-sm text-slate-400">給与計算単位がありません</p>}
            {runs.map((run) => (
              <button
                key={run.id}
                onClick={() => {
                  setSelectedRunId(run.id);
                  setActionError(null);
                  setExportError(null);
                  setExportNotice(null);
                  setPayslipError(null);
                }}
                className={`w-full rounded-lg px-3 py-2 text-left text-sm ${
                  run.id === selectedRunId ? "bg-sky-50 font-semibold text-sky-700" : "hover:bg-slate-50"
                }`}
              >
                <div>{run.target_month}</div>
                <div className="text-xs text-slate-400">{STATUS_LABEL[run.status]}</div>
              </button>
            ))}
          </div>

          <div className="space-y-6">
            {!selectedRun && (
              <div className="rounded-2xl bg-white p-6 text-sm text-slate-400 shadow-sm">
                対象月を選択してください
              </div>
            )}

            {selectedRun && (
              <>
                <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
                  <div className="flex items-center justify-between">
                    <h3 className="text-base font-bold text-slate-800">
                      {selectedRun.target_month} の給与
                    </h3>
                    <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600">
                      {STATUS_LABEL[selectedRun.status]}
                    </span>
                  </div>

                  {actionError && <p className="text-sm font-medium text-red-500">{actionError}</p>}

                  {issuesError && <p className="text-sm font-medium text-red-500">{issuesError}</p>}
                  {issues.length > 0 && (
                    <div className="space-y-2 rounded-xl border border-amber-200 bg-amber-50 p-4">
                      <p className="text-sm font-semibold text-amber-800">
                        計算チェック: {issues.filter((i) => i.severity === "error").length}件のエラー・
                        {issues.filter((i) => i.severity === "warning").length}件の警告
                      </p>
                      <ul className="space-y-1 text-xs">
                        {issues.map((issue) => (
                          <li
                            key={issue.id}
                            className={issue.severity === "error" ? "text-red-600" : "text-amber-700"}
                          >
                            [{issue.severity === "error" ? "エラー" : "警告"}] {issue.message}
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}

                  <div className="flex flex-wrap gap-3">
                    {selectedRun.status === "draft" && (
                      <button
                        onClick={() => handleConfirm(selectedRun)}
                        disabled={isActing}
                        className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
                      >
                        給与を確定する
                      </button>
                    )}
                    {selectedRun.status === "confirmed" && (
                      <>
                        <button
                          onClick={() => handleMarkTransferred(selectedRun)}
                          disabled={isActing}
                          className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                        >
                          振込実行済みにする
                        </button>
                        <button
                          onClick={() => handleUnlock(selectedRun)}
                          disabled={isActing}
                          className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                        >
                          確定解除(システム最高管理者のみ)
                        </button>
                      </>
                    )}
                    {selectedRun.status === "transferred" && (
                      <p className="text-sm text-slate-400">
                        振込実行済みのため、確定解除・再計算はできません(33章)。
                      </p>
                    )}
                  </div>
                </div>

                <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
                  <h3 className="text-base font-bold text-slate-800">施設別給与内訳Excel</h3>
                  <p className="text-xs text-slate-400">
                    施設ごとに、職員番号・氏名・基本給・手当・通勤費・控除額・差引支給額の内訳を確認できるExcelを出力します。
                    振込データ(全銀協CSV)とは別に、給与内容の確認用としてご利用ください。兼務職員は所属施設・兼務施設の両方に行が出力されますが、
                    控除額・差引支給額は所属施設側にのみ表示されます。
                  </p>
                  <button
                    onClick={handlePayrollExcelExport}
                    disabled={isExportingPayrollExcel}
                    className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
                  >
                    {isExportingPayrollExcel ? "出力中…" : "施設別給与Excelダウンロード"}
                  </button>
                  {payrollExcelError && <p className="text-sm font-medium text-red-500">{payrollExcelError}</p>}
                </div>

                {selectedRun.status !== "draft" && (
                  <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
                    <h3 className="text-base font-bold text-slate-800">
                      振込データ出力(全銀協フォーマット)
                    </h3>
                    <p className="text-xs text-slate-400">
                      標準の全銀協「総合振込」固定長フォーマットに基づくベストエフォート出力です。横浜銀行の
                      法人向けインターネットバンキング仕様書での最終確認前に実際の振込へは使用しないでください。
                    </p>
                    <div className="flex flex-wrap items-end gap-4">
                      <div>
                        <label className="mb-1 block text-xs font-medium text-slate-500">施設(支払元口座)</label>
                        <select
                          value={selectedOfficeId}
                          onChange={(e) => setSelectedOfficeId(e.target.value)}
                          className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                        >
                          {offices.map((o) => (
                            <option key={o.office_id} value={o.office_id}>
                              {o.office_name}
                            </option>
                          ))}
                        </select>
                      </div>
                      <div>
                        <label className="mb-1 block text-xs font-medium text-slate-500">取組日</label>
                        <input
                          type="date"
                          value={transferDate}
                          onChange={(e) => setTransferDate(e.target.value)}
                          className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                        />
                        <p className="mt-1 text-xs text-slate-400">
                          翌月25日を基準に土日祝を自動で前営業日へ調整した値を初期表示します。必要に応じて手動で修正できます。
                        </p>
                      </div>
                      <button
                        onClick={handleExportCsv}
                        disabled={isExporting || !selectedOfficeId}
                        className="rounded-lg bg-slate-800 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-900 disabled:opacity-60"
                      >
                        {isExporting ? "出力中…" : "振込データダウンロード"}
                      </button>
                    </div>
                    {exportError && <p className="text-sm font-medium text-red-500">{exportError}</p>}
                    {exportNotice && <p className="text-sm font-medium text-amber-600">{exportNotice}</p>}
                  </div>
                )}

                {selectedRun.status !== "draft" && (
                  <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
                    <h3 className="text-base font-bold text-slate-800">給与明細PDF発行</h3>
                    <p className="text-xs text-slate-400">
                      職員ごとの給与明細PDFを発行します。発行したPDFはpayslipsストレージへ保存され、次回以降は再発行(上書き)されます。
                    </p>
                    {payslipError && <p className="text-sm font-medium text-red-500">{payslipError}</p>}
                    {payrollDetails.length === 0 && (
                      <p className="text-sm text-slate-400">この対象月の給与明細はありません</p>
                    )}
                    <ul className="divide-y divide-slate-100">
                      {payrollDetails.map((d) => (
                        <li key={d.employee_id} className="flex items-center justify-between py-2">
                          <div>
                            <span className="text-sm font-medium text-slate-700">
                              {d.employees?.name ?? "(不明な職員)"}
                            </span>
                            <span className="ml-3 text-sm text-slate-400">
                              {d.net_pay.toLocaleString("ja-JP")}円
                            </span>
                          </div>
                          <a
                            href={`/api/payroll/payslip?payrollRunId=${selectedRun.id}&employeeId=${d.employee_id}`}
                            className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                          >
                            PDFダウンロード
                          </a>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
              </>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
