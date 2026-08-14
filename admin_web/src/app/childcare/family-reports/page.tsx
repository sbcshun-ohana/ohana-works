"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { currentDate } from "@/lib/datetime";
import { FAMILY_MOOD_LABELS, FAMILY_BOWEL_CONDITION_LABELS } from "@/lib/types";
import type { FamilyDailyReportSummary } from "@/lib/types";

// K8 家庭での様子一覧(admin_web・Ohana Kids Phase A 相当)。
// family_daily_reports(保護者記入・status=submitted)を施設×日で全園児分表示し、
// 園側検温(188)の最新値を1列追加する。取得は既存RLS(staff_has_guardian_data_access)で
// 直接select、園側最新検温は fetch_child_latest_temperatures_for_office(188)。

type ChildJoin = {
  display_name: string;
  honorific_suffix: string | null;
  office_id: string;
};

type ReportRow = FamilyDailyReportSummary & {
  child_id: string;
  children: ChildJoin;
};


function fmtTime(t: string | null): string {
  return t ? t.slice(0, 5) : "—";
}

function mood(v: string | null): string {
  return v ? (FAMILY_MOOD_LABELS[v] ?? v) : "—";
}

function bowel(count: number | null, condition: string | null): string {
  if (count == null && !condition) return "—";
  const c = condition ? (FAMILY_BOWEL_CONDITION_LABELS[condition] ?? condition) : "";
  return `${count ?? 0}回${c ? `・${c}` : ""}`;
}

function ChildcareFamilyReportsPageContent() {
  // 施設選択はヘッダーに集約。selectedOffice は useChildcareOffices が ?office= に追随して供給する。
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const [businessDate, setBusinessDate] = useState(currentDate());
  const [rows, setRows] = useState<ReportRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);

  useEffect(() => {
    function load() {
      if (!selectedOffice) {
        setRows([]);
        return null;
      }
      setIsLoading(true);
      setRowsError(null);
      return createClient();
    }
    const supabase = load();
    if (!supabase) return;
    supabase
      .from("family_daily_reports")
      .select("*, children!inner(display_name, honorific_suffix, office_id)")
      .eq("business_date", businessDate)
      .eq("children.office_id", selectedOffice)
      .eq("status", "submitted")
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          setRows([]);
          return;
        }
        const list = ((data ?? []) as ReportRow[])
          .slice()
          .sort((a, b) => a.children.display_name.localeCompare(b.children.display_name, "ja"));
        setRows(list);
      });
  }, [selectedOffice, businessDate]);

  // K8方針変更(俊確定): 園側検温は family-reports には出さず、公開時に園→保護者の連絡帳へ
  // 自動反映する(195/196)。よって「園側検温(最新)」列は廃止。

  const filtered = rows;

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
        <h2 className="text-lg font-bold text-slate-800">家庭での様子一覧</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
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
                <th className="px-3 py-3">園児</th>
                <th className="px-3 py-3">機嫌(夜/朝)</th>
                <th className="px-3 py-3">排便(夜/朝)</th>
                <th className="px-3 py-3">睡眠</th>
                <th className="px-3 py-3">食事(夕/朝)</th>
                <th className="px-3 py-3">検温(家庭朝)</th>
                <th className="px-3 py-3">迎え</th>
                <th className="px-3 py-3">子どもの様子</th>
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr>
                  <td colSpan={9} className="px-3 py-6 text-center text-slate-400">
                    読み込み中…
                  </td>
                </tr>
              )}
              {!isLoading && filtered.length === 0 && (
                <tr>
                  <td colSpan={9} className="px-3 py-6 text-center text-slate-400">
                    提出済みの家庭連絡帳がありません
                  </td>
                </tr>
              )}
              {!isLoading &&
                filtered.map((r) => {
                  return (
                    <tr key={r.child_id} className="border-b border-slate-100 align-top last:border-0 hover:bg-slate-50">
                      <td className="px-3 py-3 font-medium text-slate-800">
                        {r.children.display_name}
                        {r.children.honorific_suffix ?? ""}
                      </td>
                      <td className="px-3 py-3 text-slate-600">
                        {mood(r.night_mood)} / {mood(r.morning_mood)}
                      </td>
                      <td className="px-3 py-3 text-slate-600">
                        {bowel(r.night_bowel_count, r.night_bowel_condition)} /{" "}
                        {bowel(r.morning_bowel_count, r.morning_bowel_condition)}
                      </td>
                      <td className="px-3 py-3 text-slate-600">
                        {r.sleep_start_at || r.sleep_end_at
                          ? `${fmtTime(r.sleep_start_at)}〜${fmtTime(r.sleep_end_at)}`
                          : "—"}
                      </td>
                      <td className="px-3 py-3 text-slate-600">
                        <div>夕: {r.dinner_content ?? "—"}</div>
                        <div>朝: {r.breakfast_content ?? "—"}</div>
                      </td>
                      <td className="px-3 py-3 text-slate-600">
                        {r.temperature != null ? `${r.temperature.toFixed(1)}℃` : "—"}
                        {r.temperature_measured_at ? `(${fmtTime(r.temperature_measured_at)})` : ""}
                      </td>
                      <td className="px-3 py-3 text-slate-600">
                        {r.pickup_person_name
                          ? `${r.pickup_person_name}${r.pickup_time_from || r.pickup_time_to ? `(${r.pickup_time_from ? `登園${fmtTime(r.pickup_time_from)}` : ""}${r.pickup_time_to ? ` お迎え${fmtTime(r.pickup_time_to)}` : ""})` : ""}`
                          : "—"}
                      </td>
                      <td className="max-w-xs px-3 py-3 text-slate-600">
                        {r.home_notes || r.symptoms ? (
                          <div className="space-y-1">
                            {r.home_notes && <div className="whitespace-pre-wrap">{r.home_notes}</div>}
                            {r.symptoms && <div className="text-amber-700">症状: {r.symptoms}</div>}
                          </div>
                        ) : (
                          "—"
                        )}
                      </td>
                    </tr>
                  );
                })}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}

export default function ChildcareFamilyReportsPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareFamilyReportsPageContent />
    </Suspense>
  );
}
