"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { BulkPromoteChildrenModal } from "@/components/BulkPromoteChildrenModal";
import { ChildcareNav } from "@/components/ChildcareNav";
import { ChildRequiredPeriodModal } from "@/components/ChildRequiredPeriodModal";
import { CreateChildModal } from "@/components/CreateChildModal";
import { WithdrawChildModal } from "@/components/WithdrawChildModal";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { currentDate } from "@/lib/datetime";
import type { ChildcareClass, ChildMasterRow } from "@/lib/types";

const ALL_CLASSES_VALUE = "__all__";

function isCurrentlyRequired(row: ChildMasterRow, today: string): boolean {
  if (row.family_daily_report_required_from) {
    const withinPeriod =
      today >= row.family_daily_report_required_from &&
      (!row.family_daily_report_required_until || today <= row.family_daily_report_required_until);
    if (withinPeriod) return true;
  }
  return row.class_family_daily_report_required ?? false;
}

function ChildcareChildrenPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();

  const [rows, setRows] = useState<ChildMasterRow[]>([]);
  const [classes, setClasses] = useState<ChildcareClass[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [selectedClassName, setSelectedClassName] = useState<string>(ALL_CLASSES_VALUE);
  const [editingRow, setEditingRow] = useState<ChildMasterRow | null>(null);
  const [isPromoting, setIsPromoting] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [withdrawingRow, setWithdrawingRow] = useState<ChildMasterRow | null>(null);

  useEffect(() => {
    function loadRows() {
      if (!selectedOffice) return null;
      setIsLoading(true);
      setRowsError(null);
      return createClient();
    }

    const supabase = loadRows();
    if (!supabase) return;
    supabase
      .rpc("fetch_children_for_office_master", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRows((data ?? []) as ChildMasterRow[]);
      });
    supabase.rpc("fetch_childcare_classes", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (!error) setClasses((data ?? []) as ChildcareClass[]);
    });
  }, [selectedOffice, reloadToken]);

  const classNames = Array.from(
    new Set(rows.map((r) => r.class_name).filter((v): v is string => v != null)),
  );
  const filteredRows =
    selectedClassName === ALL_CLASSES_VALUE ? rows : rows.filter((r) => r.class_name === selectedClassName);
  const today = currentDate();

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
      <main className="flex-1 space-y-6 p-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h2 className="text-lg font-bold text-slate-800">園児マスタ</h2>
            <p className="text-xs text-slate-400">
              連絡帳提出必須は0〜2歳児クラスは全員必須(クラス基準)です。3歳以上のクラスで発達等の理由により
              個別に必須化したい場合のみ、対象園児に適用期間を設定してください。
            </p>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => setIsCreating(true)}
              disabled={classes.length === 0}
              className="rounded-lg border border-sky-300 px-4 py-2 text-sm font-semibold text-sky-700 hover:bg-sky-50 disabled:opacity-50"
            >
              新規園児登録
            </button>
            <button
              onClick={() => setIsPromoting(true)}
              disabled={classes.length === 0}
              className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-50"
            >
              翌年度への進級一括登録
            </button>
          </div>
        </div>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => {
                setSelectedOffice(e.target.value);
                setSelectedClassName(ALL_CLASSES_VALUE);
              }}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices?.map((office) => (
                <option key={office.office_id} value={office.office_id}>
                  {office.office_name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">クラス</label>
            <select
              value={selectedClassName}
              onChange={(e) => setSelectedClassName(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value={ALL_CLASSES_VALUE}>全クラス</option>
              {classNames.map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-4 py-3">園児</th>
                <th className="px-4 py-3">クラス</th>
                <th className="px-4 py-3">生年月日</th>
                <th className="px-4 py-3">在籍状況</th>
                <th className="px-4 py-3">連絡帳提出必須</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr>
                  <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                    読み込み中…
                  </td>
                </tr>
              )}
              {!isLoading && filteredRows.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                    在籍園児がいません
                  </td>
                </tr>
              )}
              {!isLoading &&
                filteredRows.map((row) => {
                  const required = isCurrentlyRequired(row, today);
                  const classDefaultRequired = row.class_family_daily_report_required ?? false;
                  const isWithdrawn = row.enrollment_status === "退園済み";
                  return (
                    <tr
                      key={row.child_id}
                      className={`border-b border-slate-100 last:border-0 hover:bg-slate-50 ${
                        isWithdrawn ? "text-slate-400" : ""
                      }`}
                    >
                      <td className="px-4 py-3 font-medium text-slate-800">
                        {row.display_name}
                        {row.honorific_suffix ?? ""}
                      </td>
                      <td className="px-4 py-3 text-slate-500">{row.class_name ?? "—"}</td>
                      <td className="px-4 py-3 text-slate-500">{row.birth_date}</td>
                      <td className="px-4 py-3">
                        {isWithdrawn ? (
                          <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">
                            退園済み{row.withdrawal_date ? `(${row.withdrawal_date})` : ""}
                          </span>
                        ) : (
                          <span className="text-slate-500">{row.enrollment_status}</span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        {classDefaultRequired ? (
                          <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">
                            クラス基準で必須
                          </span>
                        ) : (
                          <div className="space-y-1">
                            <span
                              className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                                required ? "bg-sky-100 text-sky-700" : "bg-slate-100 text-slate-500"
                              }`}
                            >
                              {required ? "必須(個別設定)" : "任意"}
                            </span>
                            {row.family_daily_report_required_from && (
                              <p className="text-xs text-slate-400">
                                {row.family_daily_report_required_from} 〜{" "}
                                {row.family_daily_report_required_until ?? "無期限"}
                              </p>
                            )}
                          </div>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex justify-end gap-2">
                          {!classDefaultRequired && (
                            <button
                              onClick={() => setEditingRow(row)}
                              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                            >
                              期間設定
                            </button>
                          )}
                          {!isWithdrawn && (
                            <button
                              onClick={() => setWithdrawingRow(row)}
                              className="rounded-lg border border-red-300 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50"
                            >
                              退園
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
            </tbody>
          </table>
        </div>
      </main>

      {editingRow && (
        <ChildRequiredPeriodModal
          row={editingRow}
          onClose={() => setEditingRow(null)}
          onSaved={() => {
            setEditingRow(null);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {isPromoting && (
        <BulkPromoteChildrenModal
          classes={classes}
          rows={rows}
          onClose={() => setIsPromoting(false)}
          onSaved={() => {
            setIsPromoting(false);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {isCreating && (
        <CreateChildModal
          officeId={selectedOffice}
          classes={classes}
          onClose={() => setIsCreating(false)}
          onSaved={() => {
            setIsCreating(false);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {withdrawingRow && (
        <WithdrawChildModal
          row={withdrawingRow}
          onClose={() => setWithdrawingRow(null)}
          onSaved={() => {
            setWithdrawingRow(null);
            setReloadToken((t) => t + 1);
          }}
        />
      )}
    </div>
  );
}

export default function ChildcareChildrenPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareChildrenPageContent />
    </Suspense>
  );
}
