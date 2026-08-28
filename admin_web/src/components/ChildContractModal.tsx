"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { ChildMasterRow } from "@/lib/types";

// 園児契約モーダル(請求Phase3・389/390)。契約・月極延長=主任以上/免除・年齢スナップショット=統括のみ
// (免除セクションはRPCが統括以外に返さないため自動的に非表示)。
// 月は「月初日」で表現(input type=month の値 + "-01")。変更予約=閉じて作る・予約のみ削除可。

type ContractRow = {
  id: string;
  contract_plan_id: string;
  plan_name: string;
  cert_type: string | null;
  age_band: string | null;
  usage_start: string;
  usage_end: string;
  start_month: string;
  end_month: string | null;
  note: string | null;
  created_by_name: string | null;
  is_future: boolean;
};

type ExtensionRow = {
  id: string;
  monthly_extension_plan_id: string;
  plan_name: string;
  coverage_end: string;
  start_month: string;
  end_month: string | null;
  note: string | null;
  is_future: boolean;
};

type ExemptionRow = {
  id: string;
  kind: string;
  start_month: string;
  end_month: string | null;
  document_state: string;
  document_fiscal_year: number | null;
  has_document: boolean;
  document_path: string | null;
  document_confirmed_by_name: string | null;
  document_confirmed_at: string | null;
  note: string | null;
};

type SnapshotRow = {
  fiscal_year: number;
  age_band: string;
  basis_class_name: string | null;
  determined_at: string;
};

type PlanOption = {
  id: string;
  name: string;
  cert_type: string | null;
  age_band: string | null;
  usage_start: string;
  usage_end: string;
};

type ExtensionPlanOption = { id: string; name: string; coverage_end: string };

type BillingContracts = {
  can_edit_exemptions: boolean;
  contracts: ContractRow[];
  extension_contracts: ExtensionRow[];
  exemptions: ExemptionRow[];
  age_band_snapshots: SnapshotRow[];
  available_plans: PlanOption[];
  available_extension_plans: ExtensionPlanOption[];
};

const KIND_LABELS: Record<string, string> = {
  free_childcare: "無償化(保育料)",
  meal_main: "主食費免除",
  meal_side: "副食費免除",
  company_paid: "会社負担(職員の子)",
  custom: "個別免除",
};

const DOC_STATE_LABELS: Record<string, string> = {
  not_required: "書類不要",
  pending: "書類確認待ち",
  confirmed: "確認済み",
  deficient: "不備あり",
};

function hhmm(t: string | null): string {
  return t ? t.slice(0, 5) : "";
}

function ym(d: string | null): string {
  return d ? d.slice(0, 7) : "";
}

// 現在の年度(4月始まり)。免除フォームの年度初期値に使う(俊要望 2026-08-28: ゼロから手打ちさせない)
function currentFiscalYear(): number {
  const d = new Date();
  return d.getMonth() + 1 >= 4 ? d.getFullYear() : d.getFullYear() - 1;
}

function certLabel(cert: string | null, ageBand: string | null): string {
  if (cert === "standard") return "標準時間認定";
  if (cert === "short") return "短時間認定";
  if (ageBand === "age0") return "0歳児";
  if (ageBand === "age1_2") return "1-2歳児";
  return "";
}

type Props = {
  row: ChildMasterRow;
  officeId: string;
  onClose: () => void;
};

export function ChildContractModal({ row, officeId, onClose }: Props) {
  const [data, setData] = useState<BillingContracts | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [actionError, setActionError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // 契約追加フォーム
  const [showAddContract, setShowAddContract] = useState(false);
  const [addPlanId, setAddPlanId] = useState("");
  const [addMonth, setAddMonth] = useState("");
  const [addNote, setAddNote] = useState("");
  // 月極延長追加フォーム
  const [showAddExt, setShowAddExt] = useState(false);
  const [extPlanId, setExtPlanId] = useState("");
  const [extMonth, setExtMonth] = useState("");
  // 免除追加フォーム
  const [showAddEx, setShowAddEx] = useState(false);
  const [exKind, setExKind] = useState("free_childcare");
  const [exStart, setExStart] = useState("");
  const [exEnd, setExEnd] = useState("");
  const [exState, setExState] = useState("not_required");
  const [exFy, setExFy] = useState("");
  const [exNote, setExNote] = useState("");
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [uploadTarget, setUploadTarget] = useState<ExemptionRow | null>(null);
  // 終了月エディタ(俊要望 2026-08-28: 手打ちでなく月ピッカーで選択)
  const [endEdit, setEndEdit] = useState<{ kind: "contract" | "extension"; id: string; planName: string; startMonth: string } | null>(null);
  const [endMonth, setEndMonth] = useState("");

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    let alive = true;
    createClient()
      .rpc("fetch_child_billing_contracts", { p_child_id: row.child_id })
      .then(({ data: d, error }) => {
        if (!alive) return;
        if (error) {
          setLoadError(
            error.message.includes("feature disabled")
              ? "この施設は請求管理が無効です"
              : error.message.includes("not authorized")
                ? "契約情報は主任以上のみ閲覧できます"
                : error.message,
          );
          return;
        }
        setData(d as BillingContracts);
      });
    return () => {
      alive = false;
    };
  }, [row.child_id, reloadToken]);

  async function run(fn: () => PromiseLike<{ error: { message: string } | null }>) {
    setBusy(true);
    setActionError(null);
    const { error } = await fn();
    setBusy(false);
    if (error) {
      setActionError(error.message);
      return false;
    }
    reload();
    return true;
  }

  async function handleAddContract() {
    if (!addPlanId || !addMonth) {
      setActionError("プランと開始月を選択してください");
      return;
    }
    const ok = await run(() =>
      createClient().rpc("add_child_contract", {
        p_child_id: row.child_id,
        p_contract_plan_id: addPlanId,
        p_start_month: `${addMonth}-01`,
        p_note: addNote.trim() || null,
      }),
    );
    if (ok) {
      setShowAddContract(false);
      setAddPlanId("");
      setAddMonth("");
      setAddNote("");
    }
  }

  function openEndEdit(kind: "contract" | "extension", id: string, planName: string, startMonth: string, current: string | null) {
    setEndEdit({ kind, id, planName, startMonth });
    setEndMonth(current ? ym(current) : "");
    setActionError(null);
  }

  async function handleEndSave(clear: boolean) {
    if (!endEdit) return;
    const rpcName = endEdit.kind === "contract" ? "set_child_contract_end" : "set_child_extension_end";
    const ok = await run(() =>
      createClient().rpc(rpcName, {
        p_contract_id: endEdit.id,
        p_end_month: clear || !endMonth ? null : `${endMonth}-01`,
      }),
    );
    if (ok) setEndEdit(null);
  }

  async function handleDeleteFuture(c: ContractRow) {
    if (!window.confirm(`予約「${c.plan_name}(${ym(c.start_month)}〜)」を取り消しますか?`)) return;
    await run(() => createClient().rpc("delete_future_child_contract", { p_contract_id: c.id }));
  }

  async function handleAddExt() {
    if (!extPlanId || !extMonth) {
      setActionError("プランと開始月を選択してください");
      return;
    }
    const ok = await run(() =>
      createClient().rpc("add_child_extension_contract", {
        p_child_id: row.child_id,
        p_monthly_extension_plan_id: extPlanId,
        p_start_month: `${extMonth}-01`,
        p_note: null,
      }),
    );
    if (ok) {
      setShowAddExt(false);
      setExtPlanId("");
      setExtMonth("");
    }
  }

  async function handleDeleteFutureExt(c: ExtensionRow) {
    if (!window.confirm(`予約「${c.plan_name}(${ym(c.start_month)}〜)」を取り消しますか?`)) return;
    await run(() => createClient().rpc("delete_future_child_extension", { p_contract_id: c.id }));
  }

  async function handleAddExemption() {
    if (!exStart) {
      setActionError("開始月を入力してください");
      return;
    }
    const ok = await run(() =>
      createClient().rpc("upsert_child_exemption", {
        p_child_id: row.child_id,
        p_id: null,
        p_kind: exKind,
        p_start_month: `${exStart}-01`,
        p_end_month: exEnd ? `${exEnd}-01` : null,
        p_document_state: exState,
        p_document_fiscal_year: exFy ? Number(exFy) : null,
        p_note: exNote.trim() || null,
      }),
    );
    if (ok) {
      setShowAddEx(false);
      setExStart("");
      setExEnd("");
      setExNote("");
    }
  }

  async function handleDeleteExemption(x: ExemptionRow) {
    if (!window.confirm(`免除「${KIND_LABELS[x.kind] ?? x.kind}」を削除しますか?`)) return;
    await run(() => createClient().rpc("delete_child_exemption", { p_exemption_id: x.id }));
  }

  function startUpload(x: ExemptionRow) {
    setUploadTarget(x);
    fileInputRef.current?.click();
  }

  async function handleFileSelected(file: File | null) {
    const target = uploadTarget;
    setUploadTarget(null);
    if (!file || !target) return;
    if (file.type !== "application/pdf") {
      setActionError("PDFファイルを選択してください");
      return;
    }
    setBusy(true);
    setActionError(null);
    const supabase = createClient();
    const fy = target.document_fiscal_year ?? new Date().getFullYear();
    const path = `${row.child_id}/${fy}/${Date.now()}.pdf`;
    const { error: upErr } = await supabase.storage
      .from("exemption-documents")
      .upload(path, file, { contentType: "application/pdf" });
    if (upErr) {
      setBusy(false);
      setActionError(`アップロードに失敗しました(統括のみ): ${upErr.message}`);
      return;
    }
    const { error } = await supabase.rpc("set_exemption_document", {
      p_exemption_id: target.id,
      p_document_path: path,
      p_document_fiscal_year: fy,
      p_confirmed: false,
    });
    setBusy(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    reload();
  }

  async function handleConfirmDocument(x: ExemptionRow) {
    if (!x.document_path) return;
    if (!window.confirm("書類の内容を確認済みとして記録しますか?")) return;
    await run(() =>
      createClient().rpc("set_exemption_document", {
        p_exemption_id: x.id,
        p_document_path: x.document_path,
        p_document_fiscal_year: x.document_fiscal_year,
        p_confirmed: true,
      }),
    );
  }

  async function handleOpenDocument(x: ExemptionRow) {
    if (!x.document_path) return;
    const { data: signed, error } = await createClient()
      .storage.from("exemption-documents")
      .createSignedUrl(x.document_path, 300);
    if (error || !signed?.signedUrl) {
      setActionError(`書類を開けませんでした: ${error?.message ?? ""}`);
      return;
    }
    window.open(signed.signedUrl, "_blank");
  }

  async function handleGenerateSnapshots() {
    const fy = currentFiscalYear();
    if (!window.confirm(`${fy}年度の年齢区分を施設全体の在籍クラスから一括確定しますか?(再実行可)`)) return;
    setBusy(true);
    setActionError(null);
    const { data: count, error } = await createClient().rpc("generate_age_band_snapshots", {
      p_office_id: officeId,
      p_fiscal_year: fy,
    });
    setBusy(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    window.alert(`${count}名の年齢区分を確定しました`);
    reload();
  }

  const current = data?.contracts.find((c) => !c.is_future && (c.end_month === null || c.end_month >= new Date().toISOString().slice(0, 8) + "01"));

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-xl bg-white p-5 shadow-xl">
        <div className="flex items-center justify-between">
          <h3 className="text-base font-bold text-slate-800">契約: {row.display_name}</h3>
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-3 py-1 text-sm text-slate-600 hover:bg-slate-50">
            閉じる
          </button>
        </div>

        {loadError && <p className="mt-3 text-sm font-medium text-red-500">{loadError}</p>}
        {!data && !loadError && <p className="mt-3 text-sm text-slate-500">読み込み中…</p>}

        {data && (
          <div className="mt-4 space-y-5">
            {/* 契約プラン */}
            <section>
              <div className="flex items-center justify-between">
                <h4 className="text-sm font-bold text-slate-700">
                  契約プラン
                  {current && <span className="ml-2 rounded bg-emerald-50 px-1.5 py-0.5 text-xs font-semibold text-emerald-700">現在: {current.plan_name}</span>}
                  {!current && data.contracts.length === 0 && <span className="ml-2 rounded bg-amber-100 px-1.5 py-0.5 text-xs font-semibold text-amber-700">未契約</span>}
                </h4>
                <button
                  onClick={() => setShowAddContract((v) => !v)}
                  className="rounded-lg border border-sky-200 bg-sky-50 px-2.5 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-100"
                >
                  + 契約追加・変更
                </button>
              </div>
              {showAddContract && (
                <div className="mt-2 flex flex-wrap items-end gap-2 rounded-lg border border-sky-100 bg-sky-50/50 p-3">
                  <label className="text-xs text-slate-600">
                    プラン
                    <select value={addPlanId} onChange={(e) => setAddPlanId(e.target.value)}
                      className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                      <option value="">選択…</option>
                      {data.available_plans.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.name}({certLabel(p.cert_type, p.age_band)} {hhmm(p.usage_start)}〜{hhmm(p.usage_end)})
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="text-xs text-slate-600">
                    開始月
                    <input type="month" value={addMonth} onChange={(e) => setAddMonth(e.target.value)}
                      className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                  </label>
                  <label className="text-xs text-slate-600">
                    メモ
                    <input type="text" value={addNote} onChange={(e) => setAddNote(e.target.value)}
                      className="mt-0.5 block w-40 rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                  </label>
                  <button onClick={handleAddContract} disabled={busy}
                    className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60">
                    確定
                  </button>
                </div>
              )}
              <table className="mt-2 w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-slate-400">
                    <th className="py-1 pr-2 font-medium">プラン</th>
                    <th className="py-1 pr-2 font-medium">期間</th>
                    <th className="py-1 pr-2 font-medium">メモ</th>
                    <th className="py-1 text-right font-medium">操作</th>
                  </tr>
                </thead>
                <tbody>
                  {data.contracts.map((c) => (
                    <tr key={c.id} className="border-t border-slate-100">
                      <td className="py-1.5 pr-2 font-medium text-slate-700">
                        {c.plan_name}
                        <span className="ml-1 text-xs text-slate-400">{certLabel(c.cert_type, c.age_band)}</span>
                        {c.is_future && <span className="ml-1 rounded bg-violet-50 px-1 py-0.5 text-xs font-semibold text-violet-600">予約</span>}
                      </td>
                      <td className="py-1.5 pr-2 tabular-nums text-slate-600">
                        {ym(c.start_month)}〜{c.end_month ? ym(c.end_month) : ""}
                      </td>
                      <td className="py-1.5 pr-2 text-xs text-slate-500">{c.note ?? ""}</td>
                      <td className="py-1.5 text-right">
                        <div className="flex justify-end gap-1.5">
                          <button onClick={() => openEndEdit("contract", c.id, c.plan_name, c.start_month, c.end_month)} className="rounded border border-slate-200 px-2 py-0.5 text-xs text-slate-500 hover:bg-slate-50">終了月</button>
                          {c.is_future && (
                            <button onClick={() => handleDeleteFuture(c)} className="rounded border border-red-200 px-2 py-0.5 text-xs text-red-500 hover:bg-red-50">取消</button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                  {data.contracts.length === 0 && (
                    <tr><td colSpan={4} className="py-2 text-sm text-slate-400">契約履歴はまだありません</td></tr>
                  )}
                </tbody>
              </table>
            </section>

            {/* 月極延長(プランのある施設=大和のみ表示) */}
            {data.available_extension_plans.length > 0 && (
              <section>
                <div className="flex items-center justify-between">
                  <h4 className="text-sm font-bold text-slate-700">月極延長</h4>
                  <button onClick={() => setShowAddExt((v) => !v)}
                    className="rounded-lg border border-sky-200 bg-sky-50 px-2.5 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-100">
                    + 加入・変更
                  </button>
                </div>
                {showAddExt && (
                  <div className="mt-2 flex flex-wrap items-end gap-2 rounded-lg border border-sky-100 bg-sky-50/50 p-3">
                    <label className="text-xs text-slate-600">
                      プラン
                      <select value={extPlanId} onChange={(e) => setExtPlanId(e.target.value)}
                        className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                        <option value="">選択…</option>
                        {data.available_extension_plans.map((p) => (
                          <option key={p.id} value={p.id}>{p.name}(〜{hhmm(p.coverage_end)})</option>
                        ))}
                      </select>
                    </label>
                    <label className="text-xs text-slate-600">
                      開始月
                      <input type="month" value={extMonth} onChange={(e) => setExtMonth(e.target.value)}
                        className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                    </label>
                    <button onClick={handleAddExt} disabled={busy}
                      className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60">
                      確定
                    </button>
                  </div>
                )}
                <table className="mt-2 w-full text-sm">
                  <tbody>
                    {data.extension_contracts.map((c) => (
                      <tr key={c.id} className="border-t border-slate-100">
                        <td className="py-1.5 pr-2 font-medium text-slate-700">
                          {c.plan_name}
                          {c.is_future && <span className="ml-1 rounded bg-violet-50 px-1 py-0.5 text-xs font-semibold text-violet-600">予約</span>}
                        </td>
                        <td className="py-1.5 pr-2 tabular-nums text-slate-600">{ym(c.start_month)}〜{c.end_month ? ym(c.end_month) : ""}</td>
                        <td className="py-1.5 text-right">
                          <div className="flex justify-end gap-1.5">
                            <button onClick={() => openEndEdit("extension", c.id, c.plan_name, c.start_month, c.end_month)} className="rounded border border-slate-200 px-2 py-0.5 text-xs text-slate-500 hover:bg-slate-50">終了月</button>
                            {c.is_future && (
                              <button onClick={() => handleDeleteFutureExt(c)} className="rounded border border-red-200 px-2 py-0.5 text-xs text-red-500 hover:bg-red-50">取消</button>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                    {data.extension_contracts.length === 0 && (
                      <tr><td colSpan={3} className="py-2 text-sm text-slate-400">月極延長の加入はありません</td></tr>
                    )}
                  </tbody>
                </table>
              </section>
            )}

            {/* 免除(統括のみ表示・RPCが統括以外には返さない) */}
            {data.can_edit_exemptions && (
              <section>
                <div className="flex items-center justify-between">
                  <h4 className="text-sm font-bold text-slate-700">免除・無償化<span className="ml-2 text-xs font-normal text-slate-400">統括のみ</span></h4>
                  <button onClick={() => {
                      setShowAddEx((v) => !v);
                      if (!exFy) setExFy(String(currentFiscalYear()));
                    }}
                    className="rounded-lg border border-sky-200 bg-sky-50 px-2.5 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-100">
                    + 免除追加
                  </button>
                </div>
                {showAddEx && (
                  <div className="mt-2 flex flex-wrap items-end gap-2 rounded-lg border border-sky-100 bg-sky-50/50 p-3">
                    <label className="text-xs text-slate-600">
                      種別
                      <select value={exKind} onChange={(e) => setExKind(e.target.value)}
                        className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                        {Object.entries(KIND_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                      </select>
                    </label>
                    <label className="text-xs text-slate-600">
                      開始月
                      <input type="month" value={exStart} onChange={(e) => setExStart(e.target.value)}
                        className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                    </label>
                    <label className="text-xs text-slate-600">
                      終了月(任意)
                      <input type="month" value={exEnd} onChange={(e) => setExEnd(e.target.value)}
                        className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                    </label>
                    <label className="text-xs text-slate-600">
                      書類
                      <select value={exState} onChange={(e) => setExState(e.target.value)}
                        className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                        <option value="not_required">不要</option>
                        <option value="pending">確認待ち</option>
                        <option value="deficient">不備あり</option>
                      </select>
                    </label>
                    <label className="text-xs text-slate-600">
                      年度
                      <input type="number" value={exFy} onChange={(e) => setExFy(e.target.value)} placeholder="2026"
                        className="mt-0.5 block w-20 rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                    </label>
                    <label className="text-xs text-slate-600">
                      メモ
                      <input type="text" value={exNote} onChange={(e) => setExNote(e.target.value)}
                        className="mt-0.5 block w-32 rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                    </label>
                    <button onClick={handleAddExemption} disabled={busy}
                      className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60">
                      確定
                    </button>
                  </div>
                )}
                <table className="mt-2 w-full text-sm">
                  <tbody>
                    {data.exemptions.map((x) => (
                      <tr key={x.id} className="border-t border-slate-100">
                        <td className="py-1.5 pr-2 font-medium text-slate-700">{KIND_LABELS[x.kind] ?? x.kind}</td>
                        <td className="py-1.5 pr-2 tabular-nums text-slate-600">{ym(x.start_month)}〜{x.end_month ? ym(x.end_month) : ""}</td>
                        <td className="py-1.5 pr-2">
                          <span className={`rounded px-1.5 py-0.5 text-xs font-semibold ${
                            x.document_state === "confirmed" ? "bg-emerald-50 text-emerald-700"
                            : x.document_state === "pending" ? "bg-amber-100 text-amber-700"
                            : x.document_state === "deficient" ? "bg-red-100 text-red-600"
                            : "bg-slate-100 text-slate-500"}`}>
                            {DOC_STATE_LABELS[x.document_state] ?? x.document_state}
                            {x.document_fiscal_year ? `(${x.document_fiscal_year}年度)` : ""}
                          </span>
                        </td>
                        <td className="py-1.5 text-right">
                          <div className="flex justify-end gap-1.5">
                            {x.has_document ? (
                              <>
                                <button onClick={() => handleOpenDocument(x)} className="rounded border border-slate-200 px-2 py-0.5 text-xs text-slate-500 hover:bg-slate-50">書類を開く</button>
                                {x.document_state !== "confirmed" && (
                                  <button onClick={() => handleConfirmDocument(x)} className="rounded border border-emerald-200 px-2 py-0.5 text-xs text-emerald-600 hover:bg-emerald-50">確認済みに</button>
                                )}
                              </>
                            ) : (
                              <button onClick={() => startUpload(x)} className="rounded border border-slate-200 px-2 py-0.5 text-xs text-slate-500 hover:bg-slate-50">PDF添付</button>
                            )}
                            <button onClick={() => handleDeleteExemption(x)} className="rounded border border-red-200 px-2 py-0.5 text-xs text-red-500 hover:bg-red-50">削除</button>
                          </div>
                        </td>
                      </tr>
                    ))}
                    {data.exemptions.length === 0 && (
                      <tr><td colSpan={4} className="py-2 text-sm text-slate-400">免除はありません</td></tr>
                    )}
                  </tbody>
                </table>
              </section>
            )}

            {/* 年齢区分(企業主導型のみ意味を持つ。スナップショットが無く生成もできない場合は非表示) */}
            {(data.age_band_snapshots.length > 0 || data.can_edit_exemptions) && (
              <section>
                <div className="flex items-center justify-between">
                  <h4 className="text-sm font-bold text-slate-700">年齢区分(年度確定・クラス基準)</h4>
                  {data.can_edit_exemptions && (
                    <button onClick={handleGenerateSnapshots} disabled={busy}
                      className="rounded-lg border border-slate-300 px-2.5 py-1 text-xs font-semibold text-slate-600 hover:bg-slate-50 disabled:opacity-60">
                      今年度を施設一括確定
                    </button>
                  )}
                </div>
                <table className="mt-2 w-full text-sm">
                  <tbody>
                    {data.age_band_snapshots.map((s) => (
                      <tr key={s.fiscal_year} className="border-t border-slate-100">
                        <td className="py-1.5 pr-2 text-slate-600">{s.fiscal_year}年度</td>
                        <td className="py-1.5 pr-2 font-medium text-slate-700">{s.age_band === "age0" ? "0歳児" : "1-2歳児"}</td>
                        <td className="py-1.5 text-xs text-slate-400">基準クラス: {s.basis_class_name ?? ""}</td>
                      </tr>
                    ))}
                    {data.age_band_snapshots.length === 0 && (
                      <tr><td colSpan={3} className="py-2 text-sm text-slate-400">未確定(企業主導型のみ対象)</td></tr>
                    )}
                  </tbody>
                </table>
              </section>
            )}

            {actionError && <p className="text-sm font-medium text-red-500">{actionError}</p>}
          </div>
        )}

        {/* 終了月ピッカー(俊要望: 手打ちでなくカレンダー選択) */}
        {endEdit && (
          <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/30 p-4">
            <div className="w-full max-w-sm rounded-xl bg-white p-5 shadow-xl">
              <h4 className="text-sm font-bold text-slate-800">終了月の設定: {endEdit.planName}</h4>
              <p className="mt-1 text-xs text-slate-500">その月まで有効です(開始 {ym(endEdit.startMonth)})</p>
              <input
                type="month"
                value={endMonth}
                min={ym(endEdit.startMonth)}
                onChange={(e) => setEndMonth(e.target.value)}
                className="mt-3 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
              {actionError && <p className="mt-2 text-sm font-medium text-red-500">{actionError}</p>}
              <div className="mt-4 flex justify-between gap-2">
                <button onClick={() => handleEndSave(true)} disabled={busy}
                  className="rounded-lg border border-slate-300 px-3 py-2 text-sm text-slate-600 hover:bg-slate-50 disabled:opacity-60">
                  継続に戻す(終了月なし)
                </button>
                <div className="flex gap-2">
                  <button onClick={() => setEndEdit(null)}
                    className="rounded-lg border border-slate-300 px-3 py-2 text-sm text-slate-600 hover:bg-slate-50">
                    キャンセル
                  </button>
                  <button onClick={() => handleEndSave(false)} disabled={busy || !endMonth}
                    className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60">
                    確定
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        <input
          ref={fileInputRef}
          type="file"
          accept="application/pdf"
          className="hidden"
          onChange={(e) => {
            void handleFileSelected(e.target.files?.[0] ?? null);
            e.target.value = "";
          }}
        />
      </div>
    </div>
  );
}
