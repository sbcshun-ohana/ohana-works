"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { friendlyEmployeeError } from "@/lib/employeeErrors";

type HomeroomRow = { class_id: string; class_name: string; employee_id: string | null; employee_name: string | null };
type OfficeOpt = { office_id: string; office_name: string };
type StaffOpt = { employee_id: string; name: string };

/** 担任(class_homeroom_assignments)の割当/解除。既存 set_class_homeroom(manages_childcare)をUI露出。 */
export function ClassHomeroomModal({ onClose }: { onClose: () => void }) {
  const [offices, setOffices] = useState<OfficeOpt[]>([]);
  const [officeId, setOfficeId] = useState("");
  const [rows, setRows] = useState<HomeroomRow[]>([]);
  const [staff, setStaff] = useState<StaffOpt[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    createClient()
      .rpc("fetch_my_childcare_offices")
      .then(({ data }) => {
        const list = (data ?? []) as OfficeOpt[];
        setOffices(list);
        if (list.length > 0) setOfficeId((p) => p || list[0].office_id);
      });
  }, []);

  useEffect(() => {
    if (!officeId) return;
    const supabase = createClient();
    supabase.rpc("fetch_class_homerooms", { p_office_id: officeId }).then(({ data }) => setRows((data ?? []) as HomeroomRow[]));
    supabase.rpc("fetch_childcare_office_staff", { p_office_id: officeId }).then(({ data }) => setStaff((data ?? []) as StaffOpt[]));
  }, [officeId, reload]);

  async function toggle(classId: string, employeeId: string, assign: boolean) {
    setError(null);
    const { error: e } = await createClient().rpc("set_class_homeroom", {
      p_class_id: classId,
      p_employee_id: employeeId,
      p_assign: assign,
    });
    if (e) {
      setError(friendlyEmployeeError(e.message));
      return;
    }
    setReload((t) => t + 1);
  }

  // クラスごとに担任をまとめる。
  const classes = new Map<string, { name: string; members: HomeroomRow[] }>();
  for (const r of rows) {
    const entry = classes.get(r.class_id) ?? { name: r.class_name, members: [] };
    if (r.employee_id) entry.members.push(r);
    classes.set(r.class_id, entry);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">担任管理</h3>
        <div className="mt-3">
          <label className="mb-1 block text-xs text-slate-500">施設</label>
          <select value={officeId} onChange={(e) => setOfficeId(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm">
            {offices.map((o) => (
              <option key={o.office_id} value={o.office_id}>{o.office_name}</option>
            ))}
          </select>
        </div>

        <div className="mt-4 max-h-96 space-y-3 overflow-y-auto">
          {Array.from(classes.entries()).map(([classId, c]) => (
            <div key={classId} className="rounded-xl border border-slate-200 p-3">
              <div className="text-sm font-semibold text-slate-700">{c.name}</div>
              <div className="mt-1 flex flex-wrap gap-1">
                {c.members.length === 0 && <span className="text-xs text-slate-400">担任なし</span>}
                {c.members.map((m) => (
                  <span key={m.employee_id} className="flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-xs text-emerald-700">
                    {m.employee_name}
                    <button onClick={() => toggle(classId, m.employee_id!, false)} className="text-emerald-500 hover:text-red-500">×</button>
                  </span>
                ))}
              </div>
              <div className="mt-2 flex gap-2">
                <select
                  className="flex-1 rounded-lg border border-slate-300 px-2 py-1 text-xs"
                  defaultValue=""
                  onChange={(e) => {
                    if (e.target.value) {
                      toggle(classId, e.target.value, true);
                      e.target.value = "";
                    }
                  }}
                >
                  <option value="">担任を追加…</option>
                  {staff
                    .filter((s) => !c.members.some((m) => m.employee_id === s.employee_id))
                    .map((s) => (
                      <option key={s.employee_id} value={s.employee_id}>{s.name}</option>
                    ))}
                </select>
              </div>
            </div>
          ))}
          {classes.size === 0 && <p className="text-xs text-slate-400">クラスがありません。</p>}
        </div>

        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}

        <div className="mt-6 flex justify-end">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">閉じる</button>
        </div>
      </div>
    </div>
  );
}
