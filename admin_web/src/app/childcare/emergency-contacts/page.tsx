"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { classOrderIndex } from "@/lib/childcareClassSort";
import type { ChildForAssignment, EmergencyContact } from "@/lib/types";
import { useChildcareClass } from "@/hooks/useChildcareClass";

/// 緊急連絡先 一覧(閲覧用・俊指示 2026-08-18)。
/// 保護者が基本情報/台帳で登録した緊急連絡先(guardian_emergency_contacts)を施設横断でまとめ、
/// 非常時に園児1人ずつ台帳を開かなくても確認できるようにする。登録・修正は各園児の台帳側で行う。
function ChildcareEmergencyContactsPageContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const { classes } = useChildcareClass(selectedOffice);

  const [children, setChildren] = useState<ChildForAssignment[]>([]);
  const [contactsByChild, setContactsByChild] = useState<Map<string, EmergencyContact[]>>(new Map());
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [search, setSearch] = useState("");

  useEffect(() => {
    if (!selectedOffice) return;
    setIsLoading(true);
    setRowsError(null);
    const supabase = createClient();
    supabase.rpc("fetch_children_for_office", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (error) {
        setRowsError(error.message);
        setIsLoading(false);
        return;
      }
      const list = (data ?? []) as ChildForAssignment[];
      setChildren(list);
      const ids = list.map((c) => c.child_id);
      if (ids.length === 0) {
        setContactsByChild(new Map());
        setIsLoading(false);
        return;
      }
      supabase
        .from("guardian_emergency_contacts")
        .select("id, child_id, name, phone, relationship, sort_order")
        .in("child_id", ids)
        .order("sort_order")
        .then(({ data: cData, error: cErr }) => {
          setIsLoading(false);
          if (cErr) {
            setRowsError(cErr.message);
            return;
          }
          const map = new Map<string, EmergencyContact[]>();
          for (const row of (cData ?? []) as EmergencyContact[]) {
            const arr = map.get(row.child_id) ?? [];
            arr.push(row);
            map.set(row.child_id, arr);
          }
          setContactsByChild(map);
        });
    });
  }, [selectedOffice]);

  const classOrder = useMemo(() => classOrderIndex(classes), [classes]);

  // クラス(年齢順)→ 園児名でグループ化。氏名検索でフィルタ。未所属は末尾。
  const groups = useMemo(() => {
    const kw = search.trim();
    const filtered = kw ? children.filter((c) => c.display_name.includes(kw)) : children;
    const sorted = filtered.slice().sort((a, b) => {
      const ai = a.class_name != null ? classOrder.get(a.class_name) ?? Number.MAX_SAFE_INTEGER : Number.MAX_SAFE_INTEGER;
      const bi = b.class_name != null ? classOrder.get(b.class_name) ?? Number.MAX_SAFE_INTEGER : Number.MAX_SAFE_INTEGER;
      if (ai !== bi) return ai - bi;
      return a.display_name.localeCompare(b.display_name, "ja");
    });
    const byClass = new Map<string, ChildForAssignment[]>();
    for (const c of sorted) {
      const key = c.class_name ?? "その他・未所属";
      const arr = byClass.get(key) ?? [];
      arr.push(c);
      byClass.set(key, arr);
    }
    return Array.from(byClass.entries());
  }, [children, search, classOrder]);

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
      <main className="flex-1 space-y-4 p-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-bold text-slate-800">緊急連絡先 一覧(非常時確認用)</h2>
            <p className="text-xs text-slate-400">
              保護者が基本情報・台帳で登録した緊急連絡先の一覧です。非常時にこの画面でまとめて確認できます。
              登録・修正は各園児の台帳(基本情報)で行います。番号はタップで発信できます。
            </p>
          </div>
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="氏名で検索"
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}
        {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}
        {!isLoading && groups.length === 0 && (
          <p className="rounded-xl bg-white p-4 text-sm text-slate-400 shadow-sm">該当する園児がいません。</p>
        )}

        {groups.map(([className, kids]) => (
          <section key={className} className="space-y-2">
            <h3 className="text-sm font-bold text-slate-700">
              {className}
              <span className="ml-2 text-xs font-normal text-slate-400">{kids.length}名</span>
            </h3>
            {/* 園児カードのグリッド。広い画面は2列、iPad縦/スマホは1列。 */}
            <div className="grid grid-cols-1 gap-3 xl:grid-cols-2">
              {kids.map((child) => {
                const contacts = contactsByChild.get(child.child_id) ?? [];
                // 最低3枠。登録がそれ以上なら全件表示。
                const slotCount = Math.max(3, contacts.length);
                const slots = Array.from({ length: slotCount }, (_, i) => contacts[i] ?? null);
                return (
                  <div key={child.child_id} className="rounded-2xl border border-slate-200 bg-white p-4">
                    <div className="mb-2 flex items-center justify-between gap-2">
                      <p className="text-base font-bold text-slate-800">
                        {child.display_name}
                        {child.honorific_suffix ?? ""}
                      </p>
                      <span
                        className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                          contacts.length >= 3
                            ? "bg-emerald-50 text-emerald-700"
                            : "bg-amber-50 text-amber-700"
                        }`}
                      >
                        {contacts.length}/3件
                      </span>
                    </div>
                    {/* 優先枠: 広い画面=横並び(左から1・2・3)、狭い画面=縦積み(上から1・2・3)。 */}
                    <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
                      {slots.map((c, i) => (
                        <div
                          key={c?.id ?? `empty-${i}`}
                          className={`rounded-xl border p-2.5 ${
                            c ? "border-slate-200 bg-slate-50" : "border-dashed border-slate-200 bg-white"
                          }`}
                        >
                          <div className="mb-1 flex items-center gap-1.5">
                            <span
                              className={`inline-flex h-5 w-5 items-center justify-center rounded-full text-xs font-bold ${
                                c ? "bg-sky-600 text-white" : "bg-slate-200 text-slate-400"
                              }`}
                            >
                              {i + 1}
                            </span>
                            <span className="text-xs font-medium text-slate-400">優先{i + 1}</span>
                          </div>
                          {c ? (
                            <>
                              <p className="text-sm font-semibold text-slate-800">
                                {c.name}
                                {c.relationship && (
                                  <span className="ml-1 text-xs font-normal text-slate-400">({c.relationship})</span>
                                )}
                              </p>
                              <a
                                href={`tel:${c.phone}`}
                                className="mt-0.5 block text-base font-bold text-sky-700 hover:underline"
                              >
                                {c.phone}
                              </a>
                            </>
                          ) : (
                            <p className="text-sm text-slate-300">未登録</p>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </section>
        ))}
      </main>
    </div>
  );
}

export default function ChildcareEmergencyContactsPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareEmergencyContactsPageContent />
    </Suspense>
  );
}
