"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

type Photo = {
  id: string;
  storage_path: string;
  caption: string | null;
  status: string;
  rejected_reason: string | null;
  uploaded_by_name: string | null;
  approved_by_name: string | null;
  approved_at: string | null;
  created_at: string;
};

function todayStr(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

const STATUS_LABEL: Record<string, { label: string; cls: string }> = {
  pending: { label: "承認待ち", cls: "bg-amber-100 text-amber-700" },
  published: { label: "公開中", cls: "bg-emerald-100 text-emerald-700" },
  rejected: { label: "差し戻し", cls: "bg-red-100 text-red-700" },
};

function MealPhotosContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const [businessDate, setBusinessDate] = useState(todayStr());
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [urls, setUrls] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [caption, setCaption] = useState("");

  // データ取得は meal-board と同じ inline .then パターン(effect内の同期setStateを避ける)。
  useEffect(() => {
    if (!selectedOffice) return;
    const s = createClient();
    void s
      .rpc("fetch_meal_photos_for_office", { p_office_id: selectedOffice, p_business_date: businessDate })
      .then(async ({ data, error }) => {
        if (error) {
          setErr(error.message);
          setPhotos([]);
          return;
        }
        setErr(null);
        const list = (data ?? []) as Photo[];
        setPhotos(list);
        const map: Record<string, string> = {};
        for (const p of list) {
          const { data: signed } = await s.storage.from("meal-photos").createSignedUrl(p.storage_path, 300);
          if (signed?.signedUrl) map[p.storage_path] = signed.signedUrl;
        }
        setUrls(map);
      });
  }, [selectedOffice, businessDate, reloadToken]);

  async function approve(id: string) {
    setBusy(true);
    const { error } = await createClient().rpc("approve_meal_photo", { p_id: id });
    setBusy(false);
    if (error) return setErr(error.message);
    setReloadToken((t) => t + 1);
  }
  async function reject(id: string) {
    const reason = window.prompt("差し戻し理由(必須)");
    if (reason == null || reason.trim() === "") return;
    setBusy(true);
    const { error } = await createClient().rpc("reject_meal_photo", { p_id: id, p_reason: reason.trim() });
    setBusy(false);
    if (error) return setErr(error.message);
    setReloadToken((t) => t + 1);
  }
  async function remove(id: string) {
    if (!window.confirm("この写真を削除しますか?")) return;
    setBusy(true);
    const { error } = await createClient().rpc("delete_meal_photo", { p_id: id });
    setBusy(false);
    if (error) return setErr(error.message);
    setReloadToken((t) => t + 1);
  }
  // 撮影/選択した画像を meal-photos バケットへアップロード → 承認待ちで登録(submit_meal_photo)。
  async function upload(file: File) {
    if (!selectedOffice) return;
    setBusy(true);
    setErr(null);
    try {
      const s = createClient();
      const ext = (file.name.split(".").pop() || "jpg").toLowerCase();
      const path = `${selectedOffice}/${businessDate}/${Date.now()}-${Math.floor(Math.random() * 1e6)}.${ext}`;
      const { error: upErr } = await s.storage.from("meal-photos").upload(path, file, { contentType: file.type || "image/jpeg", upsert: false });
      if (upErr) { setErr(upErr.message); return; }
      const { error } = await s.rpc("submit_meal_photo", { p_office_id: selectedOffice, p_business_date: businessDate, p_storage_path: path, p_caption: caption.trim() || null });
      if (error) { setErr(error.message); return; }
      setCaption("");
      setReloadToken((t) => t + 1);
    } finally {
      setBusy(false);
    }
  }

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
      <MealSubNav />
      <main className="flex-1 space-y-5 p-6">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-slate-800">給食写真の承認</h2>
          <input
            type="date"
            value={businessDate}
            onChange={(e) => setBusinessDate(e.target.value)}
            className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm"
          />
        </div>
        <p className="text-sm text-slate-500">
          厨房から送られた「本日の給食」写真を確認し、承認で保護者アプリに公開します。承認・差し戻しは管理者以上のみ可能です。
        </p>

        {/* 写真の追加(iPadで撮影 or 保存済み画像をアップロード)。送信すると承認待ちになる。 */}
        <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
          <div className="mb-2 text-sm font-bold text-slate-700">写真を追加(対象日: {businessDate})</div>
          <div className="flex flex-wrap items-center gap-3">
            <input value={caption} onChange={(e) => setCaption(e.target.value)} placeholder="一言メモ(任意)"
              className="min-w-[200px] flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm" />
            <label className={`cursor-pointer rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 ${busy ? "opacity-50" : ""}`}>
              📷 写真を撮る
              <input type="file" accept="image/*" capture="environment" className="hidden" disabled={busy}
                onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
            </label>
            <label className={`cursor-pointer rounded-lg border border-emerald-400 px-4 py-2 text-sm font-semibold text-emerald-700 hover:bg-emerald-50 ${busy ? "opacity-50" : ""}`}>
              ⬆️ アップロードする
              <input type="file" accept="image/*" className="hidden" disabled={busy}
                onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
            </label>
          </div>
          <p className="mt-1 text-xs text-slate-400">「写真を撮る」はiPadのカメラを起動、「アップロードする」は保存済みの画像を選べます。複数枚・過去日(日付を変更)も追加でき、下に履歴として並びます。</p>
        </div>
        {err && <div className="rounded-lg bg-red-50 px-4 py-2 text-sm text-red-600">{err}</div>}
        {photos.length === 0 ? (
          <div className="rounded-lg border border-slate-200 p-8 text-center text-sm text-slate-400">
            この日の給食写真はありません。
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4">
            {photos.map((p) => {
              const st = STATUS_LABEL[p.status] ?? STATUS_LABEL.pending;
              return (
                <div key={p.id} className="overflow-hidden rounded-xl border border-slate-200 bg-white">
                  <div className="relative aspect-square bg-slate-100">
                    {urls[p.storage_path] ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={urls[p.storage_path]} alt={p.caption ?? "給食写真"} className="h-full w-full object-cover" />
                    ) : (
                      <div className="flex h-full items-center justify-center text-slate-300">読み込み中…</div>
                    )}
                    <span className={`absolute left-2 top-2 rounded-full px-2 py-0.5 text-xs font-semibold ${st.cls}`}>
                      {st.label}
                    </span>
                  </div>
                  <div className="space-y-1 p-2">
                    {p.caption && <div className="truncate text-sm font-medium text-slate-700">{p.caption}</div>}
                    <div className="truncate text-xs text-slate-400">
                      撮影: {p.uploaded_by_name ?? "—"}
                      {p.approved_by_name ? ` / 承認: ${p.approved_by_name}` : ""}
                    </div>
                    {p.status === "rejected" && p.rejected_reason && (
                      <div className="truncate text-xs text-red-500">理由: {p.rejected_reason}</div>
                    )}
                    <div className="flex flex-wrap gap-1 pt-1">
                      {p.status !== "published" && (
                        <button
                          disabled={busy}
                          onClick={() => void approve(p.id)}
                          className="rounded-lg bg-emerald-600 px-2 py-1 text-xs font-semibold text-white hover:bg-emerald-700 disabled:opacity-50"
                        >
                          承認
                        </button>
                      )}
                      {p.status === "pending" && (
                        <button
                          disabled={busy}
                          onClick={() => void reject(p.id)}
                          className="rounded-lg border border-amber-300 px-2 py-1 text-xs font-medium text-amber-700 hover:bg-amber-50 disabled:opacity-50"
                        >
                          差し戻し
                        </button>
                      )}
                      <button
                        disabled={busy}
                        onClick={() => void remove(p.id)}
                        className="rounded-lg border border-slate-300 px-2 py-1 text-xs text-slate-500 hover:bg-slate-50 disabled:opacity-50"
                      >
                        削除
                      </button>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>
    </div>
  );
}

export default function ChildcareMealPhotosPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-500">読み込み中…</div>}>
      <MealPhotosContent />
    </Suspense>
  );
}
