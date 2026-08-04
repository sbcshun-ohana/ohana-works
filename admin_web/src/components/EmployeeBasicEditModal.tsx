"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { friendlyEmployeeError } from "@/lib/employeeErrors";

type Row = {
  employee_id: string;
  name: string;
  name_kana: string | null;
  email: string | null;
  home_office_id: string | null;
};

/** 氏名・カナ・メール・所属の編集(update_employee_basic・労務 or 統括園長)。 */
export function EmployeeBasicEditModal({
  row,
  offices,
  onClose,
  onSaved,
}: {
  row: Row;
  offices: { id: string; name: string }[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState(row.name);
  const [kana, setKana] = useState(row.name_kana ?? "");
  const [email, setEmail] = useState(row.email ?? "");
  const [officeId, setOfficeId] = useState(row.home_office_id ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save() {
    setSaving(true);
    setError(null);
    const { error: e } = await createClient().rpc("update_employee_basic", {
      p_employee_id: row.employee_id,
      p_name: name,
      p_name_kana: kana || null,
      p_email: email || null,
      p_home_office_id: officeId || null,
    });
    setSaving(false);
    if (e) {
      setError(friendlyEmployeeError(e.message));
      return;
    }
    onSaved();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">基本情報の編集</h3>
        <div className="mt-4 space-y-3">
          <div>
            <label className="mb-1 block text-xs text-slate-500">氏名</label>
            <input value={name} onChange={(e) => setName(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">カナ</label>
            <input value={kana} onChange={(e) => setKana(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">メール</label>
            <input value={email} onChange={(e) => setEmail(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="mb-1 block text-xs text-slate-500">所属</label>
            <select value={officeId} onChange={(e) => setOfficeId(e.target.value)} className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">選択</option>
              {offices.map((o) => (
                <option key={o.id} value={o.id}>{o.name}</option>
              ))}
            </select>
          </div>
        </div>
        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}
        <div className="mt-6 flex justify-end gap-2">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">キャンセル</button>
          <button onClick={save} disabled={saving} className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-50">
            {saving ? "保存中…" : "保存"}
          </button>
        </div>
      </div>
    </div>
  );
}
