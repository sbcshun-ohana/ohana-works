"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { BulkPromoteChildrenModal } from "@/components/BulkPromoteChildrenModal";
import { ChildClassChangeModal } from "@/components/ChildClassChangeModal";
import { ChildContractModal } from "@/components/ChildContractModal";
import { ChildDevelopmentModal } from "@/components/ChildDevelopmentModal";
import { ChildKahaiPeriodModal } from "@/components/ChildKahaiPeriodModal";
import { DevelopmentApprovalPanel } from "@/components/DevelopmentApprovalPanel";
import { ChildRegisterEditModal } from "@/components/ChildRegisterEditModal";
import { ChildTherapySettingModal } from "@/components/ChildTherapySettingModal";
import { ChildWeeklyScheduleModal } from "@/components/ChildWeeklyScheduleModal";
import { CreateChildModal } from "@/components/CreateChildModal";
import { InvitationQrModal } from "@/components/InvitationQrModal";
import { PromoteProvisionalChildModal } from "@/components/PromoteProvisionalChildModal";
import { ProvisionalChildModal } from "@/components/ProvisionalChildModal";
import { WithdrawChildModal } from "@/components/WithdrawChildModal";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { classOrderIndex, compareByClassThenName } from "@/lib/childcareClassSort";
import type { ChildMasterRow } from "@/lib/types";

// 連絡帳提出必須 = クラス基準(0-2歳) OR 加配期間中(295で一本化)。加配期間は kahaiActive で判定。

function ChildcareChildrenPageContent() {
  // 施設選択はヘッダーに集約。selectedOffice は useChildcareOffices が ?office= に追随して供給する。
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;
  const { classes, selectedClass, setSelectedClass, selectedClassName } = useChildcareClass(selectedOffice);

  const [rows, setRows] = useState<ChildMasterRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [isPromoting, setIsPromoting] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [isProvisioning, setIsProvisioning] = useState(false);
  const [qrRow, setQrRow] = useState<ChildMasterRow | null>(null);
  const [promoteRow, setPromoteRow] = useState<ChildMasterRow | null>(null);
  const [registerEditRow, setRegisterEditRow] = useState<ChildMasterRow | null>(null);
  const [classChangeRow, setClassChangeRow] = useState<ChildMasterRow | null>(null);
  const [withdrawingRow, setWithdrawingRow] = useState<ChildMasterRow | null>(null);
  const [therapyRow, setTherapyRow] = useState<ChildMasterRow | null>(null);
  const [therapyEnabled, setTherapyEnabled] = useState(false);
  const [weeklyRow, setWeeklyRow] = useState<ChildMasterRow | null>(null);
  const [developmentRow, setDevelopmentRow] = useState<ChildMasterRow | null>(null);
  const [developmentEnabled, setDevelopmentEnabled] = useState(false);
  const [kahaiActive, setKahaiActive] = useState<Set<string>>(new Set()); // 本日時点で加配適用中の child_id
  const [kahaiRow, setKahaiRow] = useState<ChildMasterRow | null>(null);   // 加配期間モーダル対象
  const [billingEnabled, setBillingEnabled] = useState(false);             // 請求フラグ(契約ボタン表示)
  const [contractRow, setContractRow] = useState<ChildMasterRow | null>(null); // 契約モーダル対象
  // 免除書類の確認待ちアラート(391・統括のみ返る。確認完了まで出続ける=俊要望 2026-08-28)
  const [exemptionAlerts, setExemptionAlerts] = useState<
    { child_id: string; child_name: string; kind: string; document_state: string; document_fiscal_year: number | null; start_month: string }[]
  >([]);

  // 園内記録機能フラグ(施設単位)。ONの施設のみボタンを表示する
  // 施設切替のステール応答ガード(314/394): 遅れて届いた前施設の応答で上書きしない
  useEffect(() => {
    if (!selectedOffice) return;
    let stale = false;
    const supabase = createClient();
    supabase
      .rpc("is_therapy_outing_enabled_for_office", { p_office_id: selectedOffice })
      .then(({ data }) => { if (!stale) setTherapyEnabled(Boolean(data)); });
    supabase
      .rpc("is_development_records_enabled_for_office", { p_office_id: selectedOffice })
      .then(({ data }) => { if (!stale) setDevelopmentEnabled(Boolean(data)); });
    supabase
      .rpc("is_billing_enabled_for_office", { p_office_id: selectedOffice })
      .then(({ data }) => { if (!stale) setBillingEnabled(Boolean(data)); });
    return () => { stale = true; };
  }, [selectedOffice]);

  useEffect(() => {
    if (!selectedOffice) return;
    let stale = false;
    setIsLoading(true);
    setRowsError(null);
    const supabase = createClient();
    supabase
      .rpc("fetch_children_for_office_master", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        if (stale) return;
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRows((data ?? []) as ChildMasterRow[]);
      });
    // 加配(個人案対象・291)。本日時点で適用中の児をバッジ表示。期間・履歴はモーダルで編集。
    supabase
      .rpc("fetch_children_kahai_active", { p_office_id: selectedOffice, p_ref_date: new Date().toISOString().slice(0, 10) })
      .then(({ data }) => {
        if (stale) return;
        setKahaiActive(new Set((data ?? []).map((r: { child_id: string }) => r.child_id)));
      });
    // 免除書類の確認待ちアラート(391)。統括以外・フラグOFFはエラー=黙って空(バナー非表示)。
    // 契約モーダルを閉じるとreloadTokenが進み再取得される(確認済みにすると消える)。
    // ステールガード必須: 免除アラートは機微情報のため他施設への誤表示を防ぐ(394)。
    supabase
      .rpc("fetch_pending_exemption_alerts", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        if (stale) return;
        setExemptionAlerts(error ? [] : ((data ?? []) as typeof exemptionAlerts));
      });
    return () => { stale = true; };
  }, [selectedOffice, reloadToken]);

  const classOrder = classOrderIndex(classes);
  // 入園予定(仮登録)は本体の表と分けて表示する(クラス未所属・基本情報未入力のため)
  const provisionalRows = rows.filter((r) => r.enrollment_status === "入園予定");
  const enrolledRows = rows.filter((r) => r.enrollment_status !== "入園予定");
  const filteredRows = (selectedClassName === null ? enrolledRows : enrolledRows.filter((r) => r.class_name === selectedClassName))
    .slice()
    .sort((a, b) => compareByClassThenName(classOrder, a.class_name, a.display_name, b.class_name, b.display_name));

  async function cancelProvisionalChild(row: ChildMasterRow) {
    if (!window.confirm(`${row.full_name}さんの仮登録を取り消しますか?(退園済み扱いになります)`)) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("withdraw_child", {
      p_child_id: row.child_id,
      p_withdrawal_date: new Date().toISOString().slice(0, 10),
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
              連絡帳提出必須は0〜2歳児クラスは全員必須(クラス基準)です。3歳以上のクラスは、
              「加配」に期間を登録するとその期間中のみ連絡帳提出が必須(かつ月案に個人案が必要)になります。
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

        {developmentEnabled && isManager && selectedOffice && (
          <DevelopmentApprovalPanel officeId={selectedOffice} />
        )}

        {/* 免除書類の確認待ちアラート(統括のみ表示・確認完了まで出続ける) */}
        {exemptionAlerts.length > 0 && (
          <div className="rounded-2xl border border-amber-300 bg-amber-50 p-4 shadow-sm">
            <p className="text-sm font-bold text-amber-800">
              ⚠ 免除書類の確認が必要です({exemptionAlerts.length}件)
            </p>
            <ul className="mt-2 space-y-1">
              {exemptionAlerts.map((a) => {
                const target = rows.find((r) => r.child_id === a.child_id);
                return (
                  <li key={`${a.child_id}-${a.kind}-${a.start_month}`} className="flex items-center gap-2 text-sm text-amber-900">
                    <span className={`rounded px-1.5 py-0.5 text-xs font-semibold ${
                      a.document_state === "deficient" ? "bg-red-100 text-red-600" : "bg-amber-100 text-amber-700"}`}>
                      {a.document_state === "deficient" ? "不備あり" : "書類確認待ち"}
                    </span>
                    <span className="font-medium">{a.child_name}</span>
                    <span className="text-amber-700">
                      {{ free_childcare: "無償化(保育料)", meal_main: "主食費免除", meal_side: "副食費免除",
                         company_paid: "会社負担", custom: "個別免除" }[a.kind] ?? a.kind}
                      {a.document_fiscal_year ? `(${a.document_fiscal_year}年度)` : ""}
                    </span>
                    {target && (
                      <button
                        onClick={() => setContractRow(target)}
                        className="rounded border border-amber-300 px-2 py-0.5 text-xs font-semibold text-amber-800 hover:bg-amber-100"
                      >
                        契約を開く
                      </button>
                    )}
                  </li>
                );
              })}
            </ul>
          </div>
        )}

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
                            onClick={() => setRegisterEditRow(row)}
                            className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                          >
                            園児情報
                          </button>
                          <button
                            onClick={() => setQrRow(row)}
                            className="rounded-lg border border-sky-300 px-3 py-1 text-xs font-medium text-sky-700 hover:bg-sky-50"
                          >
                            招待QR
                          </button>
                          <button
                            onClick={() => setPromoteRow(row)}
                            disabled={classes.length === 0}
                            className="rounded-lg bg-sky-500 px-3 py-1 text-xs font-semibold text-white hover:bg-sky-600 disabled:opacity-50"
                          >
                            正式入園
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
                  const kahaiOn = kahaiActive.has(row.child_id);
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
                          // 在籍種別の変更は「園児情報」編集モーダル内に集約(俊指示 2026-08-17: 一覧のリンクは誤操作防止のため廃止)
                          <span className="text-slate-500">{row.enrollment_status}</span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        {classDefaultRequired ? (
                          <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">
                            クラス基準で必須
                          </span>
                        ) : (
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                              kahaiOn ? "bg-violet-100 text-violet-700" : "bg-slate-100 text-slate-500"
                            }`}
                          >
                            {kahaiOn ? "必須(加配期間中)" : "任意"}
                          </span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex justify-end gap-2">
                          <button
                            onClick={() => setRegisterEditRow(row)}
                            className="rounded-lg border border-sky-300 px-3 py-1 text-xs font-medium text-sky-700 hover:bg-sky-50"
                          >
                            園児情報
                          </button>
                          {!isWithdrawn && (
                            <button
                              onClick={() => setClassChangeRow(row)}
                              disabled={classes.length === 0}
                              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-50"
                            >
                              クラス変更
                            </button>
                          )}
                          {developmentEnabled && (
                            <button
                              onClick={() => setDevelopmentRow(row)}
                              className="rounded-lg border border-emerald-300 px-3 py-1 text-xs font-medium text-emerald-700 hover:bg-emerald-50"
                            >
                              発達記録
                            </button>
                          )}
                          {isManager && !isWithdrawn && (
                            <button
                              onClick={() => setKahaiRow(row)}
                              className={`rounded-lg border px-3 py-1 text-xs font-medium ${
                                kahaiActive.has(row.child_id)
                                  ? "border-violet-400 bg-violet-50 text-violet-700"
                                  : "border-slate-300 text-slate-500 hover:bg-slate-100"
                              }`}
                              title="加配(個人案の対象)の期間・履歴を設定。3〜5歳児で加配期間中は月案に個人案が必要"
                            >
                              加配{kahaiActive.has(row.child_id) ? "：適用中" : ""}
                            </button>
                          )}
                          <button
                            onClick={() => setWeeklyRow(row)}
                            className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                          >
                            週次予定
                          </button>
                          {billingEnabled && (
                            <button
                              onClick={() => setContractRow(row)}
                              className="rounded-lg border border-emerald-300 px-3 py-1 text-xs font-medium text-emerald-700 hover:bg-emerald-50"
                              title="契約プラン・月極延長・免除(統括のみ)の登録と履歴"
                            >
                              契約
                            </button>
                          )}
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

      {contractRow && (
        <ChildContractModal
          row={contractRow}
          officeId={selectedOffice}
          onClose={() => { setContractRow(null); setReloadToken((t) => t + 1); }}
        />
      )}

      {kahaiRow && (
        <ChildKahaiPeriodModal
          childId={kahaiRow.child_id}
          childName={kahaiRow.display_name}
          onClose={() => { setKahaiRow(null); setReloadToken((t) => t + 1); }}
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

      {classChangeRow && (
        <ChildClassChangeModal
          row={classChangeRow}
          classes={classes}
          onClose={() => setClassChangeRow(null)}
          onSaved={() => {
            setClassChangeRow(null);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {registerEditRow && (
        <ChildRegisterEditModal
          row={registerEditRow}
          onClose={() => setRegisterEditRow(null)}
          onSaved={() => {
            setRegisterEditRow(null);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {promoteRow && (
        <PromoteProvisionalChildModal
          row={promoteRow}
          classes={classes}
          onClose={() => setPromoteRow(null)}
          onSaved={() => {
            setPromoteRow(null);
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

      {developmentRow && (
        <ChildDevelopmentModal
          childId={developmentRow.child_id}
          childName={`${developmentRow.display_name}${developmentRow.honorific_suffix ?? ""}`}
          officeId={selectedOffice}
          isManager={isManager}
          onClose={() => setDevelopmentRow(null)}
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
