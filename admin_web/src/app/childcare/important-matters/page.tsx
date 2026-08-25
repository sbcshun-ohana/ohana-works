"use client";

import { Fragment, Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

type Doc = {
  id: string;
  fiscal_year: number;
  title: string;
  storage_path: string;
  version: number;
  is_published: boolean;
  published_at: string;
  note: string | null;
  consented_count: number;
};
type ConsentRow = {
  child_id: string;
  child_name: string;
  class_name: string | null;
  consented: boolean;
  agreed_guardian_name: string | null;
  agreed_at: string | null;
};

function fmtDate(ts: string | null): string {
  if (!ts) return "—";
  const d = new Date(ts);
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`;
}

function ImportantMattersContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isAdmin = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false; // 一覧は主任以上、公開は管理者以上(RPCで判定)
  const now = new Date();
  const [fiscalYear, setFiscalYear] = useState(now.getMonth() + 1 >= 4 ? now.getFullYear() : now.getFullYear() - 1);
  const [title, setTitle] = useState("重要事項説明書");
  const [file, setFile] = useState<File | null>(null);
  const [note, setNote] = useState("");
  const [docs, setDocs] = useState<Doc[]>([]);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [statusRows, setStatusRows] = useState<ConsentRow[]>([]);

  useEffect(() => {
    if (!selectedOffice) return;
    createClient()
      .rpc("fetch_important_matters_documents", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        if (error) { setErr(error.message); setDocs([]); return; }
        setErr(null);
        setDocs((data ?? []) as Doc[]);
      });
  }, [selectedOffice, reloadToken]);

  async function publish() {
    if (!selectedOffice || !file) { setErr("PDFファイルを選択してください"); return; }
    setBusy(true);
    try {
      const s = createClient();
      const path = `${selectedOffice}/${fiscalYear}/${Date.now()}.pdf`;
      const { error: upErr } = await s.storage.from("important-matters").upload(path, file, { contentType: "application/pdf", upsert: false });
      if (upErr) { setErr(`アップロード失敗: ${upErr.message}`); return; }
      const { error } = await s.rpc("save_important_matters_document", {
        p_office_id: selectedOffice, p_fiscal_year: fiscalYear, p_title: title, p_storage_path: path, p_note: note || null,
      });
      if (error) { setErr(error.message); return; }
      setErr(null); setFile(null); setNote("");
      setReloadToken((t) => t + 1);
    } finally {
      setBusy(false);
    }
  }

  async function openPdf(path: string) {
    const { data } = await createClient().storage.from("important-matters").createSignedUrl(path, 300);
    if (data?.signedUrl) window.open(data.signedUrl, "_blank");
  }

  async function toggleStatus(id: string) {
    if (expandedId === id) { setExpandedId(null); return; }
    const { data, error } = await createClient().rpc("fetch_important_matters_consent_status", { p_document_id: id });
    if (error) { setErr(error.message); return; }
    setStatusRows((data ?? []) as ConsentRow[]);
    setExpandedId(id);
  }

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
      <main className="flex-1 space-y-5 p-6">
        <h2 className="text-lg font-bold text-slate-800">重要事項説明書</h2>
        {err && <div className="rounded-lg bg-red-50 px-4 py-2 text-sm text-red-600">{err}</div>}

        {/* 公開(管理者以上) */}
        <section className="space-y-3 rounded-2xl bg-white p-5 shadow-sm">
          <div className="text-sm font-bold text-slate-700">PDFを公開(管理者以上)</div>
          <p className="text-xs text-slate-400">保育安全計画を内包した年度版の重要事項説明書PDFをアップロードして公開します。保護者アプリに表示され、世帯単位で同意を受けます。</p>
          <div className="flex flex-wrap items-center gap-3">
            <label className="text-sm text-slate-600">年度
              <select value={fiscalYear} onChange={(e) => setFiscalYear(Number(e.target.value))} className="ml-2 rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                {[now.getFullYear() - 1, now.getFullYear(), now.getFullYear() + 1].map((y) => <option key={y} value={y}>{y}年度</option>)}
              </select>
            </label>
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="タイトル" className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
            <input type="file" accept="application/pdf" onChange={(e) => setFile(e.target.files?.[0] ?? null)} className="text-sm" />
          </div>
          <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="メモ(任意)" className="w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
          <button onClick={() => void publish()} disabled={busy || !file}
            className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50">
            {busy ? "公開中…" : "公開する"}
          </button>
        </section>

        {/* 一覧 */}
        <section className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-3 py-3">年度</th><th className="px-3 py-3">タイトル</th><th className="px-3 py-3">版</th>
                <th className="px-3 py-3">公開日</th><th className="px-3 py-3">同意世帯</th><th className="px-3 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {docs.length === 0 && <tr><td colSpan={6} className="px-3 py-6 text-center text-slate-400">公開済みの重要事項説明書はありません</td></tr>}
              {docs.map((d) => (
                <Fragment key={d.id}>
                  <tr className="border-b border-slate-100">
                    <td className="px-3 py-3 text-slate-600">{d.fiscal_year}年度</td>
                    <td className="px-3 py-3 font-medium text-slate-800">{d.title}</td>
                    <td className="px-3 py-3 text-slate-500">v{d.version}</td>
                    <td className="px-3 py-3 text-slate-500">{fmtDate(d.published_at)}</td>
                    <td className="px-3 py-3 text-slate-500">{d.consented_count}世帯</td>
                    <td className="px-3 py-3 text-right">
                      <div className="flex items-center justify-end gap-2">
                        <button onClick={() => void openPdf(d.storage_path)} className="rounded-lg border border-slate-300 px-3 py-1 text-xs text-slate-600 hover:bg-slate-50">PDF</button>
                        <button onClick={() => void toggleStatus(d.id)} className="rounded-lg border border-sky-300 px-3 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-50">
                          {expandedId === d.id ? "閉じる" : "同意状況"}
                        </button>
                      </div>
                    </td>
                  </tr>
                  {expandedId === d.id && (
                    <tr className="border-b border-slate-100 bg-slate-50/60">
                      <td colSpan={6} className="px-4 py-3">
                        <div className="grid gap-1 md:grid-cols-2">
                          {statusRows.map((r) => (
                            <div key={r.child_id} className="flex items-center gap-2 text-sm">
                              <span className={`inline-block h-2 w-2 rounded-full ${r.consented ? "bg-emerald-500" : "bg-red-400"}`} />
                              <span className="font-medium text-slate-700">{r.child_name}</span>
                              <span className="text-xs text-slate-400">{r.class_name ?? ""}</span>
                              <span className="ml-auto text-xs text-slate-500">
                                {r.consented ? `同意済 ${r.agreed_guardian_name ?? ""} ${fmtDate(r.agreed_at)}` : "未同意"}
                              </span>
                            </div>
                          ))}
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </section>
        {!isAdmin && <p className="text-xs text-slate-400">※ 公開は管理者以上のみ可能です。</p>}
      </main>
    </div>
  );
}

export default function ImportantMattersPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-500">読み込み中…</div>}>
      <ImportantMattersContent />
    </Suspense>
  );
}
