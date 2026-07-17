"use client";

import { useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { currentDate } from "@/lib/datetime";
import { watermarkImage } from "@/lib/imageWatermark";
import type { ChildcareClass, ChildcareOffice, ClassDailyPhoto } from "@/lib/types";

const STATUS_LABELS: Record<ClassDailyPhoto["status"], string> = {
  draft: "未チェック",
  checked: "チェック済み(未公開)",
  published: "公開済み",
};

export default function ChildcareClassPhotosPage() {
  const [offices, setOffices] = useState<ChildcareOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [selectedOffice, setSelectedOffice] = useState<string>("");
  const [isManager, setIsManager] = useState(false);

  const [classes, setClasses] = useState<ChildcareClass[]>([]);
  const [selectedClass, setSelectedClass] = useState<string>("");
  const [businessDate, setBusinessDate] = useState(currentDate());

  const [photos, setPhotos] = useState<ClassDailyPhoto[]>([]);
  const [signedUrls, setSignedUrls] = useState<Record<string, string>>({});
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [isUploading, setIsUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

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
    if (!selectedOffice) return;
    const supabase = createClient();
    supabase.rpc("fetch_childcare_classes", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (error) {
        setRowsError(error.message);
        return;
      }
      const list = (data ?? []) as ChildcareClass[];
      setClasses(list);
      setSelectedClass(list.length > 0 ? list[0].class_id : "");
    });
  }, [selectedOffice]);

  useEffect(() => {
    function loadRows() {
      if (!selectedClass) return null;
      setIsLoading(true);
      setRowsError(null);
      return createClient();
    }

    const supabase = loadRows();
    if (!supabase) return;
    supabase
      .from("class_daily_photos")
      .select("id, class_id, business_date, storage_path, status, checked_at, published_at, created_at")
      .eq("class_id", selectedClass)
      .eq("business_date", businessDate)
      .order("created_at", { ascending: false })
      .then(async ({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        const rows = (data ?? []) as ClassDailyPhoto[];
        setPhotos(rows);

        const urls: Record<string, string> = {};
        for (const photo of rows) {
          const { data: signed } = await supabase.storage
            .from("class-photos")
            .createSignedUrl(photo.storage_path, 300);
          if (signed) urls[photo.id] = signed.signedUrl;
        }
        setSignedUrls(urls);
      });
  }, [selectedClass, businessDate, reloadToken]);

  async function handleFileSelected(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file || !selectedClass) return;
    setIsUploading(true);
    setRowsError(null);
    try {
      const watermarked = await watermarkImage(file);
      const path = `${selectedClass}/${businessDate}/${crypto.randomUUID()}.jpg`;
      const supabase = createClient();
      const { error: uploadError } = await supabase.storage
        .from("class-photos")
        .upload(path, watermarked, { contentType: "image/jpeg" });
      if (uploadError) throw uploadError;

      const { data: userData } = await supabase.auth.getUser();
      const { data: employee } = await supabase
        .from("employees")
        .select("id")
        .eq("auth_user_id", userData.user?.id)
        .maybeSingle();

      const { error: insertError } = await supabase.from("class_daily_photos").insert({
        class_id: selectedClass,
        business_date: businessDate,
        storage_path: path,
        uploaded_by: employee?.id,
      });
      if (insertError) throw insertError;

      setReloadToken((t) => t + 1);
    } catch (e) {
      setRowsError(e instanceof Error ? e.message : "アップロードに失敗しました");
    } finally {
      setIsUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  async function check(photo: ClassDailyPhoto) {
    const supabase = createClient();
    const { error } = await supabase.rpc("check_class_daily_photo", { p_photo_id: photo.id });
    if (error) {
      setRowsError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function publish(photo: ClassDailyPhoto) {
    const supabase = createClient();
    const { error } = await supabase.rpc("publish_class_daily_photo", { p_photo_id: photo.id });
    if (error) {
      setRowsError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
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
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">クラス写真の管理</h2>
        <p className="text-xs text-slate-400">
          アップロード時にブラウザ内でクレジット透かしを合成してから保存します(元画像は送信されません)。
          公開前に「掲載不可の園児が写っていないか」を目視でご確認ください。
        </p>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => {
                setSelectedOffice(e.target.value);
                setIsManager(offices?.find((o) => o.office_id === e.target.value)?.is_manager ?? false);
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
            <label className="mb-1 block text-xs font-medium text-slate-500">クラス</label>
            <select
              value={selectedClass}
              onChange={(e) => setSelectedClass(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
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
          <div>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              onChange={handleFileSelected}
              disabled={isUploading || !selectedClass}
              className="hidden"
              id="class-photo-upload"
            />
            <label
              htmlFor="class-photo-upload"
              className="cursor-pointer rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
            >
              {isUploading ? "アップロード中…" : "写真をアップロード"}
            </label>
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}
          {!isLoading && photos.length === 0 && (
            <p className="text-sm text-slate-400">この日の写真はまだありません</p>
          )}
          {photos.map((photo) => (
            <div key={photo.id} className="space-y-3 rounded-2xl bg-white p-4 shadow-sm">
              {signedUrls[photo.id] ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={signedUrls[photo.id]}
                  alt="クラス写真"
                  className="aspect-square w-full rounded-xl object-cover"
                />
              ) : (
                <div className="aspect-square w-full rounded-xl bg-slate-100" />
              )}
              <span
                className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${
                  photo.status === "published"
                    ? "bg-emerald-50 text-emerald-700"
                    : photo.status === "checked"
                      ? "bg-sky-50 text-sky-700"
                      : "bg-slate-100 text-slate-500"
                }`}
              >
                {STATUS_LABELS[photo.status]}
              </span>
              {isManager && photo.status === "draft" && (
                <button
                  onClick={() => check(photo)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100"
                >
                  チェック済みにする
                </button>
              )}
              {isManager && photo.status === "checked" && (
                <button
                  onClick={() => publish(photo)}
                  className="w-full rounded-lg bg-emerald-600 px-3 py-2 text-xs font-semibold text-white hover:bg-emerald-700"
                >
                  公開する
                </button>
              )}
            </div>
          ))}
        </div>
      </main>
    </div>
  );
}
