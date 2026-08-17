"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import {
  ENROLLMENT_SECTION_LABELS,
  ENROLLMENT_SECTION_ORDER,
  ENROLLMENT_STATUS_LABELS,
  enrollmentFieldLabel,
} from "@/lib/enrollmentFormLabels";
import type { EnrollmentFormReview, EnrollmentFormRow } from "@/lib/types";

function statusBadgeClass(status: string): string {
  switch (status) {
    case "submitted":
      return "bg-sky-100 text-sky-700";
    case "sent_back":
      return "bg-amber-100 text-amber-700";
    case "approved":
      return "bg-emerald-100 text-emerald-700";
    case "cancelled":
      return "bg-slate-100 text-slate-500";
    default:
      return "bg-slate-100 text-slate-600";
  }
}

function formatValue(v: unknown): string {
  if (v === true) return "はい";
  if (v === false) return "いいえ";
  return String(v ?? "");
}

function isEmptyValue(v: unknown): boolean {
  return v == null || v === "" || v === false;
}

/// 平熱・アレルギー・服薬の「要確認」情報を提出データから抽出する(草案§8.1)
function extractCautions(data: Record<string, unknown>): string[] {
  const cautions: string[] = [];
  const health = (data.health ?? {}) as Record<string, unknown>;
  const temp = Number(health.normal_temp ?? 0);
  if (temp >= 37.5) cautions.push(`平熱が ${temp}℃ で登録されています(37.5℃以上)`);
  if (health.has_allergy === true) {
    cautions.push(`アレルギーあり${health.allergy_foods ? `: ${health.allergy_foods}` : ""}`);
  }
  const meds = Array.isArray(health.medication) ? (health.medication as unknown[]) : [];
  if (meds.length > 0) cautions.push(`服薬情報が ${meds.length} 件登録されています`);
  return cautions;
}

function ReviewModal({
  formId,
  onClose,
  onChanged,
}: {
  formId: string;
  onClose: () => void;
  onChanged: () => void;
}) {
  const [review, setReview] = useState<EnrollmentFormReview | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [sendBackMessage, setSendBackMessage] = useState("");
  const [showSendBack, setShowSendBack] = useState(false);
  const [isActing, setIsActing] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_enrollment_form_review", { p_form_id: formId }).then(({ data, error }) => {
      if (error) {
        setLoadError(error.message);
        return;
      }
      const row = (Array.isArray(data) ? data[0] : data) as EnrollmentFormReview | undefined;
      setReview(row ?? null);
    });
  }, [formId]);

  async function sendBack() {
    if (!sendBackMessage.trim()) return;
    setIsActing(true);
    setActionError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("send_back_enrollment_form", {
      p_form_id: formId,
      p_message: sendBackMessage.trim(),
    });
    setIsActing(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    onChanged();
    onClose();
  }

  async function approve() {
    if (!window.confirm("提出内容を承認しますか?(園児氏名・性別・生年月日・世帯住所・お迎え者名簿へ反映されます)")) return;
    setIsActing(true);
    setActionError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("approve_enrollment_form", { p_form_id: formId });
    setIsActing(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    onChanged();
    onClose();
  }

  const data = (review?.data ?? {}) as Record<string, unknown>;
  const cautions = review ? extractCautions(data) : [];
  const basic = (data.basic ?? {}) as Record<string, unknown>;
  const address = (data.address ?? {}) as Record<string, unknown>;
  const currentAddress = review?.current_household
    ? ["postal_code", "prefecture", "city", "town", "address_line", "building"]
        .map((k) => review.current_household?.[k] ?? "")
        .filter(Boolean)
        .join(" ")
    : "";
  const submittedAddress = ["postal_code", "prefecture", "city", "town", "address_line", "building"]
    .map((k) => (address[k] ?? "") as string)
    .filter(Boolean)
    .join(" ");

  const diffRows: { label: string; current: string; submitted: string }[] = review
    ? [
        { label: "園児氏名", current: review.current_full_name, submitted: formatValue(basic.full_name) },
        { label: "ふりがな", current: review.current_name_kana ?? "", submitted: formatValue(basic.name_kana) },
        { label: "呼び名(愛称)", current: review.current_display_name, submitted: formatValue(basic.nickname) },
        { label: "性別", current: review.current_gender ?? "", submitted: formatValue(basic.gender) },
        { label: "生年月日", current: review.current_birth_date ?? "", submitted: formatValue(basic.birth_date) },
        { label: "世帯住所", current: currentAddress, submitted: submittedAddress },
      ]
    : [];

  const isPending = review?.review_status === "pending";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4 py-8">
      <div className="flex max-h-full w-full max-w-3xl flex-col rounded-2xl bg-white shadow-lg">
        <div className="flex items-center justify-between border-b border-slate-200 px-6 py-4">
          <div>
            <h2 className="text-base font-bold text-slate-800">入園時基本情報の確認</h2>
            {review && (
              <p className="text-xs text-slate-400">
                {review.current_full_name} / 提出 第{review.version ?? "—"}版
                {review.submitted_at ? `(${new Date(review.submitted_at).toLocaleString("ja-JP")})` : ""}
              </p>
            )}
          </div>
          <button onClick={onClose} className="rounded-lg px-3 py-1 text-sm text-slate-500 hover:bg-slate-100">
            閉じる
          </button>
        </div>

        <div className="flex-1 space-y-4 overflow-y-auto px-6 py-4">
          {loadError && <p className="text-sm font-medium text-red-500">{loadError}</p>}
          {!review && !loadError && <p className="text-sm text-slate-400">読み込み中…</p>}

          {review && (
            <>
              {cautions.length > 0 && (
                <div className="rounded-xl border border-amber-300 bg-amber-50 p-4">
                  <p className="text-sm font-bold text-amber-800">要確認の健康・医療情報</p>
                  <ul className="mt-1 space-y-0.5 text-sm text-amber-900">
                    {cautions.map((c, i) => (
                      <li key={i}>・{c}</li>
                    ))}
                  </ul>
                </div>
              )}

              {review.review_message && review.review_status === "sent_back" && (
                <div className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
                  差し戻し中: {review.review_message}
                </div>
              )}

              <div>
                <h3 className="mb-2 text-sm font-bold text-slate-700">園の登録値と提出値の差分(承認で提出値を正本へ反映)</h3>
                <table className="min-w-full text-sm">
                  <thead>
                    <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                      <th className="px-3 py-2">項目</th>
                      <th className="px-3 py-2">園の登録値</th>
                      <th className="px-3 py-2">保護者の提出値</th>
                    </tr>
                  </thead>
                  <tbody>
                    {diffRows.map((r) => {
                      const changed = r.submitted !== "" && r.submitted !== r.current;
                      return (
                        <tr key={r.label} className="border-b border-slate-100 last:border-0">
                          <td className="px-3 py-2 text-slate-500">{r.label}</td>
                          <td className="px-3 py-2">{r.current || "—"}</td>
                          <td className={`px-3 py-2 ${changed ? "font-bold text-sky-700" : ""}`}>
                            {r.submitted || "—"}
                            {changed && <span className="ml-1 rounded bg-sky-100 px-1 text-xs">変更</span>}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              <div className="space-y-3">
                <h3 className="text-sm font-bold text-slate-700">提出内容(全セクション)</h3>
                {ENROLLMENT_SECTION_ORDER.map((sectionKey) => {
                  const section = data[sectionKey];
                  if (section == null) return null;
                  return (
                    <div key={sectionKey} className="rounded-xl border border-slate-200 p-3">
                      <p className="mb-2 text-xs font-bold text-sky-700">
                        {ENROLLMENT_SECTION_LABELS[sectionKey] ?? sectionKey}
                      </p>
                      <SectionContent value={section} />
                    </div>
                  );
                })}
              </div>
            </>
          )}
        </div>

        {review && (
          <div className="space-y-3 border-t border-slate-200 px-6 py-4">
            {actionError && <p className="text-sm font-medium text-red-500">{actionError}</p>}
            {showSendBack && (
              <div className="space-y-2">
                <textarea
                  value={sendBackMessage}
                  onChange={(e) => setSendBackMessage(e.target.value)}
                  rows={2}
                  placeholder="差し戻しの理由・修正してほしい項目(保護者へ通知されます)"
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
            )}
            <div className="flex justify-end gap-3">
              {isPending && !showSendBack && (
                <button
                  onClick={() => setShowSendBack(true)}
                  className="rounded-lg border border-amber-400 px-4 py-2 text-sm font-semibold text-amber-700 hover:bg-amber-50"
                >
                  差し戻す
                </button>
              )}
              {isPending && showSendBack && (
                <button
                  onClick={sendBack}
                  disabled={isActing || !sendBackMessage.trim()}
                  className="rounded-lg bg-amber-500 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-600 disabled:opacity-50"
                >
                  {isActing ? "送信中…" : "差し戻しを送信"}
                </button>
              )}
              {isPending && (
                <button
                  onClick={approve}
                  disabled={isActing}
                  className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-50"
                >
                  {isActing ? "処理中…" : "承認して正本へ反映"}
                </button>
              )}
              {!isPending && (
                <span className="text-sm text-slate-400">
                  {review.form_status === "approved" ? "承認済みです" : "確認待ちの提出はありません"}
                </span>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

/// セクション値の汎用表示。Map=ラベル+値の行、配列=要素カード、ネスト配列(emergency等)にも対応。
function SectionContent({ value }: { value: unknown }) {
  if (Array.isArray(value)) {
    if (value.length === 0) return <p className="text-xs text-slate-400">登録なし</p>;
    return (
      <div className="space-y-2">
        {value.map((item, i) => (
          <div key={i} className="rounded-lg bg-slate-50 p-2">
            <SectionContent value={item} />
          </div>
        ))}
      </div>
    );
  }
  if (typeof value === "object" && value != null) {
    const entries = Object.entries(value as Record<string, unknown>).filter(([, v]) => !isEmptyValue(v));
    if (entries.length === 0) return <p className="text-xs text-slate-400">入力なし</p>;
    return (
      <div className="space-y-1">
        {entries.map(([k, v]) =>
          Array.isArray(v) ? (
            <div key={k}>
              <p className="mt-1 text-xs font-semibold text-slate-500">{enrollmentFieldLabel(k)}</p>
              <SectionContent value={v} />
            </div>
          ) : (
            <div key={k} className="flex gap-2 text-sm">
              <span className="w-40 shrink-0 text-xs leading-5 text-slate-400">{enrollmentFieldLabel(k)}</span>
              <span className="whitespace-pre-wrap">{formatValue(v)}</span>
            </div>
          ),
        )}
      </div>
    );
  }
  return <span className="text-sm">{formatValue(value)}</span>;
}

function EnrollmentFormsPageContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const [rows, setRows] = useState<EnrollmentFormRow[]>([]);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const [reviewFormId, setReviewFormId] = useState<string | null>(null);

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    if (!selectedOffice) return;
    setIsLoading(true);
    setRowsError(null);
    const supabase = createClient();
    supabase
      .rpc("fetch_enrollment_forms_for_office", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
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
        setRows((data ?? []) as EnrollmentFormRow[]);
      });
  }, [selectedOffice, reloadToken]);

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
      <ChildcareNav />
      <main className="flex-1 space-y-6 p-6">
        <div>
          <h2 className="text-lg font-bold text-slate-800">入園手続き(入園時基本情報)</h2>
          <p className="text-xs text-slate-400">
            保護者が提出した入園時基本情報を確認し、承認または差し戻します。承認すると園児氏名・性別・生年月日・世帯住所・お迎え者名簿へ反映されます。
          </p>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-4 py-3">園児</th>
                <th className="px-4 py-3">状態</th>
                <th className="px-4 py-3">入力進捗</th>
                <th className="px-4 py-3">最終保存</th>
                <th className="px-4 py-3">最新提出</th>
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
              {!isLoading && rows.length === 0 && !rowsError && (
                <tr>
                  <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                    入園フォームはまだありません(保護者が入力を開始すると表示されます)
                  </td>
                </tr>
              )}
              {!isLoading &&
                rows.map((row) => (
                  <tr key={row.form_id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                    <td className="px-4 py-3 font-medium text-slate-800">
                      {row.child_full_name}
                      {row.child_name_kana && (
                        <span className="ml-2 text-xs text-slate-400">{row.child_name_kana}</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${statusBadgeClass(row.status)}`}>
                        {ENROLLMENT_STATUS_LABELS[row.status] ?? row.status}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-slate-500">{row.current_step}/10</td>
                    <td className="px-4 py-3 text-slate-500">
                      {row.last_saved_at ? new Date(row.last_saved_at).toLocaleString("ja-JP") : "—"}
                    </td>
                    <td className="px-4 py-3 text-slate-500">
                      {row.latest_version != null
                        ? `第${row.latest_version}版 ${row.latest_submitted_at ? new Date(row.latest_submitted_at).toLocaleString("ja-JP") : ""}`
                        : "—"}
                    </td>
                    <td className="px-4 py-3 text-right">
                      {row.latest_version != null && (
                        <button
                          onClick={() => setReviewFormId(row.form_id)}
                          className={`rounded-lg px-3 py-1 text-xs font-medium ${
                            row.status === "submitted"
                              ? "bg-sky-600 text-white hover:bg-sky-700"
                              : "border border-slate-300 text-slate-600 hover:bg-slate-100"
                          }`}
                        >
                          {row.status === "submitted" ? "確認する" : "内容を見る"}
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </main>

      {reviewFormId && (
        <ReviewModal formId={reviewFormId} onClose={() => setReviewFormId(null)} onChanged={reload} />
      )}
    </div>
  );
}

export default function EnrollmentFormsPage() {
  return (
    <Suspense fallback={null}>
      <EnrollmentFormsPageContent />
    </Suspense>
  );
}
