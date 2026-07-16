"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { currentDate } from "@/lib/datetime";
import type { ChildcareOffice, DailyContactRow } from "@/lib/types";

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

export default function ChildcareContactsPage() {
  const [offices, setOffices] = useState<ChildcareOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [selectedOffice, setSelectedOffice] = useState<string>("");
  const [isManager, setIsManager] = useState(false);

  const [businessDate, setBusinessDate] = useState(currentDate());
  const [rows, setRows] = useState<DailyContactRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [selectedChildId, setSelectedChildId] = useState<string | null>(null);
  const [form, setForm] = useState({ guardian_message: "", child_today_notes: "", free_notes: "" });
  const [editableText, setEditableText] = useState("");
  const [adminComment, setAdminComment] = useState("");
  const [noticeMasters, setNoticeMasters] = useState<NoticeMaster[]>([]);
  const [checkedNoticeIds, setCheckedNoticeIds] = useState<Set<string>>(new Set());
  const [isBusy, setIsBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const selectedRow = rows.find((r) => r.child_id === selectedChildId) ?? null;

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_childcare_offices").then(({ data, error }) => {
      if (error) {
        setOfficesError(error.message);
        return;
      }
      const list = (data ?? []) as ChildcareOffice[];
      setOffices(list);
      if (list.length > 0) {
        setSelectedOffice(list[0].office_id);
        setIsManager(list[0].is_manager);
      }
    });
  }, []);

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
      .update({ ...form, current_text: editableText })
      .eq("id", selectedRow.contact_id);
    setIsBusy(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
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
                setIsManager(offices?.find((o) => o.office_id === e.target.value)?.is_manager ?? false);
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
                  <span className="text-xs text-slate-500">担当: {selectedRow.assignee_name ?? "未割当"}</span>
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
    </div>
  );
}
