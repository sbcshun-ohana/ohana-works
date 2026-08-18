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
            <h3 className="text-sm font-bold text-slate-700">{className}</h3>
            <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
              <table className="w-full text-left text-sm">
                <thead className="bg-slate-50 text-xs text-slate-500">
                  <tr>
                    <th className="w-40 px-3 py-2">園児</th>
                    <th className="px-3 py-2">緊急連絡先(優先順)</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {kids.map((child) => {
                    const contacts = contactsByChild.get(child.child_id) ?? [];
                    return (
                      <tr key={child.child_id} className="align-top">
                        <td className="px-3 py-2 font-medium text-slate-800">
                          {child.display_name}
                          {child.honorific_suffix ?? ""}
                        </td>
                        <td className="px-3 py-2">
                          {contacts.length === 0 ? (
                            <span className="rounded-md bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-700">
                              未登録
                            </span>
                          ) : (
                            <div className="flex flex-col gap-1">
                              {contacts.map((c, i) => (
                                <div key={c.id} className="flex flex-wrap items-center gap-2">
                                  <span className="inline-flex h-5 w-5 items-center justify-center rounded-full bg-slate-100 text-xs font-bold text-slate-500">
                                    {i + 1}
                                  </span>
                                  <span className="font-medium text-slate-800">{c.name}</span>
                                  {c.relationship && (
                                    <span className="text-xs text-slate-400">({c.relationship})</span>
                                  )}
                                  <a
                                    href={`tel:${c.phone}`}
                                    className="font-semibold text-sky-700 hover:underline"
                                  >
                                    {c.phone}
                                  </a>
                                </div>
                              ))}
                            </div>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
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
