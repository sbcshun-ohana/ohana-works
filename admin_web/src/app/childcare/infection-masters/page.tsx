"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";

// 感染症マスター管理(205・設計指示書§4)。閲覧=職員(RLS)、登録・改訂・確認記録・様式PDF=統括園長以上
// (RLS/storageポリシーで強制。権限外の操作はサーバー側で拒否されエラー表示になる)。
// 改訂は「新版の行を追加+旧版を閉じる」方式(過去記録は当時の版で再現=AC-16)。

type RuleDefinition = {
  checks?: string[];
  date_condition?: { base_label?: string; min_hours?: number };
} | null;

type DiseaseRow = {
  id: string;
  name: string;
  category: string;
  requires_opinion_letter: boolean;
  requires_return_form: boolean;
  return_criteria: string | null;
  infectious_period: string | null;
  rule_definition: RuleDefinition;
  version: number;
  effective_from: string;
  effective_to: string | null;
  source_title: string | null;
  source_revision: string | null;
  confirmed_by_name: string | null;
  confirmed_at: string | null;
  sort_order: number | null;
  is_active: boolean;
};

// 様式PDF(137拡張)。v1はこの2種のみ扱う。
const FORM_TEMPLATES: { key: string; label: string }[] = [
  { key: "infection_return_notice_form", label: "登園届(保護者記入)様式" },
  { key: "infection_permission_form", label: "登園許可書(医師記入)様式" },
];

type TemplateRow = {
  id: string;
  template_key: string;
  version: number;
  effective_from: string;
  status: string;
  file_path: string | null;
};

function ChildcareInfectionMastersPageContent() {
  const [rows, setRows] = useState<DiseaseRow[]>([]);
  const [templates, setTemplates] = useState<TemplateRow[]>([]);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [editTarget, setEditTarget] = useState<DiseaseRow | null>(null);
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  function showToast(m: string) {
    setToast(m);
    window.setTimeout(() => setToast((c) => (c === m ? null : c)), 3500);
  }

  useEffect(() => {
    function load() {
      return createClient();
    }
    const supabase = load();
    supabase
      .from("infectious_disease_masters")
      .select("*")
      .is("office_id", null)
      .order("is_active", { ascending: false })
      .order("sort_order", { ascending: true, nullsFirst: false })
      .order("version", { ascending: false })
      .then(({ data, error }) => {
        if (error) {
          setRowsError(error.message);
          return;
        }
        setRows((data ?? []) as DiseaseRow[]);
      });
    supabase
      .from("document_templates")
      .select("id, template_key, version, effective_from, status, file_path")
      .in(
        "template_key",
        FORM_TEMPLATES.map((t) => t.key),
      )
      .order("version", { ascending: false })
      .then(({ data, error }) => {
        if (!error) setTemplates((data ?? []) as TemplateRow[]);
      });
  }, [reloadToken]);

  async function recordConfirmation(row: DiseaseRow) {
    const name = window.prompt("確認記録: 確認者名を入力してください(例: 大原統括園長に口頭確認・俊)");
    if (!name) return;
    const { error } = await createClient()
      .from("infectious_disease_masters")
      .update({ confirmed_by_name: name, confirmed_at: new Date().toISOString().slice(0, 10) })
      .eq("id", row.id);
    if (error) {
      showToast(`保存に失敗しました(統括園長以上のみ): ${error.message}`);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function uploadFormPdf(templateKey: string, label: string, file: File) {
    setBusy(true);
    const supabase = createClient();
    const current = templates.find((t) => t.template_key === templateKey);
    const nextVersion = (current?.version ?? 0) + 1;
    const path = `${templateKey}/v${nextVersion}.pdf`;
    const { error: upErr } = await supabase.storage
      .from("document-templates")
      .upload(path, file, { contentType: "application/pdf" });
    if (upErr) {
      setBusy(false);
      showToast(`アップロードに失敗しました(統括園長以上のみ): ${upErr.message}`);
      return;
    }
    // 旧版を superseded に落としてから新版を active で登録(AC-10: 新規案件には有効版のみ配布)
    if (current) {
      await supabase.from("document_templates").update({ status: "superseded" }).eq("id", current.id);
    }
    const today = new Date().toISOString().slice(0, 10);
    const { error: insErr } = await supabase.from("document_templates").insert({
      template_key: templateKey,
      document_type: "infection_form",
      version: nextVersion,
      effective_from: today,
      status: "active",
      source_file_name: file.name,
      file_path: path,
    });
    setBusy(false);
    if (insErr) {
      showToast(`様式の登録に失敗しました: ${insErr.message}`);
      return;
    }
    showToast(`${label} v${nextVersion} を登録しました`);
    setReloadToken((t) => t + 1);
  }

  async function openFormPdf(t: TemplateRow) {
    if (!t.file_path) return;
    const { data, error } = await createClient()
      .storage.from("document-templates")
      .createSignedUrl(t.file_path, 300);
    if (error) {
      showToast(`表示に失敗しました: ${error.message}`);
      return;
    }
    window.open(data.signedUrl, "_blank");
  }

  const activeRows = rows.filter((r) => r.is_active);
  const inactiveRows = rows.filter((r) => !r.is_active);

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-6 p-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-lg font-bold text-slate-800">感染症マスター</h2>
          <p className="text-xs text-slate-500">
            出典: {activeRows[0]?.source_title ?? "—"}({activeRows[0]?.source_revision ?? "—"})
            ・登録/改訂/確認記録は統括園長以上のみ
          </p>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}
        {toast && (
          <p className="rounded-lg bg-slate-800 px-4 py-2 text-sm font-medium text-white">{toast}</p>
        )}

        {/* 様式PDF(137拡張・document-templatesバケット) */}
        <div className="grid gap-4 md:grid-cols-2">
          {FORM_TEMPLATES.map((ft) => {
            const current = templates.find((t) => t.template_key === ft.key && t.status === "active");
            return (
              <div key={ft.key} className="rounded-2xl bg-white p-4 shadow-sm">
                <div className="flex items-center justify-between gap-2">
                  <div>
                    <p className="text-sm font-bold text-slate-700">{ft.label}</p>
                    <p className="text-xs text-slate-500">
                      {current
                        ? `現行 v${current.version}(${current.effective_from}〜)`
                        : "未登録(PDFをアップロードしてください)"}
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    {current?.file_path && (
                      <button
                        onClick={() => openFormPdf(current)}
                        className="rounded-lg border border-sky-300 px-3 py-1.5 text-xs font-medium text-sky-700 hover:bg-sky-50"
                      >
                        表示
                      </button>
                    )}
                    <label className="cursor-pointer rounded-lg bg-sky-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-sky-700">
                      {busy ? "処理中…" : current ? "新版をアップロード" : "アップロード"}
                      <input
                        type="file"
                        accept="application/pdf"
                        className="hidden"
                        disabled={busy}
                        onChange={(e) => {
                          const f = e.target.files?.[0];
                          if (f) uploadFormPdf(ft.key, ft.label, f);
                          e.target.value = "";
                        }}
                      />
                    </label>
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {/* 有効マスター一覧 */}
        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-3 py-3">感染症名</th>
                <th className="px-3 py-3">必要書類</th>
                <th className="px-3 py-3">登園のめやす</th>
                <th className="px-3 py-3">登園届の確認項目</th>
                <th className="px-3 py-3">版</th>
                <th className="px-3 py-3">確認記録</th>
                <th className="px-3 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {activeRows.map((r) => (
                <tr key={r.id} className="border-b border-slate-100 align-top last:border-0 hover:bg-slate-50">
                  <td className="px-3 py-3 font-medium whitespace-nowrap text-slate-800">{r.name}</td>
                  <td className="px-3 py-3 whitespace-nowrap">
                    {r.requires_opinion_letter ? (
                      <span className="rounded-full bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-600">
                        登園許可書(医師)
                      </span>
                    ) : r.requires_return_form ? (
                      <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800">
                        登園届(保護者)
                      </span>
                    ) : (
                      <span className="text-xs text-slate-400">—</span>
                    )}
                  </td>
                  <td className="max-w-md px-3 py-3 text-slate-600">{r.return_criteria ?? "—"}</td>
                  <td className="max-w-xs px-3 py-3 text-slate-600">
                    {r.rule_definition?.checks?.length ? (
                      <ul className="list-inside list-disc space-y-0.5 text-xs">
                        {r.rule_definition.checks.map((c, i) => (
                          <li key={i}>{c}</li>
                        ))}
                        {r.rule_definition.date_condition && (
                          <li className="font-semibold text-slate-700">
                            {r.rule_definition.date_condition.base_label}から
                            {r.rule_definition.date_condition.min_hours}時間経過
                          </li>
                        )}
                      </ul>
                    ) : (
                      <span className="text-xs text-slate-400">—</span>
                    )}
                  </td>
                  <td className="px-3 py-3 text-xs whitespace-nowrap text-slate-500">
                    v{r.version}
                    <br />
                    {r.effective_from}〜
                  </td>
                  <td className="px-3 py-3 text-xs whitespace-nowrap text-slate-600">
                    {r.confirmed_by_name ? (
                      <>
                        ✓ {r.confirmed_by_name}
                        <br />
                        {r.confirmed_at}
                      </>
                    ) : (
                      <button
                        onClick={() => recordConfirmation(r)}
                        className="rounded-lg border border-slate-300 px-2 py-1 text-xs text-slate-600 hover:bg-slate-50"
                      >
                        確認を記録
                      </button>
                    )}
                  </td>
                  <td className="px-3 py-3 whitespace-nowrap">
                    <button
                      onClick={() => setEditTarget(r)}
                      className="rounded-lg border border-sky-300 px-2 py-1 text-xs font-medium text-sky-700 hover:bg-sky-50"
                    >
                      改訂(新版)
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {inactiveRows.length > 0 && (
          <details className="rounded-2xl bg-white p-4 text-sm shadow-sm">
            <summary className="cursor-pointer font-medium text-slate-500">
              無効・旧版({inactiveRows.length}件)
            </summary>
            <ul className="mt-2 space-y-1 text-xs text-slate-500">
              {inactiveRows.map((r) => (
                <li key={r.id}>
                  {r.name} v{r.version}({r.effective_from}〜{r.effective_to ?? ""})
                </li>
              ))}
            </ul>
          </details>
        )}
      </main>

      {editTarget && (
        <ReviseDiseaseModal
          row={editTarget}
          onClose={() => setEditTarget(null)}
          onSaved={(m) => {
            showToast(m);
            setEditTarget(null);
            setReloadToken((t) => t + 1);
          }}
        />
      )}
    </div>
  );
}

// 改訂モーダル: 旧版を閉じて(effective_to=前日・is_active=false)、version+1 の新行を追加する。
function ReviseDiseaseModal({
  row,
  onClose,
  onSaved,
}: {
  row: DiseaseRow;
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const [criteria, setCriteria] = useState(row.return_criteria ?? "");
  const [period, setPeriod] = useState(row.infectious_period ?? "");
  const [docKind, setDocKind] = useState<"opinion" | "form">(
    row.requires_opinion_letter ? "opinion" : "form",
  );
  const [checksText, setChecksText] = useState((row.rule_definition?.checks ?? []).join("\n"));
  const [minHours, setMinHours] = useState(
    row.rule_definition?.date_condition?.min_hours?.toString() ?? "",
  );
  const [baseLabel, setBaseLabel] = useState(row.rule_definition?.date_condition?.base_label ?? "");
  const [sourceRevision, setSourceRevision] = useState(row.source_revision ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setSaving(true);
    setError(null);
    const supabase = createClient();
    const today = new Date();
    const yest = new Date(today.getTime() - 24 * 3600 * 1000);
    const d = (x: Date) => x.toISOString().slice(0, 10);

    const checks = checksText
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean);
    const rule =
      docKind === "form"
        ? {
            checks,
            ...(minHours
              ? { date_condition: { base_label: baseLabel || "基準日時", min_hours: Number(minHours) } }
              : {}),
          }
        : null;

    // 旧版を閉じる
    const { error: closeErr } = await supabase
      .from("infectious_disease_masters")
      .update({ is_active: false, effective_to: d(yest) })
      .eq("id", row.id);
    if (closeErr) {
      setSaving(false);
      setError(`旧版の更新に失敗しました(統括園長以上のみ): ${closeErr.message}`);
      return;
    }
    const { error: insErr } = await supabase.from("infectious_disease_masters").insert({
      office_id: null,
      name: row.name,
      category: row.category,
      requires_opinion_letter: docKind === "opinion",
      requires_return_form: docKind === "form",
      return_criteria: criteria || null,
      infectious_period: period || null,
      rule_definition: rule,
      version: row.version + 1,
      effective_from: d(today),
      source: "national",
      source_title: row.source_title,
      source_url: null,
      source_revision: sourceRevision || null,
      sort_order: row.sort_order,
      is_active: true,
    });
    setSaving(false);
    if (insErr) {
      setError(`新版の登録に失敗しました: ${insErr.message}`);
      return;
    }
    onSaved(`${row.name} を v${row.version + 1} に改訂しました`);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-black/30 p-4">
      <div className="w-full max-w-2xl space-y-4 rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">
          {row.name} の改訂(v{row.version} → v{row.version + 1})
        </h3>
        <p className="text-xs text-slate-500">
          保存すると旧版は無効化され(過去の提出記録は当時の版のまま再現されます)、新版が本日から有効になります。
        </p>

        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">必要書類</label>
          <div className="flex gap-4 text-sm">
            <label className="flex items-center gap-1">
              <input
                type="radio"
                checked={docKind === "opinion"}
                onChange={() => setDocKind("opinion")}
              />
              登園許可書(医師記入)
            </label>
            <label className="flex items-center gap-1">
              <input type="radio" checked={docKind === "form"} onChange={() => setDocKind("form")} />
              登園届(保護者記入)
            </label>
          </div>
        </div>

        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">登園のめやす</label>
          <textarea
            value={criteria}
            onChange={(e) => setCriteria(e.target.value)}
            rows={3}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>

        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">感染しやすい期間(参考)</label>
          <input
            value={period}
            onChange={(e) => setPeriod(e.target.value)}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>

        {docKind === "form" && (
          <>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">
                登園届の確認項目(1行に1項目)
              </label>
              <textarea
                value={checksText}
                onChange={(e) => setChecksText(e.target.value)}
                rows={4}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="mb-1 block text-xs font-medium text-slate-500">
                  日付条件の基準(任意・例: 抗菌薬の内服を開始した日時)
                </label>
                <input
                  value={baseLabel}
                  onChange={(e) => setBaseLabel(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
              <div className="w-40">
                <label className="mb-1 block text-xs font-medium text-slate-500">経過時間(時間)</label>
                <input
                  type="number"
                  value={minHours}
                  onChange={(e) => setMinHours(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
            </div>
          </>
        )}

        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">出典の改訂情報</label>
          <input
            value={sourceRevision}
            onChange={(e) => setSourceRevision(e.target.value)}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}

        <div className="flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm text-slate-600 hover:bg-slate-50"
          >
            キャンセル
          </button>
          <button
            onClick={save}
            disabled={saving}
            className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
          >
            {saving ? "保存中…" : "新版として保存"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function ChildcareInfectionMastersPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareInfectionMastersPageContent />
    </Suspense>
  );
}
