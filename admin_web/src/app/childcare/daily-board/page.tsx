"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { ChildInternalNotesModal } from "@/components/ChildInternalNotesModal";
import { AttendanceTimeBar } from "@/components/AttendanceTimeBar";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { classOrderIndex, compareByClassThenName } from "@/lib/childcareClassSort";
import { currentDate } from "@/lib/datetime";
import type { AttendanceKind, DailyBoardRow, DailyBoardSummary, WeatherRecord, NapMissing } from "@/lib/types";
import { ATTENDANCE_KIND_LABELS, DAILY_BOARD_STATUS_LABELS, WEATHER_OPTIONS, deriveContactBadge } from "@/lib/types";

// K7で出欠種別=病欠/都合欠(is_absent同期対象)の園児は、状態列を「欠席」表示にする
// (daily_child_status は代理打刻由来のため未登園のままになる。サマリーの欠席数と整合させる)。
function effectiveBoardStatus(row: DailyBoardRow): DailyBoardRow["status"] {
  if (row.attendance_kind === "sick_absence" || row.attendance_kind === "personal_absence") return "absent";
  return row.status;
}

function ChildcareDailyBoardPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;
  const { classes, selectedClass, setSelectedClass } = useChildcareClass(selectedOffice);

  const [businessDate, setBusinessDate] = useState(currentDate());
  const [rows, setRows] = useState<DailyBoardRow[]>([]);
  const [summary, setSummary] = useState<DailyBoardSummary | null>(null);
  const [weather, setWeather] = useState<WeatherRecord | null>(null);
  const [weatherError, setWeatherError] = useState<string | null>(null);
  const [napMissing, setNapMissing] = useState<NapMissing[]>([]);
  const [proxyTarget, setProxyTarget] = useState<{ row: DailyBoardRow; eventType: "drop_off" | "pick_up" } | null>(
    null,
  );
  const [scheduleTarget, setScheduleTarget] = useState<{ contactIds: string[]; label: string } | null>(null);
  const [attendanceTarget, setAttendanceTarget] = useState<DailyBoardRow | null>(null);
  const [temperatureTarget, setTemperatureTarget] = useState<DailyBoardRow | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  function showToast(message: string) {
    setToast(message);
    window.setTimeout(() => setToast((cur) => (cur === message ? null : cur)), 3500);
  }
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

  // 在籍登園状況サマリー。クラス絞り込み(selectedClass=class_id)に連動し、
  // 空文字(全クラス)のときは施設全体、クラス選択時はそのクラス単位で集計する。
  // 数字はRPC側集計に一任し、Ohana Kids/admin_webで一致させる(クライアント再集計しない)。
  useEffect(() => {
    function loadSummary() {
      if (!selectedOffice) {
        setSummary(null);
        return;
      }
      createClient()
        .rpc("fetch_daily_board_summary_for_office", {
          p_office_id: selectedOffice,
          p_business_date: businessDate,
          p_class_id: selectedClass === "" ? null : selectedClass,
        })
        .then(({ data }) => setSummary(((data ?? [])[0] ?? null) as DailyBoardSummary | null));
    }
    loadSummary();
  }, [selectedOffice, businessDate, selectedClass, reloadToken]);

  // §3.4: 午睡チェックの記入漏れ警告バナー用。
  useEffect(() => {
    function loadNapMissing() {
      if (!selectedOffice) {
        setNapMissing([]);
        return;
      }
      createClient()
        .rpc("fetch_nap_missing_slots", { p_office_id: selectedOffice, p_session_date: businessDate })
        .then(({ data }) => setNapMissing((data ?? []) as NapMissing[]));
    }
    loadNapMissing();
  }, [selectedOffice, businessDate, reloadToken]);

  // 天気記録(施設×日で1行)。RLS(施設アクセス)で直接selectする。未入力なら null。
  useEffect(() => {
    function loadWeather() {
      if (!selectedOffice) {
        setWeather(null);
        return;
      }
      createClient()
        .from("daily_weather_records")
        .select("weather, temperature, humidity")
        .eq("office_id", selectedOffice)
        .eq("record_date", businessDate)
        .maybeSingle()
        .then(({ data }) => setWeather((data ?? null) as WeatherRecord | null));
    }
    loadWeather();
  }, [selectedOffice, businessDate, reloadToken]);

  async function saveWeather(next: WeatherRecord) {
    setWeatherError(null);
    const { error } = await createClient().rpc("upsert_daily_weather_record", {
      p_office_id: selectedOffice,
      p_record_date: businessDate,
      p_weather: next.weather,
      p_temperature: next.temperature,
      p_humidity: next.humidity,
    });
    if (error) {
      setWeatherError("天気の保存に失敗しました(過去日/未来日の修正は主任以上のみ)");
      return;
    }
    setReloadToken((t) => t + 1);
  }

  // 代理登降園の登録。時刻(HH:MM)は対象日 + JST(+09:00)で timestamptz を組み立てて渡す。
  async function recordProxyAttendance(
    row: DailyBoardRow,
    eventType: "drop_off" | "pick_up",
    time: string,
    notifyGuardian: boolean,
  ): Promise<boolean> {
    const occurredAt = `${businessDate}T${time}:00+09:00`;
    const { error } = await createClient().rpc("record_staff_manual_attendance", {
      p_child_id: row.child_id,
      p_event_type: eventType,
      p_occurred_at: occurredAt,
      p_notify_guardian: notifyGuardian,
    });
    if (error) return false;
    setReloadToken((t) => t + 1);
    return true;
  }

  // 連絡帳の公開操作(§2.4)。対象は approved かつ未公開の contact_id 群。
  // scheduled_at は対象日 + 時刻(既定17:00)を JST(+09:00)で組み立てる。
  // 実行結果は必ずトーストで返す(対象0件・成功件数・エラー理由)。
  const NO_TARGET = "対象の連絡帳がありません(承認済み・未公開のみ対象)";

  async function scheduleContacts(contactIds: string[], time: string) {
    if (contactIds.length === 0) {
      showToast(NO_TARGET);
      return;
    }
    const scheduledAt = `${businessDate}T${time}:00+09:00`;
    const { data, error } = await createClient().rpc("schedule_child_daily_contacts", {
      p_contact_ids: contactIds,
      p_scheduled_at: scheduledAt,
    });
    if (error) {
      showToast("公開予約に失敗しました(主任以上のみ操作できます)");
      return;
    }
    const n = typeof data === "number" ? data : contactIds.length;
    const hhmm = time.slice(0, 5);
    showToast(n === 0 ? NO_TARGET : `${n}件を${hhmm}に公開予約しました`);
    setReloadToken((t) => t + 1);
  }

  async function publishContactsNow(contactIds: string[]) {
    if (contactIds.length === 0) {
      showToast(NO_TARGET);
      return;
    }
    const { data, error } = await createClient().rpc("publish_child_daily_contacts_now", { p_contact_ids: contactIds });
    if (error) {
      showToast("公開に失敗しました(主任以上のみ操作できます)");
      return;
    }
    const n = typeof data === "number" ? data : contactIds.length;
    showToast(n === 0 ? NO_TARGET : `${n}件を公開しました`);
    setReloadToken((t) => t + 1);
  }

  async function cancelContactSchedule(contactIds: string[]) {
    if (contactIds.length === 0) {
      showToast(NO_TARGET);
      return;
    }
    const { data, error } = await createClient().rpc("cancel_child_daily_contacts_schedule", { p_contact_ids: contactIds });
    if (error) {
      showToast("予約取消に失敗しました(主任以上のみ操作できます)");
      return;
    }
    const n = typeof data === "number" ? data : contactIds.length;
    showToast(n === 0 ? NO_TARGET : `${n}件の公開予約を取消しました`);
    setReloadToken((t) => t + 1);
  }

  // 一括操作の対象: 表示中(絞り込み後)の行のうち approved かつ未公開の contact_id。
  // クラス選択中なら「クラス一括」、全クラスなら「施設一括」に相当する。
  const bulkEligibleContactIds = () =>
    filteredRows
      .filter((r) => r.contact_status === "approved" && r.contact_published_at == null && r.contact_id)
      .map((r) => r.contact_id as string);

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

  const classOrder = classOrderIndex(classes);
  const filteredRows = (selectedClass === "" ? rows : rows.filter((r) => r.class_id === selectedClass))
    .slice()
    .sort((a, b) => compareByClassThenName(classOrder, a.class_name, a.display_name, b.class_name, b.display_name));

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

        {napMissing.length > 0 && (
          <div className="rounded-2xl border border-red-300 bg-red-50 p-4 text-sm font-medium text-red-700">
            ⚠ 午睡チェックの記入漏れがあります:{" "}
            {napMissing
              .slice(0, 8)
              .map((m) => `${m.display_name}(${m.class_name}・${m.missing_count})`)
              .join("、")}
          </div>
        )}

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
          {(
            [
              { key: "enrolled", label: "在籍", tone: "text-slate-700" },
              { key: "expected", label: "登園予定", tone: "text-sky-700" },
              { key: "attended", label: "出席", tone: "text-emerald-700" },
              { key: "present_now", label: "登園中", tone: "text-emerald-700" },
              { key: "absent", label: "欠席", tone: "text-red-600" },
            ] as const
          ).map((item) => (
            <div key={item.key} className="rounded-2xl bg-white p-4 text-center shadow-sm">
              <p className="text-xs font-medium text-slate-500">{item.label}</p>
              <p className={`mt-1 text-2xl font-bold ${item.tone}`}>{summary ? summary[item.key] : "—"}</p>
            </div>
          ))}
        </div>

        <WeatherBar weather={weather} onSave={saveWeather} error={weatherError} />

        <div className="flex flex-wrap items-center gap-2 rounded-2xl bg-white p-4 shadow-sm">
          <span className="text-sm font-semibold text-slate-700">
            連絡帳 {selectedClass === "" ? "施設一括" : "クラス一括"}
          </span>
          <span className="text-xs text-slate-400">(承認済み・未公開が対象)</span>
          <div className="ml-auto flex gap-2">
            <button
              onClick={() =>
                setScheduleTarget({
                  contactIds: bulkEligibleContactIds(),
                  label: selectedClass === "" ? "施設一括" : "クラス一括",
                })
              }
              className="rounded-lg border border-sky-300 bg-sky-50 px-3 py-1.5 text-xs font-semibold text-sky-700 hover:bg-sky-100"
            >
              17時公開予約
            </button>
            <button
              onClick={() => publishContactsNow(bulkEligibleContactIds())}
              className="rounded-lg border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700 hover:bg-emerald-100"
            >
              今すぐ公開
            </button>
            <button
              onClick={() => cancelContactSchedule(bulkEligibleContactIds())}
              className="rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-600 hover:bg-slate-50"
            >
              予約取消
            </button>
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
                <th className="px-4 py-3">登降園</th>
                <th className="px-4 py-3">最終イベント</th>
                <th className="px-4 py-3">家庭連絡帳</th>
                <th className="px-4 py-3">お迎え変更</th>
                <th className="px-4 py-3">代理打刻(保護者通知あり)</th>
                <th className="px-4 py-3">連絡帳公開</th>
                {internalNotesEnabled && <th className="px-4 py-3">園内記録</th>}
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr>
                  <td colSpan={internalNotesEnabled ? 10 : 9} className="px-4 py-6 text-center text-slate-400">
                    読み込み中…
                  </td>
                </tr>
              )}
              {!isLoading && filteredRows.length === 0 && (
                <tr>
                  <td colSpan={internalNotesEnabled ? 10 : 9} className="px-4 py-6 text-center text-slate-400">
                    在籍園児がいません
                  </td>
                </tr>
              )}
              {!isLoading &&
                filteredRows.map((row) => (
                  <tr key={row.child_id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                    <td className="px-4 py-3 font-medium text-slate-800">
                      {row.display_name}
                      {row.honorific_suffix ?? ""}
                    </td>
                    <td className="px-4 py-3 text-slate-500">{row.class_name}</td>
                    <td className="px-4 py-3">
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                          effectiveBoardStatus(row) === "present"
                            ? "bg-emerald-50 text-emerald-700"
                            : effectiveBoardStatus(row) === "picked_up"
                              ? "bg-slate-100 text-slate-500"
                              : effectiveBoardStatus(row) === "absent"
                                ? "bg-red-50 text-red-600"
                                : "bg-amber-50 text-amber-700"
                        }`}
                      >
                        {DAILY_BOARD_STATUS_LABELS[effectiveBoardStatus(row)]}
                      </span>
                      {row.on_therapy_outing && (
                        <span className="ml-1 rounded-full bg-violet-100 px-2 py-0.5 text-xs font-semibold text-violet-700">
                          療育外出中
                          {row.therapy_out_at
                            ? `(${new Date(row.therapy_out_at).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" })})`
                            : ""}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="space-y-1">
                        <AttendanceTimeBar
                          arrivalAt={row.arrival_at}
                          departureAt={row.departure_at}
                          outAt={row.out_at}
                          returnAt={row.return_at}
                          scheduledStartAt={row.scheduled_start_at}
                          scheduledEndAt={row.scheduled_end_at}
                        />
                        <div className="flex items-center gap-2">
                          {row.attendance_kind && row.attendance_kind !== "none" && (
                            <span
                              className={`inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                                row.attendance_kind === "sick_absence" || row.attendance_kind === "personal_absence"
                                  ? "bg-red-50 text-red-600"
                                  : "bg-amber-50 text-amber-700"
                              }`}
                            >
                              {ATTENDANCE_KIND_LABELS[row.attendance_kind]}
                            </span>
                          )}
                          <button
                            onClick={() => setAttendanceTarget(row)}
                            className="rounded-lg border border-slate-300 px-2 py-0.5 text-[10px] font-semibold text-slate-600 hover:bg-slate-100"
                          >
                            出欠編集
                          </button>
                          <button
                            onClick={() => setTemperatureTarget(row)}
                            className="rounded-lg border border-slate-300 px-2 py-0.5 text-[10px] font-semibold text-slate-600 hover:bg-slate-100"
                          >
                            検温
                          </button>
                        </div>
                      </div>
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
                    <td className="px-4 py-3">
                      {row.status === "present" ? (
                        <button
                          onClick={() => setProxyTarget({ row, eventType: "pick_up" })}
                          className="rounded-lg border border-slate-300 bg-white px-3 py-1 text-xs font-semibold text-slate-600 hover:bg-slate-50"
                        >
                          降園を登録
                        </button>
                      ) : row.status === "not_arrived" || row.status === "absent" ? (
                        <button
                          onClick={() => setProxyTarget({ row, eventType: "drop_off" })}
                          className="rounded-lg border border-sky-300 bg-sky-50 px-3 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-100"
                        >
                          登園を登録
                        </button>
                      ) : (
                        <span className="text-xs text-slate-300">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <ContactPublishCell
                        row={row}
                        onSchedule17={() => row.contact_id && scheduleContacts([row.contact_id], "17:00")}
                        onPickTime={() =>
                          row.contact_id &&
                          setScheduleTarget({
                            contactIds: [row.contact_id],
                            label: `${row.display_name}${row.honorific_suffix ?? ""}`,
                          })
                        }
                        onPublishNow={() => row.contact_id && publishContactsNow([row.contact_id])}
                        onCancel={() => row.contact_id && cancelContactSchedule([row.contact_id])}
                      />
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

      {proxyTarget && (
        <ProxyAttendanceModal
          target={proxyTarget}
          onClose={() => setProxyTarget(null)}
          onSubmit={recordProxyAttendance}
        />
      )}

      {attendanceTarget && (
        <AttendanceEditModal
          row={attendanceTarget}
          businessDate={businessDate}
          isManager={isManager}
          onClose={() => setAttendanceTarget(null)}
          onSaved={(msg) => {
            showToast(msg);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {temperatureTarget && (
        <TemperatureModal
          row={temperatureTarget}
          businessDate={businessDate}
          isManager={isManager}
          onClose={() => setTemperatureTarget(null)}
          onSaved={(msg) => showToast(msg)}
        />
      )}

      {scheduleTarget && (
        <ContactScheduleModal
          label={scheduleTarget.label}
          onClose={() => setScheduleTarget(null)}
          onSubmit={async (time) => {
            await scheduleContacts(scheduleTarget.contactIds, time);
            setScheduleTarget(null);
          }}
        />
      )}

      {toast && (
        <div className="fixed bottom-6 left-1/2 z-[60] -translate-x-1/2 rounded-xl bg-slate-800 px-4 py-2 text-sm font-semibold text-white shadow-lg">
          {toast}
        </div>
      )}
    </div>
  );
}

/** 連絡帳公開の状態バッジ+操作(承認済み・未公開のみ操作可)。 */
function ContactPublishCell({
  row,
  onSchedule17,
  onPickTime,
  onPublishNow,
  onCancel,
}: {
  row: DailyBoardRow;
  onSchedule17: () => void;
  onPickTime: () => void;
  onPublishNow: () => void;
  onCancel: () => void;
}) {
  const badge = deriveContactBadge(row);
  if (badge === "none") return <span className="text-xs text-slate-300">—</span>;
  if (badge === "draft") {
    return <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">下書き</span>;
  }
  if (badge === "published") {
    return <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700">公開済</span>;
  }
  if (badge === "unscheduled") {
    // 承認済みだが予約なし(取消後)。再予約/即時公開を提供する。
    return (
      <div className="flex flex-col gap-1">
        <span className="rounded-full bg-slate-100 px-2 py-0.5 text-center text-xs font-semibold text-slate-500">
          非公開
        </span>
        <div className="flex flex-wrap gap-1">
          <button onClick={onSchedule17} className="rounded border border-sky-300 px-2 py-0.5 text-[11px] text-sky-700 hover:bg-sky-50">
            17時予約
          </button>
          <button onClick={onPickTime} className="rounded border border-slate-300 px-2 py-0.5 text-[11px] text-slate-600 hover:bg-slate-50">
            時刻指定
          </button>
          <button onClick={onPublishNow} className="rounded border border-emerald-300 px-2 py-0.5 text-[11px] text-emerald-700 hover:bg-emerald-50">
            今すぐ公開
          </button>
        </div>
      </div>
    );
  }
  // scheduled
  const scheduledTime = row.contact_scheduled_publish_at
    ? new Date(row.contact_scheduled_publish_at).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" })
    : "";
  return (
    <div className="flex flex-col gap-1">
      <span className="rounded-full bg-amber-50 px-2 py-0.5 text-center text-xs font-semibold text-amber-700">
        公開予約済 {scheduledTime}
      </span>
      <div className="flex flex-wrap gap-1">
        <button onClick={onPickTime} className="rounded border border-slate-300 px-2 py-0.5 text-[11px] text-slate-600 hover:bg-slate-50">
          時刻変更
        </button>
        <button onClick={onPublishNow} className="rounded border border-emerald-300 px-2 py-0.5 text-[11px] text-emerald-700 hover:bg-emerald-50">
          今すぐ公開
        </button>
        <button onClick={onCancel} className="rounded border border-slate-300 px-2 py-0.5 text-[11px] text-slate-600 hover:bg-slate-50">
          取消
        </button>
      </div>
    </div>
  );
}

/** 公開予約の時刻ピッカー(既定17:00)。 */
function ContactScheduleModal({
  label,
  onClose,
  onSubmit,
}: {
  label: string;
  onClose: () => void;
  onSubmit: (time: string) => void;
}) {
  const [time, setTime] = useState("17:00");
  const [saving, setSaving] = useState(false);
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">{label} の公開予約</h3>
        <div className="mt-4">
          <label className="mb-1 block text-xs font-medium text-slate-500">公開時刻</label>
          <input
            type="time"
            value={time}
            onChange={(e) => setTime(e.target.value)}
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>
        <div className="mt-6 flex justify-end gap-2">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">
            キャンセル
          </button>
          <button
            onClick={async () => {
              setSaving(true);
              await onSubmit(time);
            }}
            disabled={saving}
            className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-50"
          >
            {saving ? "設定中…" : "予約"}
          </button>
        </div>
      </div>
    </div>
  );
}

/** 代理登降園の登録モーダル。時刻(既定=現在時刻・手入力可)+ 保護者通知トグル(既定ON)。 */
function ProxyAttendanceModal({
  target,
  onClose,
  onSubmit,
}: {
  target: { row: DailyBoardRow; eventType: "drop_off" | "pick_up" };
  onClose: () => void;
  onSubmit: (
    row: DailyBoardRow,
    eventType: "drop_off" | "pick_up",
    time: string,
    notifyGuardian: boolean,
  ) => Promise<boolean>;
}) {
  const now = new Date();
  const defaultTime = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`;
  const [time, setTime] = useState(defaultTime);
  const [notify, setNotify] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const actionLabel = target.eventType === "drop_off" ? "登園" : "降園";
  const childName = `${target.row.display_name}${target.row.honorific_suffix ?? ""}`;

  async function handleSubmit() {
    setSaving(true);
    setError(null);
    const ok = await onSubmit(target.row, target.eventType, time, notify);
    if (!ok) {
      setSaving(false);
      setError("登録に失敗しました(主任以上のみ登録できます)");
      return;
    }
    onClose();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">
          {childName} の{actionLabel}を登録
        </h3>
        <div className="mt-4">
          <label className="mb-1 block text-xs font-medium text-slate-500">{actionLabel}時刻</label>
          <input
            type="time"
            value={time}
            onChange={(e) => setTime(e.target.value)}
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>
        <label className="mt-4 flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={notify} onChange={(e) => setNotify(e.target.checked)} />
          保護者へ通知する
        </label>
        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}
        <div className="mt-6 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50"
          >
            キャンセル
          </button>
          <button
            onClick={handleSubmit}
            disabled={saving}
            className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-50"
          >
            {saving ? "登録中…" : "登録"}
          </button>
        </div>
      </div>
    </div>
  );
}

// timestamptz(ISO)→ JST の "HH:MM"(実績プリフィル用)。null は空文字。
function isoToJstHm(iso: string | null): string {
  if (!iso) return "";
  return new Date(iso).toLocaleTimeString("en-GB", {
    timeZone: "Asia/Tokyo",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
}

// K7 出欠編集モーダル。
// - 出欠状況(種別/予定/枠/メモ)= set_child_attendance_status(185・担当施設の職員)
// - 登降園実績(入/外/戻/退)= set_child_attendance_actuals(187・主任以上・全置換)
//   実績は現在値を全4値プリフィルして常に4値を渡す(空欄=そのクリア)= 全置換セマンティクス。
function AttendanceEditModal({
  row,
  businessDate,
  isManager,
  onClose,
  onSaved,
}: {
  row: DailyBoardRow;
  businessDate: string;
  isManager: boolean;
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const childName = `${row.display_name}${row.honorific_suffix ?? ""}`;

  // 出欠状況(全職員)
  const [kind, setKind] = useState<AttendanceKind>(row.attendance_kind ?? "none");
  const [schedStart, setSchedStart] = useState(row.scheduled_start_at?.slice(0, 5) ?? "");
  const [schedEnd, setSchedEnd] = useState(row.scheduled_end_at?.slice(0, 5) ?? "");
  const [slot, setSlot] = useState("");
  const [note, setNote] = useState(row.attendance_note ?? "");
  const [savingStatus, setSavingStatus] = useState(false);
  const [statusError, setStatusError] = useState<string | null>(null);

  // scheduled_slot は board(186)が返さないため、上書き防止に現行行を直接selectしてプリフィル。
  useEffect(() => {
    let alive = true;
    createClient()
      .from("child_daily_attendance")
      .select("scheduled_slot")
      .eq("child_id", row.child_id)
      .eq("business_date", businessDate)
      .maybeSingle()
      .then(({ data }) => {
        if (alive && data?.scheduled_slot) setSlot(data.scheduled_slot as string);
      });
    return () => {
      alive = false;
    };
  }, [row.child_id, businessDate]);

  // 登降園実績(主任以上)。現在値を全4値プリフィル。
  const [inAt, setInAt] = useState(isoToJstHm(row.arrival_at));
  const [outAt, setOutAt] = useState(isoToJstHm(row.out_at));
  const [returnAt, setReturnAt] = useState(isoToJstHm(row.return_at));
  const [departAt, setDepartAt] = useState(isoToJstHm(row.departure_at));
  const [savingActuals, setSavingActuals] = useState(false);
  const [actualsError, setActualsError] = useState<string | null>(null);

  async function saveStatus() {
    setSavingStatus(true);
    setStatusError(null);
    const { error } = await createClient().rpc("set_child_attendance_status", {
      p_child_id: row.child_id,
      p_business_date: businessDate,
      p_attendance_kind: kind,
      p_scheduled_start: schedStart || null,
      p_scheduled_end: schedEnd || null,
      p_scheduled_slot: slot || null,
      p_attendance_note: note || null,
    });
    setSavingStatus(false);
    if (error) {
      setStatusError(`保存に失敗しました: ${error.message}`);
      return;
    }
    onSaved("出欠状況を保存しました");
    onClose();
  }

  async function saveActuals() {
    setSavingActuals(true);
    setActualsError(null);
    // 全置換: 空欄は null(=その実績を削除)として常に4値を渡す。
    const { error } = await createClient().rpc("set_child_attendance_actuals", {
      p_child_id: row.child_id,
      p_business_date: businessDate,
      p_in: inAt || null,
      p_out: outAt || null,
      p_return: returnAt || null,
      p_depart: departAt || null,
    });
    setSavingActuals(false);
    if (error) {
      setActualsError(`保存に失敗しました(主任以上のみ・退≥入/戻≥外): ${error.message}`);
      return;
    }
    onSaved("登降園実績を保存しました");
    onClose();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/30 p-4">
      <div className="my-8 w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">{childName} の出欠編集</h3>

        {/* 出欠状況(全職員) */}
        <div className="mt-4 space-y-3">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">出欠種別</label>
            <select
              value={kind}
              onChange={(e) => setKind(e.target.value as AttendanceKind)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {(Object.keys(ATTENDANCE_KIND_LABELS) as AttendanceKind[]).map((k) => (
                <option key={k} value={k}>
                  {ATTENDANCE_KIND_LABELS[k]}
                </option>
              ))}
            </select>
            <p className="mt-1 text-[10px] text-slate-400">病欠・都合欠のみ欠席として集計されます(遅刻/早退は出席)。</p>
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="mb-1 block text-xs font-medium text-slate-500">登園予定</label>
              <input
                type="time"
                value={schedStart}
                onChange={(e) => setSchedStart(e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
              />
            </div>
            <div className="flex-1">
              <label className="mb-1 block text-xs font-medium text-slate-500">降園予定</label>
              <input
                type="time"
                value={schedEnd}
                onChange={(e) => setSchedEnd(e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
              />
            </div>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">予定枠(任意)</label>
            <input
              type="text"
              value={slot}
              onChange={(e) => setSlot(e.target.value)}
              placeholder="標準/短時間/延長 など"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">出欠メモ(任意)</label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
          {statusError && <p className="text-xs font-medium text-red-500">{statusError}</p>}
          <div className="flex justify-end">
            <button
              onClick={saveStatus}
              disabled={savingStatus}
              className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-50"
            >
              {savingStatus ? "保存中…" : "出欠状況を保存"}
            </button>
          </div>
        </div>

        {/* 登降園実績(主任以上) */}
        <div className="mt-6 border-t border-slate-200 pt-4">
          <h4 className="text-sm font-bold text-slate-700">登降園実績(入/外/戻/退)</h4>
          {isManager ? (
            <>
              <p className="mt-1 text-[10px] text-amber-600">
                全置換: 4項目すべてが現在値です。空欄で保存するとその実績が削除されます。
              </p>
              <div className="mt-2 grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">入(登園)</label>
                  <input type="time" value={inAt} onChange={(e) => setInAt(e.target.value)} className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">退(降園)</label>
                  <input type="time" value={departAt} onChange={(e) => setDepartAt(e.target.value)} className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">外(外出)</label>
                  <input type="time" value={outAt} onChange={(e) => setOutAt(e.target.value)} className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">戻(再入室)</label>
                  <input type="time" value={returnAt} onChange={(e) => setReturnAt(e.target.value)} className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                </div>
              </div>
              {actualsError && <p className="mt-2 text-xs font-medium text-red-500">{actualsError}</p>}
              <div className="mt-3 flex justify-end">
                <button
                  onClick={saveActuals}
                  disabled={savingActuals}
                  className="rounded-lg bg-indigo-600 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-700 disabled:opacity-50"
                >
                  {savingActuals ? "保存中…" : "実績を保存"}
                </button>
              </div>
            </>
          ) : (
            <p className="mt-1 text-xs text-slate-400">実績の事後修正は主任以上のみ可能です。</p>
          )}
        </div>

        <div className="mt-6 flex justify-end">
          <button
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50"
          >
            閉じる
          </button>
        </div>
      </div>
    </div>
  );
}

// 園側検温(188)の記録モーダル。職員が日中に複数回記録できる。
// 過去日(・未来日)の記録/削除は主任以上のみ(サーバー record_child_temperature と対称)。
// UIでも当日以外は一般職員に対して入力を無効化する(サーバー側ゲートは現状維持)。
function TemperatureModal({
  row,
  businessDate,
  isManager,
  onClose,
  onSaved,
}: {
  row: DailyBoardRow;
  businessDate: string;
  isManager: boolean;
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const childName = `${row.display_name}${row.honorific_suffix ?? ""}`;
  const canEdit = isManager || businessDate === currentDate(); // 当日以外は主任以上のみ

  const [records, setRecords] = useState<{ measured_at: string; temperature: number }[]>([]);
  const now = new Date();
  const [measuredAt, setMeasuredAt] = useState(
    `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`,
  );
  const [temp, setTemp] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    let alive = true;
    createClient()
      .from("child_temperature_records")
      .select("measured_at, temperature")
      .eq("child_id", row.child_id)
      .eq("business_date", businessDate)
      .order("measured_at", { ascending: true })
      .then(({ data }) => {
        if (alive) setRecords((data ?? []) as { measured_at: string; temperature: number }[]);
      });
    return () => {
      alive = false;
    };
  }, [row.child_id, businessDate, reload]);

  async function addRecord() {
    const t = Number(temp);
    if (!temp || Number.isNaN(t) || t < 34 || t > 42) {
      setError("体温は34.0〜42.0℃で入力してください");
      return;
    }
    setBusy(true);
    setError(null);
    const { error: e } = await createClient().rpc("record_child_temperature", {
      p_child_id: row.child_id,
      p_business_date: businessDate,
      p_measured_at: measuredAt,
      p_temperature: t,
    });
    setBusy(false);
    if (e) {
      setError(`記録に失敗しました(過去日は主任以上): ${e.message}`);
      return;
    }
    setTemp("");
    onSaved("検温を記録しました");
    setReload((r) => r + 1);
  }

  async function removeRecord(at: string) {
    setBusy(true);
    setError(null);
    const { error: e } = await createClient().rpc("delete_child_temperature", {
      p_child_id: row.child_id,
      p_business_date: businessDate,
      p_measured_at: at,
    });
    setBusy(false);
    if (e) {
      setError(`削除に失敗しました(過去日は主任以上): ${e.message}`);
      return;
    }
    onSaved("検温を削除しました");
    setReload((r) => r + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">{childName} の検温(園側)</h3>
        {!canEdit && (
          <p className="mt-2 text-xs font-medium text-amber-600">過去日・未来日の検温は主任以上のみ記録・削除できます。</p>
        )}

        <div className="mt-4 space-y-1">
          {records.length === 0 ? (
            <p className="text-sm text-slate-400">記録はありません</p>
          ) : (
            records.map((r) => (
              <div key={r.measured_at} className="flex items-center justify-between rounded-lg bg-slate-50 px-3 py-1.5 text-sm">
                <span className="tabular-nums text-slate-600">{r.measured_at.slice(0, 5)}</span>
                <span className="font-semibold text-slate-800">{Number(r.temperature).toFixed(1)}℃</span>
                <button
                  onClick={() => removeRecord(r.measured_at)}
                  disabled={busy || !canEdit}
                  className="text-xs font-medium text-red-500 hover:underline disabled:opacity-40"
                >
                  削除
                </button>
              </div>
            ))
          )}
        </div>

        <div className="mt-4 flex items-end gap-2">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">時刻</label>
            <div className="flex items-center gap-1">
              <input
                type="time"
                value={measuredAt}
                disabled={!canEdit}
                onChange={(e) => setMeasuredAt(e.target.value)}
                className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
              />
              <button
                type="button"
                disabled={!canEdit}
                onClick={() => {
                  const d = new Date();
                  setMeasuredAt(`${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`);
                }}
                className="rounded-lg border border-slate-300 px-2 py-1.5 text-[10px] font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-40"
              >
                現在時刻
              </button>
            </div>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">体温(℃)</label>
            <input
              type="number"
              step="0.1"
              min="34"
              max="42"
              value={temp}
              disabled={!canEdit}
              onChange={(e) => setTemp(e.target.value)}
              placeholder="36.5"
              className="w-20 rounded-lg border border-slate-300 px-2 py-1.5 text-sm disabled:bg-slate-50"
            />
          </div>
          <button
            onClick={addRecord}
            disabled={busy || !canEdit}
            className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-50"
          >
            記録
          </button>
        </div>

        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}

        <div className="mt-6 flex justify-end">
          <button
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50"
          >
            閉じる
          </button>
        </div>
      </div>
    </div>
  );
}

function WeatherBar({
  weather,
  onSave,
  error,
}: {
  weather: WeatherRecord | null;
  onSave: (next: WeatherRecord) => void;
  error: string | null;
}) {
  const [w, setW] = useState<string>(weather?.weather ?? "晴れ");
  const [temp, setTemp] = useState<string>(weather?.temperature != null ? String(weather.temperature) : "");
  const [humidity, setHumidity] = useState<string>(weather?.humidity != null ? String(weather.humidity) : "");

  // props(取得結果)が変わったら入力欄へ反映する。
  useEffect(() => {
    function sync() {
      setW(weather?.weather ?? "晴れ");
      setTemp(weather?.temperature != null ? String(weather.temperature) : "");
      setHumidity(weather?.humidity != null ? String(weather.humidity) : "");
    }
    sync();
  }, [weather]);

  return (
    <div className="flex flex-wrap items-end gap-3 rounded-2xl bg-white p-4 shadow-sm">
      <div className="flex items-center gap-2">
        <span className="text-sm font-semibold text-slate-700">天気</span>
        {weather === null && (
          <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-400">未入力</span>
        )}
      </div>
      <div>
        <label className="mb-1 block text-xs font-medium text-slate-500">天気</label>
        <select
          value={w}
          onChange={(e) => setW(e.target.value)}
          className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
        >
          {WEATHER_OPTIONS.map((opt) => (
            <option key={opt} value={opt}>
              {opt}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="mb-1 block text-xs font-medium text-slate-500">気温(℃)</label>
        <input
          type="number"
          step="0.1"
          value={temp}
          onChange={(e) => setTemp(e.target.value)}
          className="w-24 rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
        />
      </div>
      <div>
        <label className="mb-1 block text-xs font-medium text-slate-500">湿度(%)</label>
        <input
          type="number"
          step="1"
          value={humidity}
          onChange={(e) => setHumidity(e.target.value)}
          className="w-24 rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
        />
      </div>
      <button
        onClick={() =>
          onSave({
            weather: w,
            temperature: temp === "" ? null : Number(temp),
            humidity: humidity === "" ? null : Number(humidity),
          })
        }
        className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600"
      >
        保存
      </button>
      {error && <span className="text-xs font-medium text-red-500">{error}</span>}
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
