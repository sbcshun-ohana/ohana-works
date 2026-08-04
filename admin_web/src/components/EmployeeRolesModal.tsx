"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { friendlyEmployeeError } from "@/lib/employeeErrors";

type Role = { code: string; name: string; sort_order: number };
type CurrentRole = { role_code: string; office_id: string | null };

/**
 * 役職の付与/剥奪(assign/remove_employee_role・統括園長/system_adminのみ)。
 * 付与プルダウンには操作者が付与できる役職(sort_order > 自分の最小sort_order)のみ表示する。
 */
export function EmployeeRolesModal({
  employeeId,
  employeeName,
  offices,
  minSortOrder,
  onClose,
}: {
  employeeId: string;
  employeeName: string;
  offices: { id: string; name: string }[];
  minSortOrder: number;
  onClose: () => void;
}) {
  const [roles, setRoles] = useState<Role[]>([]);
  const [current, setCurrent] = useState<CurrentRole[]>([]);
  const [addCode, setAddCode] = useState("");
  const [addOffice, setAddOffice] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    function load() {
      const supabase = createClient();
      supabase.from("roles").select("code, name, sort_order").order("sort_order").then(({ data }) => setRoles((data ?? []) as Role[]));
      supabase.rpc("fetch_employee_roles", { p_employee_id: employeeId }).then(({ data }) => setCurrent((data ?? []) as CurrentRole[]));
    }
    load();
  }, [employeeId, reload]);

  // 操作者が付与できる役職のみ(自分の最小sort_orderより厳密に下位)。
  const assignable = roles.filter((r) => r.sort_order > minSortOrder);
  const roleName = (code: string) => roles.find((r) => r.code === code)?.name ?? code;
  const officeName = (id: string | null) => (id ? offices.find((o) => o.id === id)?.name ?? "—" : "全施設");
  const canRemove = (code: string) => {
    const so = roles.find((r) => r.code === code)?.sort_order ?? -1;
    return so > minSortOrder;
  };

  async function add() {
    setError(null);
    if (!addCode) return;
    const { error: e } = await createClient().rpc("assign_employee_role", {
      p_employee_id: employeeId,
      p_role_code: addCode,
      p_office_id: addOffice || null,
    });
    if (e) {
      setError(friendlyEmployeeError(e.message));
      return;
    }
    setAddCode("");
    setAddOffice("");
    setReload((t) => t + 1);
  }

  async function remove(code: string, officeId: string | null) {
    setError(null);
    const { error: e } = await createClient().rpc("remove_employee_role", {
      p_employee_id: employeeId,
      p_role_code: code,
      p_office_id: officeId,
    });
    if (e) {
      setError(friendlyEmployeeError(e.message));
      return;
    }
    setReload((t) => t + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">役職 — {employeeName}</h3>
        <p className="mt-1 text-xs text-slate-500">付与できる役職は、あなたの権限より下位のもののみ表示されます。</p>

        <div className="mt-4">
          <h4 className="text-sm font-semibold text-slate-600">現在の役職</h4>
          <ul className="mt-2 space-y-1">
            {current.length === 0 && <li className="text-xs text-slate-400">役職がありません。</li>}
            {current.map((c, i) => (
              <li key={`${c.role_code}-${c.office_id ?? "all"}-${i}`} className="flex items-center justify-between rounded-lg bg-slate-50 px-3 py-2 text-sm">
                <span>
                  {roleName(c.role_code)} <span className="text-xs text-slate-400">({officeName(c.office_id)})</span>
                </span>
                {canRemove(c.role_code) ? (
                  <button onClick={() => remove(c.role_code, c.office_id)} className="rounded border border-red-300 px-2 py-0.5 text-xs text-red-600 hover:bg-red-50">
                    剥奪
                  </button>
                ) : (
                  <span className="text-xs text-slate-300">操作不可</span>
                )}
              </li>
            ))}
          </ul>
        </div>

        <div className="mt-5 rounded-xl border border-slate-200 p-3">
          <h4 className="text-sm font-semibold text-slate-600">役職を付与</h4>
          <div className="mt-2 flex flex-wrap items-end gap-2">
            <select value={addCode} onChange={(e) => setAddCode(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">役職</option>
              {assignable.map((r) => (
                <option key={r.code} value={r.code}>{r.name}</option>
              ))}
            </select>
            <select value={addOffice} onChange={(e) => setAddOffice(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
              <option value="">全施設</option>
              {offices.map((o) => (
                <option key={o.id} value={o.id}>{o.name}</option>
              ))}
            </select>
            <button onClick={add} className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600">付与</button>
          </div>
          {assignable.length === 0 && <p className="mt-2 text-xs text-slate-400">付与できる役職がありません。</p>}
        </div>

        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}

        <div className="mt-6 flex justify-end">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">閉じる</button>
        </div>
      </div>
    </div>
  );
}
