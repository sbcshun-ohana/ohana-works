"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { currentDate } from "@/lib/datetime";

// 給食管理 Phase 6(前半)= 献立・食育レターのアップロード+版管理+公開(非AI退避構成)。
// migration 264。AI解析(日別構造化)は後半で追加。ここではファイルをアップロード→一覧→公開する。

type MenuRow = {
  id: string;
  target_month: string;
  format: string;
  source_path: string;
  source_filename: string | null;
  status: string;
  version: number;
  note: string | null;
  uploaded_by_name: string | null;
  published_at: string | null;
  created_at: string;
};

type LetterRow = {
  id: string;
  target_month: string;
  source_path: string;
  source_filename: string | null;
  status: string;
  version: number;
  uploaded_by_name: string | null;
  published_at: string | null;
  created_at: string;
};

const STATUS_LABEL: Record<string, string> = { draft: "下書き", published: "公開中", superseded: "旧版" };

function currentMonth(): string {
  // Asia/Tokyo の当月(YYYY-MM)。currentDate() は YYYY-MM-DD(東京)を返す。
  return currentDate().slice(0, 7);
}

function detectFormat(file: File): "excel" | "pdf" | "image" | null {
  const n = file.name.toLowerCase();
  if (n.endsWith(".xlsx") || n.endsWith(".xls")) return "excel";
  if (n.endsWith(".pdf")) return "pdf";
  if (/\.(png|jpe?g|heic|webp)$/.test(n)) return "image";
  return null;
}

function ChildcareMenusPageContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;
  const [month, setMonth] = useState(currentMonth());
  const [menuRows, setMenuRows] = useState<MenuRow[]>([]);
  const [letterRows, setLetterRows] = useState<LetterRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const menuInputRef = useRef<HTMLInputElement>(null);
  const letterInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!selectedOffice) return;
    let cancelled = false;
    void (async () => {
      const supabase = createClient();
      const monthStart = `${month}-01`;
      const [{ data: m, error: mErr }, { data: l, error: lErr }] = await Promise.all([
        supabase.rpc("fetch_menu_imports", { p_office_id: selectedOffice, p_target_month: monthStart }),
        supabase.rpc("fetch_nutrition_letters", { p_office_id: selectedOffice, p_target_month: monthStart }),
      ]);
      if (cancelled) return;
      if (mErr || lErr) setError(mErr?.message ?? lErr?.message ?? null);
      else setError(null);
      setMenuRows((m ?? []) as MenuRow[]);
      setLetterRows((l ?? []) as LetterRow[]);
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedOffice, month, reloadToken]);

  async function uploadMenu(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file || !selectedOffice) return;
    const format = detectFormat(file);
    if (!format) {
      setError("対応形式は Excel(.xlsx/.xls)・PDF・画像です");
      if (menuInputRef.current) menuInputRef.current.value = "";
      return;
    }
    setUploading(true);
    setError(null);
    try {
      const supabase = createClient();
      const path = `${selectedOffice}/${month}/${crypto.randomUUID()}-${file.name}`;
      const { error: upErr } = await supabase.storage.from("meal-menus").upload(path, file, {
        contentType: file.type || undefined,
      });
      if (upErr) throw upErr;
      const { error: rpcErr } = await supabase.rpc("create_menu_import", {
        p_office_id: selectedOffice,
        p_target_month: `${month}-01`,
        p_format: format,
        p_source_path: path,
        p_source_filename: file.name,
      });
      if (rpcErr) throw rpcErr;
      setReloadToken((t) => t + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : "アップロードに失敗しました");
    } finally {
      setUploading(false);
      if (menuInputRef.current) menuInputRef.current.value = "";
    }
  }

  async function uploadLetter(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file || !selectedOffice) return;
    setUploading(true);
    setError(null);
    try {
      const supabase = createClient();
      const path = `${selectedOffice}/${month}/letter-${crypto.randomUUID()}-${file.name}`;
      const { error: upErr } = await supabase.storage.from("meal-menus").upload(path, file, {
        contentType: file.type || undefined,
      });
      if (upErr) throw upErr;
      const { error: rpcErr } = await supabase.rpc("create_nutrition_letter", {
        p_office_id: selectedOffice,
        p_target_month: `${month}-01`,
        p_source_path: path,
        p_source_filename: file.name,
      });
      if (rpcErr) throw rpcErr;
      setReloadToken((t) => t + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : "アップロードに失敗しました");
    } finally {
      setUploading(false);
      if (letterInputRef.current) letterInputRef.current.value = "";
    }
  }

  async function runRpc(fn: string, id: string) {
    const supabase = createClient();
    const { error: rpcErr } = await supabase.rpc(fn, { p_id: id });
    if (rpcErr) setError(rpcErr.message);
    else setReloadToken((t) => t + 1);
  }

  async function viewFile(path: string) {
    const supabase = createClient();
    const { data, error: sErr } = await supabase.storage.from("meal-menus").createSignedUrl(path, 300);
    if (sErr || !data) {
      setError(sErr?.message ?? "ファイルを開けませんでした");
      return;
    }
    window.open(data.signedUrl, "_blank", "noopener");
  }

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <MealSubNav />
      <main className="flex-1 space-y-6 p-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-bold text-slate-800">献立・食育レター</h2>
          <div>
            <label className="mr-2 text-xs font-medium text-slate-500">対象月</label>
            <input
              type="month"
              value={month}
              onChange={(e) => setMonth(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
        </div>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}
        {!isManager && (
          <p className="rounded-lg bg-amber-50 p-3 text-sm text-amber-700">
            アップロード・公開・削除は主任以上のみ可能です(閲覧は可能)。
          </p>
        )}

        {/* 献立 */}
        <section className="space-y-3 rounded-2xl bg-white p-4 shadow-sm">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h3 className="text-base font-bold text-slate-800">献立表</h3>
            {isManager && (
              <label className="cursor-pointer rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700">
                {uploading ? "アップロード中…" : "献立をアップロード"}
                <input
                  ref={menuInputRef}
                  type="file"
                  accept=".xlsx,.xls,.pdf,image/*"
                  onChange={uploadMenu}
                  disabled={uploading}
                  className="hidden"
                />
              </label>
            )}
          </div>
          <p className="text-xs text-slate-400">
            委託先/業者の献立ファイル(Excel・PDF・画像)を月次でアップロードし、公開すると保護者アプリの給食セクションに表示されます。
          </p>
          <MenuTable
            rows={menuRows}
            isManager={isManager}
            onView={viewFile}
            onPublish={(id) => runRpc("publish_menu_import", id)}
            onDelete={(id) => runRpc("delete_menu_import", id)}
          />
        </section>

        {/* 食育レター */}
        <section className="space-y-3 rounded-2xl bg-white p-4 shadow-sm">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h3 className="text-base font-bold text-slate-800">食育レター</h3>
            {isManager && (
              <label className="cursor-pointer rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700">
                {uploading ? "アップロード中…" : "食育レターをアップロード"}
                <input
                  ref={letterInputRef}
                  type="file"
                  accept=".pdf,image/*"
                  onChange={uploadLetter}
                  disabled={uploading}
                  className="hidden"
                />
              </label>
            )}
          </div>
          <LetterTable
            rows={letterRows}
            isManager={isManager}
            onView={viewFile}
            onPublish={(id) => runRpc("publish_nutrition_letter", id)}
            onDelete={(id) => runRpc("delete_nutrition_letter", id)}
          />
        </section>
      </main>
    </div>
  );
}

function StatusChip({ status }: { status: string }) {
  const cls =
    status === "published"
      ? "bg-emerald-50 text-emerald-700"
      : status === "superseded"
        ? "bg-slate-100 text-slate-400"
        : "bg-amber-50 text-amber-700";
  return <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${cls}`}>{STATUS_LABEL[status] ?? status}</span>;
}

function MenuTable({
  rows,
  isManager,
  onView,
  onPublish,
  onDelete,
}: {
  rows: MenuRow[];
  isManager: boolean;
  onView: (path: string) => void;
  onPublish: (id: string) => void;
  onDelete: (id: string) => void;
}) {
  if (rows.length === 0) return <p className="text-sm text-slate-400">この月の献立はまだありません。</p>;
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead>
          <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
            <th className="px-3 py-2">版</th>
            <th className="px-3 py-2">ファイル</th>
            <th className="px-3 py-2">形式</th>
            <th className="px-3 py-2">状態</th>
            <th className="px-3 py-2">アップロード者</th>
            <th className="px-3 py-2">操作</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id} className="border-b border-slate-100 last:border-0 odd:bg-slate-50/60">
              <td className="px-3 py-2 text-slate-600">v{r.version}</td>
              <td className="px-3 py-2 font-medium text-slate-800">{r.source_filename ?? "—"}</td>
              <td className="px-3 py-2 text-slate-500">{r.format}</td>
              <td className="px-3 py-2">
                <StatusChip status={r.status} />
              </td>
              <td className="px-3 py-2 text-slate-500">{r.uploaded_by_name ?? "—"}</td>
              <td className="px-3 py-2">
                <div className="flex gap-2">
                  <button onClick={() => onView(r.source_path)} className="text-sky-600 hover:underline">
                    表示
                  </button>
                  {isManager && r.status !== "published" && (
                    <button onClick={() => onPublish(r.id)} className="text-emerald-600 hover:underline">
                      公開
                    </button>
                  )}
                  {isManager && (
                    <button onClick={() => onDelete(r.id)} className="text-red-500 hover:underline">
                      削除
                    </button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function LetterTable({
  rows,
  isManager,
  onView,
  onPublish,
  onDelete,
}: {
  rows: LetterRow[];
  isManager: boolean;
  onView: (path: string) => void;
  onPublish: (id: string) => void;
  onDelete: (id: string) => void;
}) {
  if (rows.length === 0) return <p className="text-sm text-slate-400">この月の食育レターはまだありません。</p>;
  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-sm">
        <thead>
          <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
            <th className="px-3 py-2">版</th>
            <th className="px-3 py-2">ファイル</th>
            <th className="px-3 py-2">状態</th>
            <th className="px-3 py-2">アップロード者</th>
            <th className="px-3 py-2">操作</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id} className="border-b border-slate-100 last:border-0 odd:bg-slate-50/60">
              <td className="px-3 py-2 text-slate-600">v{r.version}</td>
              <td className="px-3 py-2 font-medium text-slate-800">{r.source_filename ?? "—"}</td>
              <td className="px-3 py-2">
                <StatusChip status={r.status} />
              </td>
              <td className="px-3 py-2 text-slate-500">{r.uploaded_by_name ?? "—"}</td>
              <td className="px-3 py-2">
                <div className="flex gap-2">
                  <button onClick={() => onView(r.source_path)} className="text-sky-600 hover:underline">
                    表示
                  </button>
                  {isManager && r.status !== "published" && (
                    <button onClick={() => onPublish(r.id)} className="text-emerald-600 hover:underline">
                      公開
                    </button>
                  )}
                  {isManager && (
                    <button onClick={() => onDelete(r.id)} className="text-red-500 hover:underline">
                      削除
                    </button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function ChildcareMenusPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-400">読み込み中…</div>}>
      <ChildcareMenusPageContent />
    </Suspense>
  );
}
