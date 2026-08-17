"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { BulkPromoteChildrenModal } from "@/components/BulkPromoteChildrenModal";
import { ChildInternalNotesModal } from "@/components/ChildInternalNotesModal";
import { ChildRequiredPeriodModal } from "@/components/ChildRequiredPeriodModal";
import { ChildTherapySettingModal } from "@/components/ChildTherapySettingModal";
import { ChildWeeklyScheduleModal } from "@/components/ChildWeeklyScheduleModal";
import { CreateChildModal } from "@/components/CreateChildModal";
import { InvitationQrModal } from "@/components/InvitationQrModal";
import { ProvisionalChildModal } from "@/components/ProvisionalChildModal";
import { WithdrawChildModal } from "@/components/WithdrawChildModal";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { classOrderIndex, compareByClassThenName } from "@/lib/childcareClassSort";
import { currentDate } from "@/lib/datetime";
import type { ChildMasterRow } from "@/lib/types";

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
  // 施設選択はヘッダーに集約。selectedOffice は useChildcareOffices が ?office= に追随して供給する。
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;
  const { classes, selectedClass, setSelectedClass, selectedClassName } = useChildcareClass(selectedOffice);

  const [rows, setRows] = useState<ChildMasterRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [editingRow, setEditingRow] = useState<ChildMasterRow | null>(null);
  const [isPromoting, setIsPromoting] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [isProvisioning, setIsProvisioning] = useState(false);
  const [qrRow, setQrRow] = useState<ChildMasterRow | null>(null);
  const [withdrawingRow, setWithdrawingRow] = useState<ChildMasterRow | null>(null);
  const [internalNotesRow, setInternalNotesRow] = useState<ChildMasterRow | null>(null);
  const [internalNotesEnabled, setInternalNotesEnabled] = useState(false);
  const [therapyRow, setTherapyRow] = useState<ChildMasterRow | null>(null);
  const [therapyEnabled, setTherapyEnabled] = useState(false);
  const [weeklyRow, setWeeklyRow] = useState<ChildMasterRow | null>(null);

  // 園内記録機能フラグ(施設単位)。ONの施設のみボタンを表示する
  useEffect(() => {
    function load() {
      if (!selectedOffice) {
        setInternalNotesEnabled(false);
        return;
      }
      const supabase = createClient();
      supabase
        .rpc("is_child_internal_notes_enabled_for_office", { p_office_id: selectedOffice })
        .then(({ data }) => setInternalNotesEnabled(Boolean(data)));
      supabase
        .rpc("is_therapy_outing_enabled_for_office", { p_office_id: selectedOffice })
        .then(({ data }) => setTherapyEnabled(Boolean(data)));
    }
    load();
  }, [selectedOffice]);

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
  }, [selectedOffice, reloadToken]);

  const classOrder = classOrderIndex(classes);
  // 入園予定(仮登録)は本体の表と分けて表示する(クラス未所属・基本情報未入力のため)
  const provisionalRows = rows.filter((r) => r.enrollment_status === "入園予定");
  const enrolledRows = rows.filter((r) => r.enrollment_status !== "入園予定");
  const filteredRows = (selectedClassName === null ? enrolledRows : enrolledRows.filter((r) => r.class_name === selectedClassName))
    .slice()
    .sort((a, b) => compareByClassThenName(classOrder, a.class_name, a.display_name, b.class_name, b.display_name));
  const today = currentDate();

  async function toggleChildKind(row: ChildMasterRow) {
    const nextKind = row.child_kind === "temporary" ? "regular" : "temporary";
    const label = nextKind === "temporary" ? "一時預かり" : "通常在籍";
    if (!window.confirm(`${row.display_name}${row.honorific_suffix ?? ""}の在籍種別を「${label}」に変更しますか?`)) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("set_child_kind", {
      p_child_id: row.child_id,
      p_child_kind: nextKind,
    });
    if (error) {
      setRowsError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function cancelProvisionalChild(row: ChildMasterRow) {
    if (!window.confirm(`${row.full_name}さんの仮登録を取り消しますか?(退園済み扱いになります)`)) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("withdraw_child", {
      p_child_id: row.child_id,
      p_withdrawal_date: today,
    });
    if (error) {
      setRowsError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

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
              onClick={() => setIsProvisioning(true)}
              className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50"
            >
              仮登録(入園予定)
            </button>
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
            <label className="mb-1 block text-xs font-medium text-slate-500">クラス</label>
            <select
              value={selectedClass}
              onChange={(e) => setSelectedClass(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="">全クラス</option>
              {classes.map((c) => (
                <option key={c.class_id} value={c.class_id}>
                  {c.class_name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        {provisionalRows.length > 0 && (
          <div className="space-y-2 rounded-2xl bg-white p-4 shadow-sm">
            <h3 className="text-sm font-bold text-slate-700">入園予定(仮登録)</h3>
            <p className="text-xs text-slate-400">
              園児名だけの仮登録です。登園ボード・在園児一覧には表示されません。招待QRから保護者アカウントの準備を進められます。
            </p>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                    <th className="px-4 py-2">園児名</th>
                    <th className="px-4 py-2">ふりがな</th>
                    <th className="px-4 py-2">入園予定日</th>
                    <th className="px-4 py-2" />
                  </tr>
                </thead>
                <tbody>
                  {provisionalRows.map((row) => (
                    <tr key={row.child_id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                      <td className="px-4 py-2 font-medium text-slate-800">{row.full_name}</td>
                      <td className="px-4 py-2 text-slate-500">{row.name_kana ?? "—"}</td>
                      <td className="px-4 py-2 text-slate-500">{row.enrollment_date ?? "未定"}</td>
                      <td className="px-4 py-2 text-right">
                        <div className="flex justify-end gap-2">
                          <button
                            onClick={() => setQrRow(row)}
                            className="rounded-lg border border-sky-300 px-3 py-1 text-xs font-medium text-sky-700 hover:bg-sky-50"
                          >
                            招待QR
                          </button>
                          <button
                            onClick={() => cancelProvisionalChild(row)}
                            className="rounded-lg border border-red-300 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50"
                          >
                            取消
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

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
                        {row.child_kind === "temporary" && (
                          <span className="ml-2 rounded-full bg-violet-50 px-2 py-0.5 text-xs font-semibold text-violet-600">
                            一時預かり
                          </span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-slate-500">{row.class_name ?? "—"}</td>
                      <td className="px-4 py-3 text-slate-500">{row.birth_date ?? "—"}</td>
                      <td className="px-4 py-3">
                        {isWithdrawn ? (
                          <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">
                            退園済み{row.withdrawal_date ? `(${row.withdrawal_date})` : ""}
                          </span>
                        ) : (
                          <div className="space-y-1">
                            <span className="block text-slate-500">{row.enrollment_status}</span>
                            {isManager && (
                              <button
                                onClick={() => toggleChildKind(row)}
                                className="text-xs text-slate-400 underline hover:text-slate-600"
                              >
                                {row.child_kind === "temporary" ? "通常在籍に戻す" : "一時預かりにする"}
                              </button>
                            )}
                          </div>
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
                          {internalNotesEnabled && (
                            <button
                              onClick={() => setInternalNotesRow(row)}
                              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                            >
                              園内記録
                            </button>
                          )}
                          {!classDefaultRequired && (
                            <button
                              onClick={() => setEditingRow(row)}
                              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                            >
                              期間設定
                            </button>
                          )}
                          <button
                            onClick={() => setWeeklyRow(row)}
                            className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                          >
                            週次予定
                          </button>
                          {therapyEnabled && (
                            <button
                              onClick={() => setTherapyRow(row)}
                              className="rounded-lg border border-violet-300 px-3 py-1 text-xs font-medium text-violet-600 hover:bg-violet-50"
                            >
                              療育設定
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

      {therapyRow && (
        <ChildTherapySettingModal
          row={therapyRow}
          officeName={offices?.find((o) => o.office_id === selectedOffice)?.office_name ?? ""}
          onClose={() => setTherapyRow(null)}
        />
      )}

      {weeklyRow && (
        <ChildWeeklyScheduleModal
          row={weeklyRow}
          isManager={isManager}
          onClose={() => setWeeklyRow(null)}
          onSaved={() => setWeeklyRow(null)}
        />
      )}

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

      {isProvisioning && (
        <ProvisionalChildModal
          officeId={selectedOffice}
          onClose={() => setIsProvisioning(false)}
          onSaved={() => {
            setIsProvisioning(false);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {qrRow && (
        <InvitationQrModal
          childId={qrRow.child_id}
          childName={qrRow.full_name}
          onClose={() => setQrRow(null)}
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

      {internalNotesRow && (
        <ChildInternalNotesModal
          childId={internalNotesRow.child_id}
          childName={`${internalNotesRow.display_name}${internalNotesRow.honorific_suffix ?? ""}`}
          officeId={selectedOffice}
          onClose={() => setInternalNotesRow(null)}
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
