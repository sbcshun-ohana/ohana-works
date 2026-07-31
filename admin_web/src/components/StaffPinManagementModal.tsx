"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Props = {
  officeId: string;
  onClose: () => void;
};

type Row = {
  employee_id: string;
  name: string;
  has_pin: boolean;
  is_locked: boolean;
};

/// 要件3: 職員のPIN簡易ログインの管理(設定状況の確認・リセット)。
/// 権限判定は reset_staff_pin / fetch_staff_pin_status RPC(manages_office)側に従う。
export function StaffPinManagementModal({ officeId, onClose }: Props) {
  const [rows, setRows] = useState<Row[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    function load() {
      setIsLoading(true);
      setError(null);
      const supabase = createClient();
      Promise.all([
        supabase.rpc("fetch_childcare_office_staff", { p_office_id: officeId }),
        supabase.rpc("fetch_staff_pin_status", { p_office_id: officeId }),
      ]).then(([staffRes, statusRes]) => {
        setIsLoading(false);
        if (staffRes.error) {
          setError(staffRes.error.message);
          return;
        }
        const status = new Map<string, { has_pin: boolean; is_locked: boolean }>();
        for (const s of (statusRes.data ?? []) as { employee_id: string; has_pin: boolean; is_locked: boolean }[]) {
          status.set(s.employee_id, { has_pin: s.has_pin, is_locked: s.is_locked });
        }
        const merged = ((staffRes.data ?? []) as { employee_id: string; name: string }[]).map((s) => ({
          employee_id: s.employee_id,
          name: s.name,
          has_pin: status.get(s.employee_id)?.has_pin ?? false,
          is_locked: status.get(s.employee_id)?.is_locked ?? false,
        }));
        setRows(merged);
      });
    }
    load();
  }, [officeId, reloadToken]);

  async function resetPin(employeeId: string, name: string) {
    if (!window.confirm(`${name} さんのPINをリセットします。本人が次回メール+パスワードでログインして再設定する必要があります。よろしいですか?`)) {
      return;
    }
    const supabase = createClient();
    const { error } = await supabase.rpc("reset_staff_pin", { p_employee_id: employeeId });
    if (error) {
      setError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="max-h-[85vh] w-full max-w-xl overflow-y-auto rounded-2xl bg-white p-6 shadow-lg">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-base font-bold text-slate-800">職員のPINログイン管理</h2>
          <button onClick={onClose} className="text-sm text-slate-400 hover:text-slate-600">
            閉じる
          </button>
        </div>
        {error && <p className="mb-3 text-sm text-red-600">{error}</p>}
        {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}
        <table className="min-w-full text-sm">
          <thead>
            <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
              <th className="px-3 py-2">職員</th>
              <th className="px-3 py-2">PIN状態</th>
              <th className="px-3 py-2" />
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.employee_id} className="border-b border-slate-100 last:border-0">
                <td className="px-3 py-2 font-medium text-slate-800">{r.name}</td>
                <td className="px-3 py-2">
                  {r.is_locked ? (
                    <span className="rounded-full bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-600">ロック中</span>
                  ) : r.has_pin ? (
                    <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700">設定済み</span>
                  ) : (
                    <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">未設定</span>
                  )}
                </td>
                <td className="px-3 py-2 text-right">
                  {(r.has_pin || r.is_locked) && (
                    <button
                      onClick={() => resetPin(r.employee_id, r.name)}
                      className="rounded-lg border border-red-300 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50"
                    >
                      PINリセット
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {!isLoading && rows.length === 0 && (
              <tr>
                <td colSpan={3} className="px-3 py-6 text-center text-slate-400">
                  職員がいません
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
