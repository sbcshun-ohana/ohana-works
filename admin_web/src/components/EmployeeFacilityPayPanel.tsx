"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { EditFacilityWageModal } from "./EditFacilityWageModal";
import { EditFacilityAllowanceModal } from "./EditFacilityAllowanceModal";
import { EditFacilityCommuteModal } from "./EditFacilityCommuteModal";

type FacilityWage = {
  office_id: string;
  office_name: string;
  salary_type: "月給" | "時給";
  monthly_base_salary: number | null;
  hourly_wage: number | null;
  effective_start_date: string;
};

type FacilityAllowance = {
  office_id: string;
  office_name: string;
  allowance_master_id: string;
  allowance_name: string;
  amount: number;
  effective_start_date: string;
};

type FacilityCommute = {
  office_id: string;
  office_name: string;
  commute_method: string | null;
  unit_price: number;
  calc_type: string;
  taxable_limit: number | null;
  effective_start_date: string;
};

type Props = {
  employeeId: string;
  employeeName: string;
  onClose: () => void;
};

export function EmployeeFacilityPayPanel({ employeeId, employeeName, onClose }: Props) {
  const [wages, setWages] = useState<FacilityWage[]>([]);
  const [allowances, setAllowances] = useState<FacilityAllowance[]>([]);
  const [commutes, setCommutes] = useState<FacilityCommute[]>([]);
  const [homeOffice, setHomeOffice] = useState<{ office_id: string; office_name: string } | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [showWageModal, setShowWageModal] = useState(false);
  const [showAllowanceModal, setShowAllowanceModal] = useState(false);
  const [showCommuteModal, setShowCommuteModal] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    Promise.all([
      supabase.rpc("fetch_employee_facility_wages", { p_employee_id: employeeId }),
      supabase.rpc("fetch_employee_facility_allowances", { p_employee_id: employeeId }),
      supabase.rpc("fetch_employee_facility_commutes", { p_employee_id: employeeId }),
      supabase.rpc("fetch_employee_home_office", { p_employee_id: employeeId }),
    ]).then(([wagesRes, allowancesRes, commutesRes, homeOfficeRes]) => {
      if (wagesRes.error) {
        setLoadError(wagesRes.error.message);
        return;
      }
      if (allowancesRes.error) {
        setLoadError(allowancesRes.error.message);
        return;
      }
      if (commutesRes.error) {
        setLoadError(commutesRes.error.message);
        return;
      }
      if (homeOfficeRes.error) {
        setLoadError(homeOfficeRes.error.message);
        return;
      }
      setWages((wagesRes.data ?? []) as FacilityWage[]);
      setAllowances((allowancesRes.data ?? []) as FacilityAllowance[]);
      setCommutes((commutesRes.data ?? []) as FacilityCommute[]);
      const homeOfficeRow = (homeOfficeRes.data ?? [])[0] as
        | { office_id: string; office_name: string }
        | undefined;
      setHomeOffice(homeOfficeRow ?? null);
    });
  }, [employeeId, reloadToken]);

  const hasMultipleOffices = wages.length > 1;
  const isHourlyMultiOffice = hasMultipleOffices && wages.some((w) => w.salary_type === "時給");

  function reload() {
    setReloadToken((t) => t + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="max-h-[85vh] w-full max-w-2xl overflow-y-auto rounded-2xl bg-white p-6 shadow-lg">
        <div className="mb-4 flex items-start justify-between">
          <div>
            <h2 className="text-base font-bold text-slate-800">施設別 給与・手当・通勤費</h2>
            <p className="text-sm text-slate-500">{employeeName}</p>
          </div>
          <button onClick={onClose} className="text-sm text-slate-400 hover:text-slate-600">
            閉じる
          </button>
        </div>

        {loadError && <p className="mb-4 text-sm font-medium text-red-500">{loadError}</p>}

        {isHourlyMultiOffice && (
          <p className="mb-4 rounded-lg bg-amber-50 p-3 text-xs text-amber-700">
            時給の職員は複数施設の勤務時間を按分できないため、割増賃金・基本給は単一施設分としてのみ
            正しく計算されます(施設別の勤務時間記録が未対応のため)。
          </p>
        )}

        <section className="mb-6">
          <div className="mb-2 flex items-center justify-between">
            <h3 className="text-sm font-semibold text-slate-700">基本給</h3>
            <button
              onClick={() => setShowWageModal(true)}
              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
            >
              施設を追加
            </button>
          </div>
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-2 py-2">施設</th>
                <th className="px-2 py-2">給与形態</th>
                <th className="px-2 py-2">金額</th>
                <th className="px-2 py-2">適用開始日</th>
              </tr>
            </thead>
            <tbody>
              {wages.map((w) => (
                <tr key={w.office_id} className="border-b border-slate-100">
                  <td className="px-2 py-2">{w.office_name}</td>
                  <td className="px-2 py-2">{w.salary_type}</td>
                  <td className="px-2 py-2">
                    {w.salary_type === "月給" ? `${w.monthly_base_salary ?? 0}円/月` : `${w.hourly_wage ?? 0}円/時`}
                  </td>
                  <td className="px-2 py-2 text-slate-500">{w.effective_start_date}</td>
                </tr>
              ))}
              {wages.length === 0 && (
                <tr>
                  <td colSpan={4} className="px-2 py-4 text-center text-slate-400">
                    未設定
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </section>

        <section className="mb-6">
          <div className="mb-2 flex items-center justify-between">
            <h3 className="text-sm font-semibold text-slate-700">手当</h3>
            <button
              onClick={() => setShowAllowanceModal(true)}
              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
            >
              手当を追加
            </button>
          </div>
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-2 py-2">施設</th>
                <th className="px-2 py-2">手当種別</th>
                <th className="px-2 py-2">金額</th>
                <th className="px-2 py-2">適用開始日</th>
              </tr>
            </thead>
            <tbody>
              {allowances.map((a) => (
                <tr key={`${a.office_id}-${a.allowance_master_id}`} className="border-b border-slate-100">
                  <td className="px-2 py-2">{a.office_name}</td>
                  <td className="px-2 py-2">{a.allowance_name}</td>
                  <td className="px-2 py-2">{a.amount}円</td>
                  <td className="px-2 py-2 text-slate-500">{a.effective_start_date}</td>
                </tr>
              ))}
              {allowances.length === 0 && (
                <tr>
                  <td colSpan={4} className="px-2 py-4 text-center text-slate-400">
                    未設定
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </section>

        <section className="mb-2">
          <div className="mb-2 flex items-center justify-between">
            <h3 className="text-sm font-semibold text-slate-700">通勤費(所属施設のみ)</h3>
            <button
              onClick={() => setShowCommuteModal(true)}
              disabled={!homeOffice}
              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-50"
            >
              通勤費を追加
            </button>
          </div>
          <p className="mb-2 text-xs text-slate-400">
            通勤費は所属施設からのみ支給されます(兼務施設分は計上されません)。
          </p>
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-2 py-2">施設</th>
                <th className="px-2 py-2">算定方法</th>
                <th className="px-2 py-2">金額</th>
                <th className="px-2 py-2">適用開始日</th>
              </tr>
            </thead>
            <tbody>
              {commutes.map((c) => (
                <tr key={c.office_id} className="border-b border-slate-100">
                  <td className="px-2 py-2">{c.office_name}</td>
                  <td className="px-2 py-2">
                    {c.calc_type === "fixed_monthly" ? "月額固定" : "日額×勤務日数"}
                  </td>
                  <td className="px-2 py-2">{c.unit_price}円</td>
                  <td className="px-2 py-2 text-slate-500">{c.effective_start_date}</td>
                </tr>
              ))}
              {commutes.length === 0 && (
                <tr>
                  <td colSpan={4} className="px-2 py-4 text-center text-slate-400">
                    未設定
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </section>
      </div>

      {showWageModal && (
        <EditFacilityWageModal
          employeeId={employeeId}
          employeeName={employeeName}
          onClose={() => setShowWageModal(false)}
          onSaved={() => {
            setShowWageModal(false);
            reload();
          }}
        />
      )}
      {showAllowanceModal && (
        <EditFacilityAllowanceModal
          employeeId={employeeId}
          employeeName={employeeName}
          onClose={() => setShowAllowanceModal(false)}
          onSaved={() => {
            setShowAllowanceModal(false);
            reload();
          }}
        />
      )}
      {showCommuteModal && homeOffice && (
        <EditFacilityCommuteModal
          employeeId={employeeId}
          employeeName={employeeName}
          homeOfficeId={homeOffice.office_id}
          homeOfficeName={homeOffice.office_name}
          onClose={() => setShowCommuteModal(false)}
          onSaved={() => {
            setShowCommuteModal(false);
            reload();
          }}
        />
      )}
    </div>
  );
}
