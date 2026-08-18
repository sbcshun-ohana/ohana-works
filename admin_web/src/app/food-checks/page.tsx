"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { DailyEliminationPanel } from "@/components/DailyEliminationPanel";
import { MealStatusSection } from "@/components/MealStatusSection";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

type SymptomRow = {
  record_id: string;
  child_id: string;
  child_name: string;
  food_name: string;
  intake_date: string;
  symptoms: string;
  onset_note: string | null;
  amount_note: string | null;
  medical_status: string | null;
  note: string | null;
  created_at: string;
  confirmed: boolean;
  confirmed_at: string | null;
  confirm_note: string | null;
};

/// 食材チェック(M6 Phase 4・224)。保護者からの「症状あり」報告の確認(管理者以上)。
/// 園が確認するまで未処理として上部に残る(草案§14.4)。マスターの版管理UIは後続対応。
function FoodChecksPageContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const [rows, setRows] = useState<SymptomRow[]>([]);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const [confirmTarget, setConfirmTarget] = useState<SymptomRow | null>(null);
  const [confirmNote, setConfirmNote] = useState("");
  const [isActing, setIsActing] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    if (!selectedOffice) return;
    setIsLoading(true);
    setRowsError(null);
    const supabase = createClient();
    supabase.rpc("fetch_food_symptom_queue", { p_office_id: selectedOffice }).then(({ data, error }) => {
      setIsLoading(false);
      if (error) {
        setRowsError(
          error.message.includes("not authorized")
            ? "このページは管理者以上(園長・統括)のみ利用できます"
            : error.message,
        );
        setRows([]);
        return;
      }
      setRows((data ?? []) as SymptomRow[]);
    });
  }, [selectedOffice, reloadToken]);

  async function handleConfirm() {
    if (!confirmTarget) return;
    setIsActing(true);
    setActionError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("confirm_food_symptom", {
      p_record_id: confirmTarget.record_id,
      p_note: confirmNote.trim() || null,
    });
    setIsActing(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    setConfirmTarget(null);
    setConfirmNote("");
    reload();
  }

  const pending = rows.filter((r) => !r.confirmed);
  const confirmed = rows.filter((r) => r.confirmed);

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">保育業務の施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <div>
          <h2 className="text-lg font-bold text-slate-800">食材チェック・給食管理</h2>
          <p className="text-xs text-slate-400">
            保護者からの「症状あり」報告の確認と、給食段階(後期食/完了食/幼児食)の承認・アレルギー診断書の管理を行います(管理者以上)。
          </p>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        {!rowsError && selectedOffice && <DailyEliminationPanel officeId={selectedOffice} />}

        {!rowsError && selectedOffice && <MealStatusSection officeId={selectedOffice} />}

        <section className="space-y-2">
          <h3 className="text-sm font-bold text-red-600">未処理({pending.length}件)</h3>
          {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}
          {!isLoading && pending.length === 0 && (
            <p className="rounded-xl bg-white p-4 text-sm text-slate-400 shadow-sm">未処理の報告はありません</p>
          )}
          {pending.map((r) => (
            <div key={r.record_id} className="rounded-xl border border-red-200 bg-red-50/50 p-4">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div>
                  <p className="text-sm font-bold text-slate-800">
                    {r.child_name} / {r.food_name}
                    <span className="ml-2 text-xs font-normal text-slate-500">摂取日: {r.intake_date}</span>
                  </p>
                  <p className="mt-1 text-sm text-slate-700">症状: {r.symptoms}</p>
                  <p className="mt-0.5 text-xs text-slate-500">
                    {r.onset_note && `発症: ${r.onset_note} / `}
                    {r.amount_note && `摂取量: ${r.amount_note} / `}
                    {r.medical_status && `受診: ${r.medical_status}`}
                  </p>
                  {r.note && <p className="mt-0.5 text-xs text-slate-500">備考: {r.note}</p>}
                  <p className="mt-1 text-xs text-slate-400">報告: {new Date(r.created_at).toLocaleString("ja-JP")}</p>
                </div>
                <button
                  onClick={() => setConfirmTarget(r)}
                  className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
                >
                  確認する
                </button>
              </div>
            </div>
          ))}
        </section>

        <section className="space-y-2">
          <h3 className="text-sm font-bold text-slate-500">確認済み({confirmed.length}件)</h3>
          {confirmed.map((r) => (
            <div key={r.record_id} className="rounded-xl bg-white p-4 shadow-sm">
              <p className="text-sm text-slate-700">
                {r.child_name} / {r.food_name}
                <span className="ml-2 text-xs text-slate-400">摂取日: {r.intake_date}</span>
              </p>
              <p className="mt-0.5 text-xs text-slate-500">症状: {r.symptoms}</p>
              <p className="mt-0.5 text-xs text-slate-400">
                確認: {r.confirmed_at ? new Date(r.confirmed_at).toLocaleString("ja-JP") : ""}
                {r.confirm_note && ` / メモ: ${r.confirm_note}`}
              </p>
            </div>
          ))}
        </section>
      </main>

      {confirmTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
          <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-lg">
            <h2 className="mb-1 text-base font-bold text-slate-800">症状報告の確認</h2>
            <p className="mb-3 text-sm text-slate-600">
              {confirmTarget.child_name} / {confirmTarget.food_name}: {confirmTarget.symptoms}
            </p>
            <textarea
              value={confirmNote}
              onChange={(e) => setConfirmNote(e.target.value)}
              rows={2}
              placeholder="確認メモ(任意。例: 保護者へ受診案内済み)"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            {actionError && <p className="mt-2 text-sm font-medium text-red-500">{actionError}</p>}
            <div className="mt-4 flex justify-end gap-3">
              <button
                onClick={() => setConfirmTarget(null)}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                onClick={handleConfirm}
                disabled={isActing}
                className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
              >
                {isActing ? "処理中…" : "確認を記録する"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function FoodChecksPage() {
  return (
    <Suspense fallback={null}>
      <FoodChecksPageContent />
    </Suspense>
  );
}
