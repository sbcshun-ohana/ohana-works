"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { ChildInternalNotesModal } from "@/components/ChildInternalNotesModal";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { currentDate } from "@/lib/datetime";
import type { DailyContactRow, FamilyDailyReportSummary } from "@/lib/types";
import { FAMILY_BOWEL_CONDITION_LABELS, FAMILY_MOOD_LABELS, MEAL_COMPLETION_OPTIONS, TOILETING_TYPES } from "@/lib/types";

const TEMPERATURE_OPTIONS = Array.from({ length: 71 }, (_, i) => (35.0 + i * 0.1).toFixed(1));

const STATUS_LABELS: Record<string, string> = {
  draft: "下書き",
  submitted: "申請中",
  approved: "承認済み",
  rejected: "差し戻し",
};

type NoticeMaster = { id: string; label: string; sort_order: number };

const AI_ACTIONS: { key: string; label: string }[] = [
  { key: "generate", label: "AI生成" },
  { key: "shorten", label: "短く" },
  { key: "lengthen", label: "詳しく" },
  { key: "soften", label: "やわらかく" },
  { key: "add_care", label: "気遣い追加" },
  { key: "clarify", label: "重要事項明確化" },
  { key: "regenerate", label: "作り直し" },
];

function ChildcareContactsPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;

  const [businessDate, setBusinessDate] = useState(currentDate());
  const [rows, setRows] = useState<DailyContactRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [selectedChildId, setSelectedChildId] = useState<string | null>(null);
  const [form, setForm] = useState({ guardian_message: "", child_today_notes: "", free_notes: "" });
  const [napPeriods, setNapPeriods] = useState<{ start: string; end: string }[]>([]);
  const [toiletingRecords, setToiletingRecords] = useState<{ time: string; type: string }[]>([]);
  const [mealCompletionPct, setMealCompletionPct] = useState<number | "">("");
  const [mealFreeNote, setMealFreeNote] = useState("");
  const [temperature, setTemperature] = useState("");
  const [temperatureMeasuredAt, setTemperatureMeasuredAt] = useState("");
  const [bathTaken, setBathTaken] = useState<boolean | null>(null);
  const [editableText, setEditableText] = useState("");
  const [adminComment, setAdminComment] = useState("");
  const [noticeMasters, setNoticeMasters] = useState<NoticeMaster[]>([]);
  const [checkedNoticeIds, setCheckedNoticeIds] = useState<Set<string>>(new Set());
  const [isBusy, setIsBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [familyDailyReport, setFamilyDailyReport] = useState<FamilyDailyReportSummary | null>(null);
  const [internalNotesEnabled, setInternalNotesEnabled] = useState(false);
  const [internalNotesOpen, setInternalNotesOpen] = useState(false);

  const selectedRow = rows.find((r) => r.child_id === selectedChildId) ?? null;

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
      .rpc("fetch_daily_contacts_for_office", {
        p_office_id: selectedOffice,
        p_business_date: businessDate,
      })
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRows((data ?? []) as DailyContactRow[]);
      });
    supabase
      .from("individual_notice_masters")
      .select("id, label, sort_order")
      .eq("office_id", selectedOffice)
      .eq("is_active", true)
      .order("sort_order")
      .then(({ data, error }) => {
        if (!error) setNoticeMasters((data ?? []) as NoticeMaster[]);
      });
  }, [selectedOffice, businessDate, reloadToken]);

  useEffect(() => {
    function syncForm() {
      if (!selectedRow) return;
      setForm({
        guardian_message: selectedRow.guardian_message ?? "",
        child_today_notes: selectedRow.child_today_notes ?? "",
        free_notes: selectedRow.free_notes ?? "",
      });
      setNapPeriods(selectedRow.nap_periods ?? []);
      setToiletingRecords(selectedRow.toileting_records ?? []);
      setMealCompletionPct(selectedRow.meal_completion_pct ?? "");
      setMealFreeNote(selectedRow.meal_free_note ?? "");
      setTemperature(selectedRow.temperature != null ? selectedRow.temperature.toFixed(1) : "");
      setTemperatureMeasuredAt(selectedRow.temperature_measured_at?.slice(0, 5) ?? "");
      setBathTaken(selectedRow.bath_taken);
      setEditableText(selectedRow.current_text ?? selectedRow.ai_generated_text ?? "");
      setAdminComment("");
    }
    syncForm();

    function loadNoticeChecks() {
      if (!selectedRow?.contact_id) {
        setCheckedNoticeIds(new Set());
        return null;
      }
      return createClient()
        .from("child_daily_contact_notice_checks")
        .select("notice_master_id")
        .eq("contact_id", selectedRow.contact_id);
    }

    loadNoticeChecks()?.then(({ data }) => {
      setCheckedNoticeIds(new Set((data ?? []).map((r) => r.notice_master_id as string)));
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedRow?.contact_id, selectedRow?.child_id]);

  useEffect(() => {
    // family_daily_reports(保護者記入の家庭連絡帳)は既存RLS(staff_has_guardian_data_access)で
    // 保護されているため、専用RPCを介さず直接SELECTでよい。
    function loadFamilyDailyReport() {
      if (!selectedRow?.child_id) {
        setFamilyDailyReport(null);
        return null;
      }
      return createClient()
        .from("family_daily_reports")
        .select()
        .eq("child_id", selectedRow.child_id)
        .eq("business_date", businessDate)
        .maybeSingle();
    }

    loadFamilyDailyReport()?.then(({ data }) => {
      setFamilyDailyReport((data as FamilyDailyReportSummary | null) ?? null);
    });
  }, [selectedRow?.child_id, businessDate]);

  async function ensureAndSelect(childId: string) {
    setSelectedChildId(childId);
    const row = rows.find((r) => r.child_id === childId);
    if (row?.contact_id) return;

    const supabase = createClient();
    const { error } = await supabase.rpc("ensure_child_daily_contact", {
      p_child_id: childId,
      p_business_date: businessDate,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function saveContent() {
    if (!selectedRow?.contact_id) return;
    setIsBusy(true);
    setActionError(null);
    const supabase = createClient();
    const { error } = await supabase
      .from("child_daily_contacts")
      .update({
        ...form,
        current_text: editableText,
        nap_periods: napPeriods,
        toileting_records: toiletingRecords,
        meal_completion_pct: mealCompletionPct === "" ? null : mealCompletionPct,
        meal_free_note: mealFreeNote || null,
        temperature: temperature === "" ? null : Number(temperature),
        temperature_measured_at: temperatureMeasuredAt || null,
        bath_taken: bathTaken,
      })
      .eq("id", selectedRow.contact_id);
    setIsBusy(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  function addNapPeriod() {
    setNapPeriods((prev) => [...prev, { start: "13:00", end: "14:30" }]);
  }
  function updateNapPeriod(index: number, field: "start" | "end", value: string) {
    setNapPeriods((prev) => prev.map((p, i) => (i === index ? { ...p, [field]: value } : p)));
  }
  function removeNapPeriod(index: number) {
    setNapPeriods((prev) => prev.filter((_, i) => i !== index));
  }

  function addToiletingRecord() {
    setToiletingRecords((prev) => [...prev, { time: "10:00", type: TOILETING_TYPES[0] }]);
  }
  function updateToiletingRecord(index: number, field: "time" | "type", value: string) {
    setToiletingRecords((prev) => prev.map((r, i) => (i === index ? { ...r, [field]: value } : r)));
  }
  function removeToiletingRecord(index: number) {
    setToiletingRecords((prev) => prev.filter((_, i) => i !== index));
  }

  async function toggleNoticeCheck(noticeMasterId: string) {
    if (!selectedRow?.contact_id) return;
    const supabase = createClient();
    if (checkedNoticeIds.has(noticeMasterId)) {
      await supabase
        .from("child_daily_contact_notice_checks")
        .delete()
        .eq("contact_id", selectedRow.contact_id)
        .eq("notice_master_id", noticeMasterId);
    } else {
      await supabase.from("child_daily_contact_notice_checks").insert({
        contact_id: selectedRow.contact_id,
        notice_master_id: noticeMasterId,
      });
    }
    setReloadToken((t) => t + 1);
  }

  async function runAiAction(action: string) {
    if (!selectedRow?.contact_id) return;
    setIsBusy(true);
    setActionError(null);
    // AI生成の前に、その場の入力内容を保存しておく(class_activity/child_contactへの反映のため)。
    await saveContent();

    const supabase = createClient();
    const { data, error } = await supabase.functions.invoke("generate-contact-note", {
      body: {
        child_id: selectedRow.child_id,
        business_date: businessDate,
        action,
        current_text: editableText || undefined,
      },
    });
    setIsBusy(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    setEditableText(data.contact_text as string);

    const updatePayload: Record<string, unknown> = { current_text: data.contact_text };
    if (action === "generate" || action === "regenerate") {
      updatePayload.ai_generated_text = data.contact_text;
    }
    await supabase.from("child_daily_contacts").update(updatePayload).eq("id", selectedRow.contact_id);

    if (data.journal_sections) {
      const js = data.journal_sections as Record<string, string>;
      const { data: existingJournal } = await supabase
        .from("child_personal_journals")
        .select("id")
        .eq("child_id", selectedRow.child_id)
        .eq("business_date", businessDate)
        .maybeSingle();
      if (existingJournal) {
        await supabase
          .from("child_personal_journals")
          .update({
            ai_generated_text: JSON.stringify(js),
            current_text: JSON.stringify(js),
            content_fact: js.fact,
            content_support: js.support,
            content_reaction: js.reaction,
            content_progress: js.progress,
            content_consideration: js.consideration,
            content_handover: js.handover,
          })
          .eq("id", existingJournal.id);
      } else {
        await supabase.from("child_personal_journals").insert({
          child_id: selectedRow.child_id,
          business_date: businessDate,
          content_fact: js.fact,
          content_support: js.support,
          content_reaction: js.reaction,
          content_progress: js.progress,
          content_consideration: js.consideration,
          content_handover: js.handover,
          ai_generated_text: JSON.stringify(js),
          current_text: JSON.stringify(js),
        });
      }
    }
    setReloadToken((t) => t + 1);
  }

  async function submit() {
    if (!selectedRow?.contact_id) return;
    await saveContent();
    const supabase = createClient();
    const { error } = await supabase.rpc("submit_child_daily_contact", {
      p_contact_id: selectedRow.contact_id,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function approve() {
    if (!selectedRow?.contact_id) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("approve_child_daily_contact", {
      p_contact_id: selectedRow.contact_id,
      p_final_text: editableText,
      p_admin_comment: adminComment || null,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function reject() {
    if (!selectedRow?.contact_id) return;
    const reason = window.prompt("差し戻し理由を入力してください(必須)");
    if (!reason) return;
    const supabase = createClient();
    const { error } = await supabase.rpc("reject_child_daily_contact", {
      p_contact_id: selectedRow.contact_id,
      p_reason: reason,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  const canEditInput = selectedRow?.status === "draft" || selectedRow?.status === "rejected" || isManager;
  const canSubmit = selectedRow?.status === "draft" || selectedRow?.status === "rejected";

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
        <h2 className="text-lg font-bold text-slate-800">連絡帳 一覧・承認・差し戻し</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => {
                setSelectedOffice(e.target.value);
                setSelectedChildId(null);
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
            <label className="mb-1 block text-xs font-medium text-slate-500">対象日</label>
            <input
              type="date"
              value={businessDate}
              onChange={(e) => {
                setBusinessDate(e.target.value);
                setSelectedChildId(null);
              }}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}
        {actionError && <p className="text-sm font-medium text-red-500">{actionError}</p>}

        <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
          <div className="overflow-hidden rounded-2xl bg-white shadow-sm md:col-span-1">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">園児</th>
                  <th className="px-4 py-3">状態</th>
                </tr>
              </thead>
              <tbody>
                {isLoading && (
                  <tr>
                    <td colSpan={2} className="px-4 py-6 text-center text-slate-400">
                      読み込み中…
                    </td>
                  </tr>
                )}
                {!isLoading &&
                  rows.map((row) => (
                    <tr
                      key={row.child_id}
                      onClick={() => ensureAndSelect(row.child_id)}
                      className={`cursor-pointer border-b border-slate-100 last:border-0 hover:bg-slate-50 ${
                        selectedChildId === row.child_id ? "bg-sky-50" : ""
                      } ${row.is_absent ? "opacity-50" : ""}`}
                    >
                      <td className="px-4 py-3 font-medium text-slate-800">
                        {row.child_display_name}
                        {row.child_honorific_suffix ?? ""}
                        {row.is_absent && <span className="ml-1 text-xs text-red-500">(欠席)</span>}
                      </td>
                      <td className="px-4 py-3">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                            row.status === "approved"
                              ? "bg-emerald-50 text-emerald-700"
                              : row.status === "rejected"
                                ? "bg-red-50 text-red-600"
                                : row.status === "submitted"
                                  ? "bg-sky-50 text-sky-700"
                                  : "bg-slate-100 text-slate-500"
                          }`}
                        >
                          {row.status ? STATUS_LABELS[row.status] : "未着手"}
                        </span>
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>

          <div className="rounded-2xl bg-white p-4 shadow-sm md:col-span-2">
            {!selectedRow && <p className="text-sm text-slate-400">左の園児を選択してください</p>}
            {selectedRow && (
              <div className="space-y-4">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <h3 className="text-base font-bold text-slate-800">
                    {selectedRow.child_display_name}
                    {selectedRow.child_honorific_suffix ?? ""}({selectedRow.class_name})
                  </h3>
                  <div className="flex items-center gap-3">
                    {internalNotesEnabled && (
                      <button
                        onClick={() => setInternalNotesOpen(true)}
                        className="rounded-lg border border-amber-400 bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-100"
                      >
                        🔒 園内記録(保護者非公開)
                      </button>
                    )}
                    <span className="text-xs text-slate-500">担当: {selectedRow.assignee_name ?? "未割当"}</span>
                  </div>
                </div>

                {selectedRow.rejected_reason && (
                  <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-700">
                    差し戻し理由: {selectedRow.rejected_reason}
                  </div>
                )}
                {selectedRow.admin_comment && (
                  <div className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800">
                    管理者コメント(保護者非公開): {selectedRow.admin_comment}
                  </div>
                )}

                <div className="rounded-xl bg-slate-50 p-4 text-sm">
                  <p className="mb-2 font-semibold text-slate-700">保護者記入(家庭連絡帳)</p>
                  {!familyDailyReport && <p className="text-slate-400">本日分の家庭連絡帳はまだ提出されていません</p>}
                  {familyDailyReport && (
                    <div className="space-y-1 text-slate-600">
                      {familyDailyReport.status !== "submitted" && (
                        <p className="text-amber-600">※下書き中(未提出)の内容です</p>
                      )}
                      <p>
                        体温: {familyDailyReport.temperature != null ? `${familyDailyReport.temperature.toFixed(1)}℃` : "—"}(
                        {familyDailyReport.temperature_measured_at?.slice(0, 5) ?? "—"})
                        {familyDailyReport.temperature != null && familyDailyReport.temperature >= 37.5 && (
                          <span className="ml-2 font-semibold text-red-600">37.5℃以上</span>
                        )}
                      </p>
                      <p>症状: {familyDailyReport.symptoms || "—"}</p>
                      <p>自宅での様子: {familyDailyReport.home_notes || "—"}</p>
                      <p>
                        機嫌(夜/朝): {FAMILY_MOOD_LABELS[familyDailyReport.night_mood ?? ""] ?? "—"} /{" "}
                        {FAMILY_MOOD_LABELS[familyDailyReport.morning_mood ?? ""] ?? "—"}
                      </p>
                      <p>
                        排便(夜/朝):{" "}
                        {familyDailyReport.night_bowel_count == null
                          ? "—"
                          : familyDailyReport.night_bowel_count === 0
                            ? "0回"
                            : `${familyDailyReport.night_bowel_count}回(${FAMILY_BOWEL_CONDITION_LABELS[familyDailyReport.night_bowel_condition ?? ""] ?? "—"})`}{" "}
                        /{" "}
                        {familyDailyReport.morning_bowel_count == null
                          ? "—"
                          : familyDailyReport.morning_bowel_count === 0
                            ? "0回"
                            : `${familyDailyReport.morning_bowel_count}回(${FAMILY_BOWEL_CONDITION_LABELS[familyDailyReport.morning_bowel_condition ?? ""] ?? "—"})`}
                      </p>
                      <p>
                        睡眠: {familyDailyReport.sleep_start_at?.slice(0, 5) ?? "—"} 〜{" "}
                        {familyDailyReport.sleep_end_at?.slice(0, 5) ?? "—"}
                      </p>
                      <p>
                        夕食: {familyDailyReport.dinner_content || "—"}({familyDailyReport.dinner_at?.slice(0, 5) ?? "—"})
                      </p>
                      <p>
                        朝食: {familyDailyReport.breakfast_content || "—"}(
                        {familyDailyReport.breakfast_at?.slice(0, 5) ?? "—"})
                      </p>
                      {familyDailyReport.pickup_person_name && (
                        <div className="mt-2 rounded-lg bg-amber-100 p-2 font-semibold text-amber-800">
                          お迎え変更あり: {familyDailyReport.pickup_person_name}(
                          {familyDailyReport.pickup_person_relationship || "続柄未記入"}){" "}
                          {familyDailyReport.pickup_time_from?.slice(0, 5) ?? "—"}〜
                          {familyDailyReport.pickup_time_to?.slice(0, 5) ?? "—"}
                        </div>
                      )}
                    </div>
                  )}
                </div>

                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">保護者からの連絡内容</label>
                  <textarea
                    value={form.guardian_message}
                    onChange={(e) => setForm((f) => ({ ...f, guardian_message: e.target.value }))}
                    disabled={!canEditInput}
                    rows={2}
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none disabled:bg-slate-50 disabled:text-slate-400"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">今日の園児の様子</label>
                  <textarea
                    value={form.child_today_notes}
                    onChange={(e) => setForm((f) => ({ ...f, child_today_notes: e.target.value }))}
                    disabled={!canEditInput}
                    rows={2}
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none disabled:bg-slate-50 disabled:text-slate-400"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">その他自由記載</label>
                  <textarea
                    value={form.free_notes}
                    onChange={(e) => setForm((f) => ({ ...f, free_notes: e.target.value }))}
                    disabled={!canEditInput}
                    rows={2}
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none disabled:bg-slate-50 disabled:text-slate-400"
                  />
                </div>

                <div className="grid grid-cols-1 gap-4 rounded-xl border border-slate-200 p-4 md:grid-cols-2">
                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-500">午睡時間</label>
                    {napPeriods.map((p, i) => (
                      <div key={i} className="mb-2 flex items-center gap-2">
                        <input
                          type="time"
                          value={p.start}
                          disabled={!canEditInput}
                          onChange={(e) => updateNapPeriod(i, "start", e.target.value)}
                          className="rounded-lg border border-slate-300 px-2 py-1 text-sm disabled:bg-slate-50"
                        />
                        <span className="text-slate-400">〜</span>
                        <input
                          type="time"
                          value={p.end}
                          disabled={!canEditInput}
                          onChange={(e) => updateNapPeriod(i, "end", e.target.value)}
                          className="rounded-lg border border-slate-300 px-2 py-1 text-sm disabled:bg-slate-50"
                        />
                        {canEditInput && (
                          <button
                            onClick={() => removeNapPeriod(i)}
                            className="text-xs text-red-500 hover:underline"
                          >
                            削除
                          </button>
                        )}
                      </div>
                    ))}
                    {canEditInput && (
                      <button
                        onClick={addNapPeriod}
                        className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                      >
                        + 時間帯を追加
                      </button>
                    )}
                  </div>

                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-500">排泄</label>
                    {toiletingRecords.map((r, i) => (
                      <div key={i} className="mb-2 flex items-center gap-2">
                        <input
                          type="time"
                          value={r.time}
                          disabled={!canEditInput}
                          onChange={(e) => updateToiletingRecord(i, "time", e.target.value)}
                          className="rounded-lg border border-slate-300 px-2 py-1 text-sm disabled:bg-slate-50"
                        />
                        <select
                          value={r.type}
                          disabled={!canEditInput}
                          onChange={(e) => updateToiletingRecord(i, "type", e.target.value)}
                          className="rounded-lg border border-slate-300 px-2 py-1 text-sm disabled:bg-slate-50"
                        >
                          {TOILETING_TYPES.map((t) => (
                            <option key={t} value={t}>
                              {t}
                            </option>
                          ))}
                        </select>
                        {canEditInput && (
                          <button
                            onClick={() => removeToiletingRecord(i)}
                            className="text-xs text-red-500 hover:underline"
                          >
                            削除
                          </button>
                        )}
                      </div>
                    ))}
                    {canEditInput && (
                      <button
                        onClick={addToiletingRecord}
                        className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                      >
                        + 記録を追加
                      </button>
                    )}
                  </div>

                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-500">食事(昼食の完食割合)</label>
                    <select
                      value={mealCompletionPct}
                      disabled={!canEditInput}
                      onChange={(e) => setMealCompletionPct(e.target.value === "" ? "" : Number(e.target.value))}
                      className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-50"
                    >
                      <option value="">未記録</option>
                      {MEAL_COMPLETION_OPTIONS.map((v) => (
                        <option key={v} value={v}>
                          {v}%
                        </option>
                      ))}
                    </select>
                    <input
                      type="text"
                      value={mealFreeNote}
                      disabled={!canEditInput}
                      onChange={(e) => setMealFreeNote(e.target.value)}
                      placeholder="食事に関する自由記入(連絡帳へ反映)"
                      className="mt-2 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-50"
                    />
                  </div>

                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-500">検温</label>
                    <div className="flex items-center gap-2">
                      <select
                        value={temperature}
                        disabled={!canEditInput}
                        onChange={(e) => setTemperature(e.target.value)}
                        className="rounded-lg border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-50"
                      >
                        <option value="">未計測</option>
                        {TEMPERATURE_OPTIONS.map((t) => (
                          <option key={t} value={t}>
                            {t}℃
                          </option>
                        ))}
                      </select>
                      <input
                        type="time"
                        value={temperatureMeasuredAt}
                        disabled={!canEditInput}
                        onChange={(e) => setTemperatureMeasuredAt(e.target.value)}
                        className="rounded-lg border border-slate-300 px-2 py-1 text-sm disabled:bg-slate-50"
                      />
                    </div>
                    {temperature !== "" && Number(temperature) >= 37.5 && (
                      <p className="mt-1 text-xs font-medium text-amber-600">
                        37.5℃以上です。登園基準の確認・欠席申請の案内をご検討ください。
                      </p>
                    )}
                  </div>

                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-500">入浴</label>
                    <div className="flex gap-2">
                      <button
                        type="button"
                        disabled={!canEditInput}
                        onClick={() => setBathTaken(true)}
                        className={`rounded-lg border px-3 py-1 text-xs font-medium ${
                          bathTaken === true
                            ? "border-sky-500 bg-sky-50 text-sky-700"
                            : "border-slate-300 text-slate-600"
                        }`}
                      >
                        あり
                      </button>
                      <button
                        type="button"
                        disabled={!canEditInput}
                        onClick={() => setBathTaken(false)}
                        className={`rounded-lg border px-3 py-1 text-xs font-medium ${
                          bathTaken === false
                            ? "border-sky-500 bg-sky-50 text-sky-700"
                            : "border-slate-300 text-slate-600"
                        }`}
                      >
                        なし
                      </button>
                    </div>
                  </div>
                </div>

                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">個別のお知らせ</label>
                  <div className="flex flex-wrap gap-2">
                    {noticeMasters.map((nm) => (
                      <label
                        key={nm.id}
                        className="flex items-center gap-1 rounded-lg border border-slate-300 px-2 py-1 text-xs"
                      >
                        <input
                          type="checkbox"
                          checked={checkedNoticeIds.has(nm.id)}
                          disabled={!canEditInput}
                          onChange={() => toggleNoticeCheck(nm.id)}
                        />
                        {nm.label}
                      </label>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="mb-1 block text-xs font-medium text-slate-500">連絡帳本文(保護者向け)</label>
                  <textarea
                    value={editableText}
                    onChange={(e) => setEditableText(e.target.value)}
                    disabled={!canEditInput}
                    rows={5}
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none disabled:bg-slate-50 disabled:text-slate-400"
                  />
                  <div className="mt-2 flex flex-wrap gap-2">
                    {AI_ACTIONS.map((a) => (
                      <button
                        key={a.key}
                        onClick={() => runAiAction(a.key)}
                        disabled={isBusy || !canEditInput}
                        className="rounded-lg border border-sky-300 px-3 py-1 text-xs font-medium text-sky-700 hover:bg-sky-50 disabled:opacity-40"
                      >
                        {a.label}
                      </button>
                    ))}
                  </div>
                </div>

                {isManager && selectedRow.status === "submitted" && (
                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-500">
                      職員向けコメント(保護者向け本文には含まれません)
                    </label>
                    <textarea
                      value={adminComment}
                      onChange={(e) => setAdminComment(e.target.value)}
                      rows={2}
                      className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                    />
                  </div>
                )}

                <div className="flex flex-wrap gap-2 pt-2">
                  {canEditInput && (
                    <button
                      onClick={saveContent}
                      disabled={isBusy}
                      className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-50"
                    >
                      下書き保存
                    </button>
                  )}
                  {canSubmit && (
                    <button
                      onClick={submit}
                      className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
                    >
                      申請する
                    </button>
                  )}
                  {isManager && selectedRow.status === "submitted" && (
                    <>
                      <button
                        onClick={approve}
                        className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700"
                      >
                        承認する
                      </button>
                      <button
                        onClick={reject}
                        className="rounded-lg border border-red-300 px-4 py-2 text-sm font-medium text-red-600 hover:bg-red-50"
                      >
                        差し戻す
                      </button>
                    </>
                  )}
                </div>
              </div>
            )}
          </div>
        </div>
      </main>

      {internalNotesOpen && selectedRow && (
        <ChildInternalNotesModal
          childId={selectedRow.child_id}
          childName={`${selectedRow.child_display_name}${selectedRow.child_honorific_suffix ?? ""}`}
          officeId={selectedOffice}
          onClose={() => setInternalNotesOpen(false)}
        />
      )}
    </div>
  );
}

export default function ChildcareContactsPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareContactsPageContent />
    </Suspense>
  );
}
