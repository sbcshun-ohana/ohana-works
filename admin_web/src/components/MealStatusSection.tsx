"use client";

import { useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { currentDate } from "@/lib/datetime";

type MealRow = {
  child_id: string;
  child_name: string;
  class_name: string | null;
  enrollment_status: string;
  meal_status: string;
  candidate_stage: string | null;
  current_stage: string | null;
  approved_stage: string | null;
  approved_serving_start: string | null;
};

type DiagnosisRow = {
  id: string;
  status: string;
  requested_at: string | null;
  received_at: string | null;
  doctor_name: string | null;
  medical_institution: string | null;
  diagnosis_content: string | null;
  elimination_targets: string[] | null;
  effective_from: string | null;
  effective_until: string | null;
  renewal_deadline: string | null;
  release_note: string | null;
  created_at: string;
};

export const MEAL_STAGE_LABELS: Record<string, string> = {
  late: "後期食",
  complete: "完了食",
  toddler: "幼児食",
};

const DIAGNOSIS_STATUS_LABELS: Record<string, string> = {
  requested: "提出依頼中",
  received: "原本受領済み",
  released: "解除済み",
  expired: "期限切れ",
};

function mealStatusBadgeClass(status: string): string {
  switch (status) {
    case "給食開始保留":
      return "bg-red-100 text-red-700";
    case "弁当持参":
      return "bg-amber-100 text-amber-700";
    case "共通除去食":
      return "bg-violet-100 text-violet-700";
    case "通常食":
      return "bg-emerald-100 text-emerald-700";
    default: // 給食提供前(正常な経過)
      return "bg-slate-100 text-slate-600";
  }
}

/// 給食段階・診断書の管理セクション(M6 Phase 5・227/228)。管理者以上。
/// システムは候補を出し、園が承認する(承認日と提供開始日を分ける・原則2日後=既定値)。
export function MealStatusSection({ officeId }: { officeId: string }) {
  const [rows, setRows] = useState<MealRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [approveTarget, setApproveTarget] = useState<MealRow | null>(null);
  const [diagnosisTarget, setDiagnosisTarget] = useState<MealRow | null>(null);

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    if (!officeId) return;
    const supabase = createClient();
    supabase.rpc("fetch_meal_status_for_office", { p_office_id: officeId }).then(({ data, error: err }) => {
      if (err) {
        setError(err.message.includes("not authorized") ? null : err.message);
        setRows([]);
        return;
      }
      setRows((data ?? []) as MealRow[]);
    });
  }, [officeId, reloadToken]);

  return (
    <section className="space-y-2">
      <h3 className="text-sm font-bold text-slate-700">給食状態・段階の承認(在籍児・入園予定児)</h3>
      <p className="text-xs text-slate-400">
        食材チェックと月齢から段階の候補を自動判定します。候補が出た園児は内容を確認のうえ承認してください(提供開始日は承認と分けて指定・原則2日後)。
        入園予定児も入園前の準備として表示されます。
      </p>
      {error && <p className="text-sm font-medium text-red-500">{error}</p>}
      <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
              <th className="px-4 py-3">園児</th>
              <th className="px-4 py-3">クラス</th>
              <th className="px-4 py-3">給食状態</th>
              <th className="px-4 py-3">候補</th>
              <th className="px-4 py-3">現在の段階</th>
              <th className="px-4 py-3">承認済み(開始日)</th>
              <th className="px-4 py-3" />
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr>
                <td colSpan={7} className="px-4 py-6 text-center text-slate-400">
                  在籍児がいません
                </td>
              </tr>
            )}
            {rows.map((r) => (
              <tr key={r.child_id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                <td className="px-4 py-3 font-medium text-slate-800">
                  {r.child_name}
                  {r.enrollment_status === "入園予定" && (
                    <span className="ml-2 rounded-full bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-700">
                      入園予定
                    </span>
                  )}
                </td>
                <td className="px-4 py-3 text-slate-500">{r.class_name ?? "—"}</td>
                <td className="px-4 py-3">
                  <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${mealStatusBadgeClass(r.meal_status)}`}>
                    {r.meal_status}
                  </span>
                </td>
                <td className="px-4 py-3">
                  {r.candidate_stage && r.candidate_stage !== r.current_stage ? (
                    <span className="rounded-full bg-sky-100 px-2 py-0.5 text-xs font-semibold text-sky-700">
                      {MEAL_STAGE_LABELS[r.candidate_stage]}候補
                    </span>
                  ) : (
                    <span className="text-slate-400">—</span>
                  )}
                </td>
                <td className="px-4 py-3 text-slate-500">
                  {r.current_stage ? MEAL_STAGE_LABELS[r.current_stage] : "—"}
                </td>
                <td className="px-4 py-3 text-slate-500">
                  {r.approved_stage
                    ? `${MEAL_STAGE_LABELS[r.approved_stage]}(${r.approved_serving_start})`
                    : "—"}
                </td>
                <td className="px-4 py-3 text-right">
                  <div className="flex justify-end gap-2">
                    <button
                      onClick={() => setApproveTarget(r)}
                      className={`rounded-lg px-3 py-1 text-xs font-medium ${
                        r.candidate_stage && r.candidate_stage !== r.current_stage
                          ? "bg-sky-600 text-white hover:bg-sky-700"
                          : "border border-slate-300 text-slate-600 hover:bg-slate-100"
                      }`}
                    >
                      段階承認
                    </button>
                    <button
                      onClick={() => setDiagnosisTarget(r)}
                      className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                    >
                      診断書
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {approveTarget && (
        <ApproveStageModal
          row={approveTarget}
          onClose={() => setApproveTarget(null)}
          onSaved={() => {
            setApproveTarget(null);
            reload();
          }}
        />
      )}
      {diagnosisTarget && (
        <DiagnosisModal
          row={diagnosisTarget}
          onClose={() => {
            setDiagnosisTarget(null);
            reload();
          }}
        />
      )}
    </section>
  );
}

function ApproveStageModal({ row, onClose, onSaved }: { row: MealRow; onClose: () => void; onSaved: () => void }) {
  // 原則2日後提供(本案§3-2)を既定値にする
  const defaultStart = new Date();
  defaultStart.setDate(defaultStart.getDate() + 2);
  const [stage, setStage] = useState(row.candidate_stage ?? "late");
  const [startDate, setStartDate] = useState(defaultStart.toISOString().slice(0, 10));
  const [note, setNote] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    setIsSaving(true);
    setError(null);
    const supabase = createClient();
    const { error: err } = await supabase.rpc("approve_meal_stage", {
      p_child_id: row.child_id,
      p_stage: stage,
      p_serving_start_date: startDate,
      p_note: note.trim() || null,
    });
    setIsSaving(false);
    if (err) {
      setError(err.message.includes("today or later") ? "提供開始日は本日以降を指定してください" : err.message);
      return;
    }
    onSaved();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-1 text-base font-bold text-slate-800">給食段階の承認</h2>
        <p className="mb-4 text-sm text-slate-600">
          {row.child_name}
          {row.candidate_stage && ` / 候補: ${MEAL_STAGE_LABELS[row.candidate_stage]}`}
        </p>
        <div className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">段階</label>
            <select
              value={stage}
              onChange={(e) => setStage(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="late">後期食</option>
              <option value="complete">完了食</option>
              <option value="toddler">幼児食</option>
            </select>
            {row.candidate_stage !== stage && (
              <p className="mt-1 text-xs font-medium text-amber-600">
                候補と異なる段階です。食材チェック・月齢の充足を確認のうえ承認してください。
              </p>
            )}
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">提供開始日</label>
            <input
              type="date"
              value={startDate}
              min={currentDate()}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">給食担当への確定連携後、原則2日後から提供開始(既定値)。</p>
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">メモ(任意)</label>
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          {error && <p className="text-sm font-medium text-red-500">{error}</p>}
          <div className="flex justify-end gap-3">
            <button
              onClick={onClose}
              className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
            >
              キャンセル
            </button>
            <button
              onClick={handleSave}
              disabled={isSaving}
              className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
            >
              {isSaving ? "処理中…" : "承認する"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function DiagnosisModal({ row, onClose }: { row: MealRow; onClose: () => void }) {
  const [diagnoses, setDiagnoses] = useState<DiagnosisRow[]>([]);
  const [reloadToken, setReloadToken] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [isActing, setIsActing] = useState(false);
  const [recordTarget, setRecordTarget] = useState<DiagnosisRow | null>(null);
  // 受領記録フォーム
  const [receivedAt, setReceivedAt] = useState(currentDate());
  const [doctorName, setDoctorName] = useState("");
  const [institution, setInstitution] = useState("");
  const [content, setContent] = useState("");
  const [targets, setTargets] = useState("");
  const [effectiveFrom, setEffectiveFrom] = useState(currentDate());
  const [renewalDeadline, setRenewalDeadline] = useState(() => {
    // 既定=原本確認日から1年(Q&A#7)
    const d = new Date();
    d.setFullYear(d.getFullYear() + 1);
    return d.toISOString().slice(0, 10);
  });

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_child_allergy_diagnoses", { p_child_id: row.child_id }).then(({ data, error: err }) => {
      if (!err) setDiagnoses((data ?? []) as DiagnosisRow[]);
    });
  }, [row.child_id, reloadToken]);

  async function createRequest() {
    setIsActing(true);
    setError(null);
    const supabase = createClient();
    const { error: err } = await supabase.rpc("create_allergy_diagnosis_request", { p_child_id: row.child_id });
    setIsActing(false);
    if (err) {
      setError(err.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function recordDiagnosis() {
    if (!recordTarget) return;
    if (!targets.trim()) {
      setError("除去対象を入力してください(複数は「・」区切り)");
      return;
    }
    setIsActing(true);
    setError(null);
    const supabase = createClient();
    const { error: err } = await supabase.rpc("record_allergy_diagnosis", {
      p_diagnosis_id: recordTarget.id,
      p_received_at: receivedAt,
      p_doctor_name: doctorName.trim() || null,
      p_medical_institution: institution.trim() || null,
      p_diagnosis_content: content.trim() || null,
      p_elimination_targets: targets.split(/[・,、]/).map((t) => t.trim()).filter(Boolean),
      p_effective_from: effectiveFrom,
      p_effective_until: null,
      p_renewal_deadline: renewalDeadline || null,
      p_document_path: null,
    });
    setIsActing(false);
    if (err) {
      setError(err.message);
      return;
    }
    setRecordTarget(null);
    setReloadToken((t) => t + 1);
  }

  async function release(diagnosisId: string) {
    const note = window.prompt("解除メモ(任意。例: 医師の診断により除去不要)") ?? "";
    setIsActing(true);
    setError(null);
    const supabase = createClient();
    const { error: err } = await supabase.rpc("release_allergy_diagnosis", {
      p_diagnosis_id: diagnosisId,
      p_note: note.trim() || null,
    });
    setIsActing(false);
    if (err) {
      setError(err.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4 py-8">
      <div className="flex max-h-full w-full max-w-2xl flex-col rounded-2xl bg-white shadow-lg">
        <div className="flex items-center justify-between border-b border-slate-200 px-6 py-4">
          <div>
            <h2 className="text-base font-bold text-slate-800">アレルギー診断書の管理</h2>
            <p className="text-xs text-slate-400">
              {row.child_name} / 原本の受領・確認をもって確定します(アップロードのみでは確定しません)
            </p>
          </div>
          <button onClick={onClose} className="rounded-lg px-3 py-1 text-sm text-slate-500 hover:bg-slate-100">
            閉じる
          </button>
        </div>

        <div className="flex-1 space-y-3 overflow-y-auto px-6 py-4">
          {error && <p className="text-sm font-medium text-red-500">{error}</p>}
          <button
            onClick={createRequest}
            disabled={isActing}
            className="rounded-lg border border-sky-300 px-3 py-1.5 text-xs font-semibold text-sky-700 hover:bg-sky-50 disabled:opacity-50"
          >
            + 診断書の提出を依頼する(依頼中は給食状態が「弁当持参」になります)
          </button>

          {diagnoses.length === 0 && <p className="text-sm text-slate-400">診断書の記録はありません</p>}
          {diagnoses.map((d) => (
            <div key={d.id} className="rounded-xl border border-slate-200 p-3">
              <div className="flex items-center justify-between">
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                    d.status === "received"
                      ? "bg-violet-100 text-violet-700"
                      : d.status === "requested"
                        ? "bg-amber-100 text-amber-700"
                        : "bg-slate-100 text-slate-500"
                  }`}
                >
                  {DIAGNOSIS_STATUS_LABELS[d.status] ?? d.status}
                </span>
                <div className="flex gap-2">
                  {d.status === "requested" && (
                    <button
                      onClick={() => setRecordTarget(d)}
                      className="rounded-lg bg-sky-600 px-3 py-1 text-xs font-semibold text-white hover:bg-sky-700"
                    >
                      原本受領を記録
                    </button>
                  )}
                  {d.status === "received" && (
                    <button
                      onClick={() => release(d.id)}
                      className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                    >
                      解除する
                    </button>
                  )}
                </div>
              </div>
              <p className="mt-1 text-xs text-slate-500">
                {d.requested_at && `依頼: ${d.requested_at} `}
                {d.received_at && `/ 受領: ${d.received_at} `}
                {d.renewal_deadline && `/ 更新期限: ${d.renewal_deadline}`}
              </p>
              {d.elimination_targets && d.elimination_targets.length > 0 && (
                <p className="mt-0.5 text-sm text-slate-700">除去対象: {d.elimination_targets.join("・")}</p>
              )}
              {d.diagnosis_content && <p className="mt-0.5 text-xs text-slate-500">{d.diagnosis_content}</p>}
              {d.doctor_name && (
                <p className="mt-0.5 text-xs text-slate-400">
                  {d.medical_institution} {d.doctor_name}
                </p>
              )}
              {d.release_note && <p className="mt-0.5 text-xs text-slate-400">解除メモ: {d.release_note}</p>}
            </div>
          ))}

          {recordTarget && (
            <div className="rounded-xl border border-sky-200 bg-sky-50/50 p-4">
              <p className="mb-2 text-sm font-bold text-slate-700">原本受領の記録</p>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="mb-0.5 block text-xs font-medium text-slate-500">原本受領日</label>
                  <input type="date" value={receivedAt} onChange={(e) => setReceivedAt(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
                </div>
                <div>
                  <label className="mb-0.5 block text-xs font-medium text-slate-500">除去対象(・区切り) *</label>
                  <input value={targets} onChange={(e) => setTargets(e.target.value)} placeholder="例: 卵・乳"
                    className="w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
                </div>
                <div>
                  <label className="mb-0.5 block text-xs font-medium text-slate-500">医療機関</label>
                  <input value={institution} onChange={(e) => setInstitution(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
                </div>
                <div>
                  <label className="mb-0.5 block text-xs font-medium text-slate-500">医師名</label>
                  <input value={doctorName} onChange={(e) => setDoctorName(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
                </div>
                <div>
                  <label className="mb-0.5 block text-xs font-medium text-slate-500">適用開始日</label>
                  <input type="date" value={effectiveFrom} onChange={(e) => setEffectiveFrom(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
                </div>
                <div>
                  <label className="mb-0.5 block text-xs font-medium text-slate-500">更新期限(既定=1年後)</label>
                  <input type="date" value={renewalDeadline} onChange={(e) => setRenewalDeadline(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
                </div>
                <div className="col-span-2">
                  <label className="mb-0.5 block text-xs font-medium text-slate-500">診断内容</label>
                  <textarea rows={2} value={content} onChange={(e) => setContent(e.target.value)}
                    className="w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
                </div>
              </div>
              <div className="mt-3 flex justify-end gap-3">
                <button onClick={() => setRecordTarget(null)}
                  className="rounded-lg border border-slate-300 px-4 py-1.5 text-sm font-medium text-slate-600 hover:bg-slate-50">
                  キャンセル
                </button>
                <button onClick={recordDiagnosis} disabled={isActing}
                  className="rounded-lg bg-sky-600 px-4 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60">
                  {isActing ? "記録中…" : "受領を記録する"}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
