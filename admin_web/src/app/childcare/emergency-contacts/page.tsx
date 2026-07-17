"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import type { ChildForAssignment, ChildcareOffice, EmergencyContact } from "@/lib/types";

export default function ChildcareEmergencyContactsPage() {
  const [offices, setOffices] = useState<ChildcareOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [selectedOffice, setSelectedOffice] = useState<string>("");

  const [children, setChildren] = useState<ChildForAssignment[]>([]);
  const [selectedChildId, setSelectedChildId] = useState<string>("");
  const [contacts, setContacts] = useState<EmergencyContact[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [newName, setNewName] = useState("");
  const [newPhone, setNewPhone] = useState("");
  const [newRelationship, setNewRelationship] = useState("");
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_childcare_offices").then(({ data, error }) => {
      if (error) {
        setOfficesError(error.message);
        return;
      }
      const list = (data ?? []) as ChildcareOffice[];
      setOffices(list);
      if (list.length > 0) setSelectedOffice(list[0].office_id);
    });
  }, []);

  useEffect(() => {
    if (!selectedOffice) return;
    const supabase = createClient();
    supabase.rpc("fetch_children_for_office", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (error) {
        setRowsError(error.message);
        return;
      }
      const list = (data ?? []) as ChildForAssignment[];
      setChildren(list);
      setSelectedChildId(list.length > 0 ? list[0].child_id : "");
    });
  }, [selectedOffice]);

  useEffect(() => {
    function loadRows() {
      if (!selectedChildId) return null;
      setIsLoading(true);
      setRowsError(null);
      return createClient();
    }

    const supabase = loadRows();
    if (!supabase) return;
    supabase
      .from("guardian_emergency_contacts")
      .select("id, child_id, name, phone, relationship, sort_order, duplicate_approved_by, duplicate_approved_reason")
      .eq("child_id", selectedChildId)
      .order("sort_order")
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) {
          setRowsError(error.message);
          return;
        }
        setContacts((data ?? []) as EmergencyContact[]);
      });
  }, [selectedChildId, reloadToken]);

  async function addContact() {
    if (!newName.trim() || !newPhone.trim() || !selectedChildId) return;
    setIsSaving(true);
    setRowsError(null);
    const supabase = createClient();
    const { error } = await supabase.from("guardian_emergency_contacts").insert({
      child_id: selectedChildId,
      name: newName.trim(),
      phone: newPhone.trim(),
      relationship: newRelationship.trim() || null,
      sort_order: contacts.length,
    });
    setIsSaving(false);
    if (error) {
      setRowsError(error.message);
      return;
    }
    setNewName("");
    setNewPhone("");
    setNewRelationship("");
    setReloadToken((t) => t + 1);
  }

  async function removeContact(contact: EmergencyContact) {
    if (!window.confirm(`${contact.name}(${contact.phone})を削除しますか？`)) return;
    const supabase = createClient();
    const { error } = await supabase.from("guardian_emergency_contacts").delete().eq("id", contact.id);
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
        <h2 className="text-lg font-bold text-slate-800">緊急連絡先の管理</h2>
        <p className="text-xs text-slate-400">
          園児ごとに最低2件の登録を推奨します。きょうだい間で同じ連絡先を登録することは問題ありません。
        </p>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
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
            <label className="mb-1 block text-xs font-medium text-slate-500">園児</label>
            <select
              value={selectedChildId}
              onChange={(e) => setSelectedChildId(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {children.map((c) => (
                <option key={c.child_id} value={c.child_id}>
                  {c.display_name}
                  {c.honorific_suffix ?? ""}
                  {c.class_name ? `(${c.class_name})` : ""}
                </option>
              ))}
            </select>
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <div className="flex items-center justify-between">
            <h3 className="text-base font-bold text-slate-800">登録済みの連絡先</h3>
            {!isLoading && contacts.length < 2 && (
              <span className="rounded-full bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-700">
                現在{contacts.length}件(推奨2件以上)
              </span>
            )}
          </div>

          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">氏名</th>
                  <th className="px-4 py-3">電話番号</th>
                  <th className="px-4 py-3">続柄</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody>
                {isLoading && (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-center text-slate-400">
                      読み込み中…
                    </td>
                  </tr>
                )}
                {!isLoading && contacts.length === 0 && (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-center text-slate-400">
                      緊急連絡先が登録されていません
                    </td>
                  </tr>
                )}
                {!isLoading &&
                  contacts.map((c) => (
                    <tr key={c.id} className="border-b border-slate-100 last:border-0">
                      <td className="px-4 py-3 font-medium text-slate-800">{c.name}</td>
                      <td className="px-4 py-3 text-slate-500">{c.phone}</td>
                      <td className="px-4 py-3 text-slate-500">{c.relationship ?? "—"}</td>
                      <td className="px-4 py-3 text-right">
                        <button
                          onClick={() => removeContact(c)}
                          className="rounded-lg border border-red-300 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50"
                        >
                          削除
                        </button>
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>

          <div className="flex flex-wrap items-end gap-3 border-t border-slate-100 pt-4">
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">氏名</label>
              <input
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">電話番号</label>
              <input
                value={newPhone}
                onChange={(e) => setNewPhone(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">続柄(任意)</label>
              <input
                value={newRelationship}
                onChange={(e) => setNewRelationship(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
            <button
              onClick={addContact}
              disabled={isSaving || !newName.trim() || !newPhone.trim()}
              className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
            >
              {isSaving ? "追加中…" : "追加する"}
            </button>
          </div>
        </div>
      </main>
    </div>
  );
}
