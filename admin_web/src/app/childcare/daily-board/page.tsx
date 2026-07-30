"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { ChildInternalNotesModal } from "@/components/ChildInternalNotesModal";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { currentDate } from "@/lib/datetime";
import type { DailyBoardRow } from "@/lib/types";
import { DAILY_BOARD_STATUS_LABELS } from "@/lib/types";

function ChildcareDailyBoardPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();

  const [businessDate, setBusinessDate] = useState(currentDate());
  const [rows, setRows] = useState<DailyBoardRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [internalNotesEnabled, setInternalNotesEnabled] = useState(false);
  const [internalNotesChild, setInternalNotesChild] = useState<{ id: string; name: string } | null>(null);

  // 園内記録機能フラグ(施設単位)。ONの施設のみ「園内記録」導線を表示する。
  // 表示判定はRPCの戻り値のみに従い、クライアント側で再実装しない。
  useEffect(() => {
    function loadFlag() {
      if (!selectedOffice) {
        setInternalNotesEnabled(false);
        return;
      }
      createClient()
        .rpc("is_child_internal_notes_enabled_for_office", { p_office_id: selectedOffice })
        .then(({ data }) => setInternalNotesEnabled(Boolean(data)));
    }
    loadFlag();
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
      .rpc("fetch_daily_board_for_office", { p_office_id: selectedOffice, p_business_date: businessDate })
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRows((data ?? []) as DailyBoardRow[]);
      });
  }, [selectedOffice, businessDate, reloadToken]);

  // 登降園の記録は複数端末(保護者アプリ・キオスク端末)から行われるため、
  // daily_child_statusの変更をRealtimeで購読し即時反映する。
  useEffect(() => {
    if (!selectedOffice) return;
    const supabase = createClient();
    const channel = supabase
      .channel(`daily_board_${selectedOffice}_${businessDate}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "daily_child_status" },
        () => setReloadToken((t) => t + 1),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [selectedOffice, businessDate]);

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
        <h2 className="text-lg font-bold text-slate-800">デイリーボード</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
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
            <label className="mb-1 block text-xs font-medium text-slate-500">対象日</label>
            <input
              type="date"
              value={businessDate}
              onChange={(e) => setBusinessDate(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-4 py-3">園児</th>
                <th className="px-4 py-3">クラス</th>
                <th className="px-4 py-3">状態</th>
                <th className="px-4 py-3">最終イベント</th>
                <th className="px-4 py-3">家庭連絡帳</th>
                <th className="px-4 py-3">お迎え変更</th>
                {internalNotesEnabled && <th className="px-4 py-3">園内記録</th>}
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr>
                  <td colSpan={internalNotesEnabled ? 7 : 6} className="px-4 py-6 text-center text-slate-400">
                    読み込み中…
                  </td>
                </tr>
              )}
              {!isLoading && rows.length === 0 && (
                <tr>
                  <td colSpan={internalNotesEnabled ? 7 : 6} className="px-4 py-6 text-center text-slate-400">
                    在籍園児がいません
                  </td>
                </tr>
              )}
              {!isLoading &&
                rows.map((row) => (
                  <tr key={row.child_id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                    <td className="px-4 py-3 font-medium text-slate-800">
                      {row.display_name}
                      {row.honorific_suffix ?? ""}
                    </td>
                    <td className="px-4 py-3 text-slate-500">{row.class_name}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                          row.status === "present"
                            ? "bg-emerald-50 text-emerald-700"
                            : row.status === "picked_up"
                              ? "bg-slate-100 text-slate-500"
                              : row.status === "absent"
                                ? "bg-red-50 text-red-600"
                                : "bg-amber-50 text-amber-700"
                        }`}
                      >
                        {DAILY_BOARD_STATUS_LABELS[row.status]}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-slate-500">
                      {row.last_event_at
                        ? `${row.last_event_type} (${new Date(row.last_event_at).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" })})`
                        : "—"}
                    </td>
                    <td className="px-4 py-3 text-slate-500">
                      {row.family_daily_report_status === "submitted" ? (
                        <span className="text-emerald-700">
                          提出済み{row.temperature != null ? `(${row.temperature.toFixed(1)}℃)` : ""}
                        </span>
                      ) : row.family_daily_report_status === "draft" ? (
                        <span className="text-slate-400">下書き中</span>
                      ) : (
                        <span className="text-slate-400">未提出</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {row.has_pickup_change && (
                        <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800">
                          変更あり: {row.pickup_person_name}
                          {row.pickup_time_from ? `(${row.pickup_time_from.slice(0, 5)}〜${row.pickup_time_to?.slice(0, 5) ?? ""})` : ""}
                        </span>
                      )}
                    </td>
                    {internalNotesEnabled && (
                      <td className="px-4 py-3">
                        <button
                          onClick={() =>
                            setInternalNotesChild({
                              id: row.child_id,
                              name: `${row.display_name}${row.honorific_suffix ?? ""}`,
                            })
                          }
                          className="rounded-lg border border-amber-400 bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-100"
                        >
                          🔒 園内記録
                        </button>
                      </td>
                    )}
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </main>

      {internalNotesChild && (
        <ChildInternalNotesModal
          childId={internalNotesChild.id}
          childName={internalNotesChild.name}
          officeId={selectedOffice}
          onClose={() => setInternalNotesChild(null)}
        />
      )}
    </div>
  );
}

export default function ChildcareDailyBoardPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareDailyBoardPageContent />
    </Suspense>
  );
}
