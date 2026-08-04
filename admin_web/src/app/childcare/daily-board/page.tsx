"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { ChildInternalNotesModal } from "@/components/ChildInternalNotesModal";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { classOrderIndex, compareByClassThenName } from "@/lib/childcareClassSort";
import { currentDate } from "@/lib/datetime";
import type { DailyBoardRow, DailyBoardSummary, WeatherRecord, NapMissing } from "@/lib/types";
import { DAILY_BOARD_STATUS_LABELS, WEATHER_OPTIONS, deriveContactBadge } from "@/lib/types";

function ChildcareDailyBoardPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();
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
  async function scheduleContacts(contactIds: string[], time: string) {
    if (contactIds.length === 0) return;
    const scheduledAt = `${businessDate}T${time}:00+09:00`;
    await createClient().rpc("schedule_child_daily_contacts", {
      p_contact_ids: contactIds,
      p_scheduled_at: scheduledAt,
    });
    setReloadToken((t) => t + 1);
  }

  async function publishContactsNow(contactIds: string[]) {
    if (contactIds.length === 0) return;
    await createClient().rpc("publish_child_daily_contacts_now", { p_contact_ids: contactIds });
    setReloadToken((t) => t + 1);
  }

  async function cancelContactSchedule(contactIds: string[]) {
    if (contactIds.length === 0) return;
    await createClient().rpc("cancel_child_daily_contacts_schedule", { p_contact_ids: contactIds });
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
                <th className="px-4 py-3">最終イベント</th>
                <th className="px-4 py-3">家庭連絡帳</th>
                <th className="px-4 py-3">お迎え変更</th>
                <th className="px-4 py-3">代理登録</th>
                <th className="px-4 py-3">連絡帳公開</th>
                {internalNotesEnabled && <th className="px-4 py-3">園内記録</th>}
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr>
                  <td colSpan={internalNotesEnabled ? 9 : 8} className="px-4 py-6 text-center text-slate-400">
                    読み込み中…
                  </td>
                </tr>
              )}
              {!isLoading && filteredRows.length === 0 && (
                <tr>
                  <td colSpan={internalNotesEnabled ? 9 : 8} className="px-4 py-6 text-center text-slate-400">
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
                      {row.on_therapy_outing && (
                        <span className="ml-1 rounded-full bg-violet-100 px-2 py-0.5 text-xs font-semibold text-violet-700">
                          療育外出中
                          {row.therapy_out_at
                            ? `(${new Date(row.therapy_out_at).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" })})`
                            : ""}
                        </span>
                      )}
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
