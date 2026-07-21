"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { CorrectAttendanceModal } from "@/components/CorrectAttendanceModal";
import { WebProxyPunchModal } from "@/components/WebProxyPunchModal";
import { currentYearMonth, formatTime, monthRange } from "@/lib/datetime";
import { exportAttendanceExcel } from "@/lib/export/attendanceExport";
import { PUNCH_TYPE_LABELS, type AttendanceRow, type ManageableOffice, type ProxyPunchLogRow } from "@/lib/types";

const ALL_OFFICES_VALUE = "__all__";

export default function AttendancePage() {
  const [offices, setOffices] = useState<ManageableOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [selectedOffice, setSelectedOffice] = useState<string>("");
  const [yearMonth, setYearMonth] = useState(currentYearMonth());

  const [rows, setRows] = useState<AttendanceRow[]>([]);
  const [isLoadingRows, setIsLoadingRows] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [editingRow, setEditingRow] = useState<AttendanceRow | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [isExporting, setIsExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);
  const [payrollLockStatus, setPayrollLockStatus] = useState<string | null>(null);
  const isLocked = payrollLockStatus === "confirmed" || payrollLockStatus === "transferred";

  const [isProxyPunchOpen, setIsProxyPunchOpen] = useState(false);
  const [proxyLog, setProxyLog] = useState<ProxyPunchLogRow[]>([]);
  const [proxyLogError, setProxyLogError] = useState<string | null>(null);
  const [isLoadingProxyLog, setIsLoadingProxyLog] = useState(false);

  // 代理打刻の対象職員は、当月に勤怠データがある職員から選ぶ(修正ボタンと同じ制約)。
  const employeesInView = Array.from(
    new Map(rows.map((r) => [r.employee_id, r.employee_name])).entries(),
  ).map(([id, name]) => ({ id, name }));

  async function handleExport() {
    setIsExporting(true);
    setExportError(null);
    try {
      await exportAttendanceExcel({
        officeId: selectedOffice === ALL_OFFICES_VALUE ? null : selectedOffice,
        yearMonth,
      });
    } catch (e) {
      setExportError(e instanceof Error ? e.message : "エクスポートに失敗しました");
    } finally {
      setIsExporting(false);
    }
  }

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_manageable_offices").then(({ data, error }) => {
      if (error) {
        setOfficesError(error.message);
        return;
      }
      const list = (data ?? []) as ManageableOffice[];
      setOffices(list);
      if (list.length > 0) {
        setSelectedOffice(list[0].id);
      }
    });
  }, []);

  const canSelectAll = offices?.[0]?.can_select_all ?? false;

  useEffect(() => {
    if (!selectedOffice) return;

    function fetchRows() {
      setIsLoadingRows(true);
      setRowsError(null);

      const { start, end } = monthRange(yearMonth);
      const supabase = createClient();
      return supabase.rpc("fetch_attendance_by_office", {
        p_office_id: selectedOffice === ALL_OFFICES_VALUE ? null : selectedOffice,
        p_month_start: start,
        p_month_end: end,
      });
    }

    fetchRows().then(({ data, error }) => {
      setIsLoadingRows(false);
      if (error) {
        setRowsError(error.message);
        return;
      }
      setRows((data ?? []) as AttendanceRow[]);
    });
  }, [selectedOffice, yearMonth, reloadToken]);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_payroll_lock_status", { p_month: `${yearMonth}-01` }).then(({ data, error }) => {
      setPayrollLockStatus(error ? null : (data as string | null));
    });
  }, [yearMonth, reloadToken]);

  useEffect(() => {
    function clearProxyLog() {
      setProxyLog([]);
    }
    if (!selectedOffice || selectedOffice === ALL_OFFICES_VALUE) {
      clearProxyLog();
      return;
    }

    function fetchProxyLog() {
      setIsLoadingProxyLog(true);
      setProxyLogError(null);
      const { start, end } = monthRange(yearMonth);
      const supabase = createClient();
      return supabase.rpc("fetch_proxy_punches_for_office", {
        p_office_id: selectedOffice,
        p_month_start: start,
        p_month_end: end,
      });
    }

    fetchProxyLog().then(({ data, error }) => {
      setIsLoadingProxyLog(false);
      if (error) {
        setProxyLogError(error.message);
        return;
      }
      setProxyLog((data ?? []) as ProxyPunchLogRow[]);
    });
  }, [selectedOffice, yearMonth, reloadToken]);

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  if (offices !== null && offices.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">
          この機能を利用する権限がありません(主任以上の管理者権限が必要です)。
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">施設別勤怠一覧・実打刻管理</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices?.map((office) => (
                <option key={office.id} value={office.id}>
                  {office.name}
                </option>
              ))}
              {canSelectAll && <option value={ALL_OFFICES_VALUE}>全体</option>}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">対象月</label>
            <input
              type="month"
              value={yearMonth}
              onChange={(e) => setYearMonth(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <button
            onClick={handleExport}
            disabled={isExporting || !selectedOffice}
            className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white transition hover:bg-emerald-700 disabled:opacity-60"
          >
            {isExporting ? "出力中…" : "月間勤怠Excelダウンロード"}
          </button>
          <button
            onClick={() => setIsProxyPunchOpen(true)}
            disabled={isLocked || selectedOffice === ALL_OFFICES_VALUE || employeesInView.length === 0}
            title={
              selectedOffice === ALL_OFFICES_VALUE
                ? "施設を1つ選択してください"
                : employeesInView.length === 0
                  ? "対象月の勤怠データがある職員がいません"
                  : undefined
            }
            className="rounded-lg border border-sky-300 px-4 py-2 text-sm font-semibold text-sky-700 transition hover:bg-sky-50 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-transparent"
          >
            代理打刻(現在時刻)
          </button>
        </div>

        {isLocked && (
          <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
            {payrollLockStatus === "transferred"
              ? `${yearMonth}は振込実行済みのため、勤怠を編集できません(33章)。`
              : `${yearMonth}は給与確定済みのため、勤怠を編集できません。修正が必要な場合は/payroll画面で給与確定を解除してから修正し、再計算・再確定してください(17.4)。`}
          </div>
        )}

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}
        {exportError && <p className="text-sm font-medium text-red-500">{exportError}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-4 py-3">職員</th>
                <th className="px-4 py-3">施設</th>
                <th className="px-4 py-3">日付</th>
                <th className="px-4 py-3">実出勤時刻</th>
                <th className="px-4 py-3">承認済み出勤時刻</th>
                <th className="px-4 py-3">実退勤時刻</th>
                <th className="px-4 py-3">承認済み退勤時刻</th>
                <th className="px-4 py-3">承認済み休憩(分)</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {isLoadingRows && (
                <tr>
                  <td colSpan={9} className="px-4 py-6 text-center text-slate-400">
                    読み込み中…
                  </td>
                </tr>
              )}
              {!isLoadingRows && rows.length === 0 && (
                <tr>
                  <td colSpan={9} className="px-4 py-6 text-center text-slate-400">
                    対象の勤怠データはありません
                  </td>
                </tr>
              )}
              {!isLoadingRows &&
                rows.map((row) => (
                  <tr
                    key={`${row.employee_id}-${row.work_date}`}
                    className="border-b border-slate-100 last:border-0 hover:bg-slate-50"
                  >
                    <td className="px-4 py-3 font-medium text-slate-800">{row.employee_name}</td>
                    <td className="px-4 py-3 text-slate-500">{row.office_name}</td>
                    <td className="px-4 py-3 text-slate-500">{row.work_date}</td>
                    <td className="px-4 py-3 text-slate-700">{formatTime(row.actual_clock_in_at)}</td>
                    <td className="px-4 py-3 text-sky-700">{formatTime(row.approved_work_start_at)}</td>
                    <td className="px-4 py-3 text-slate-700">{formatTime(row.actual_clock_out_at)}</td>
                    <td className="px-4 py-3 text-sky-700">{formatTime(row.approved_work_end_at)}</td>
                    <td className="px-4 py-3 text-slate-500">{row.approved_break_minutes ?? "—"}</td>
                    <td className="px-4 py-3 text-right">
                      <button
                        onClick={() => setEditingRow(row)}
                        disabled={isLocked}
                        title={isLocked ? "給与確定済みのため編集できません" : undefined}
                        className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-transparent"
                      >
                        修正
                      </button>
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>

        {selectedOffice !== ALL_OFFICES_VALUE && (
          <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
            <h3 className="text-base font-bold text-slate-800">代理打刻ログ(監査)</h3>
            <p className="text-xs text-slate-500">
              キオスク(iPad、管理者コード入力)とWeb(この画面)どちらの代理打刻もまとめて表示します。
            </p>
            {proxyLogError && <p className="text-sm font-medium text-red-500">{proxyLogError}</p>}
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                    <th className="px-4 py-3">対象職員</th>
                    <th className="px-4 py-3">打刻種別</th>
                    <th className="px-4 py-3">打刻日時</th>
                    <th className="px-4 py-3">代理操作者</th>
                    <th className="px-4 py-3">経路</th>
                    <th className="px-4 py-3">備考</th>
                  </tr>
                </thead>
                <tbody>
                  {isLoadingProxyLog && (
                    <tr>
                      <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                        読み込み中…
                      </td>
                    </tr>
                  )}
                  {!isLoadingProxyLog && proxyLog.length === 0 && (
                    <tr>
                      <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                        対象月の代理打刻記録はありません
                      </td>
                    </tr>
                  )}
                  {!isLoadingProxyLog &&
                    proxyLog.map((log) => (
                      <tr key={log.id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                        <td className="px-4 py-3 font-medium text-slate-800">{log.employee_name}</td>
                        <td className="px-4 py-3 text-slate-700">{PUNCH_TYPE_LABELS[log.punch_type]}</td>
                        <td className="px-4 py-3 text-slate-500">
                          {new Date(log.punched_at).toLocaleString("ja-JP")}
                        </td>
                        <td className="px-4 py-3 text-slate-500">{log.proxy_operator_name}</td>
                        <td className="px-4 py-3">
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                              log.source_label === "Web"
                                ? "bg-sky-50 text-sky-700"
                                : "bg-slate-100 text-slate-600"
                            }`}
                          >
                            {log.source_label}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-slate-500">{log.note ?? "—"}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </main>

      {editingRow && (
        <CorrectAttendanceModal
          row={editingRow}
          onClose={() => setEditingRow(null)}
          onSaved={() => {
            setEditingRow(null);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {isProxyPunchOpen && (
        <WebProxyPunchModal
          employees={employeesInView}
          onClose={() => setIsProxyPunchOpen(false)}
          onSaved={() => {
            setIsProxyPunchOpen(false);
            setReloadToken((t) => t + 1);
          }}
        />
      )}
    </div>
  );
}
