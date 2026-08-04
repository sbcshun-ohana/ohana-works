"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { EditTaxWithholdingModal } from "@/components/EditTaxWithholdingModal";
import { EmployeeFacilityPayPanel } from "@/components/EmployeeFacilityPayPanel";
import { StaffPinManagementModal } from "@/components/StaffPinManagementModal";

type EmployeeTaxStatus = {
  employee_id: string;
  employee_name: string;
  office_name: string;
  tax_column: "甲欄" | "乙欄" | null;
  social_insurance_dependent_count: number | null;
  income_tax_dependent_count: number | null;
  submitted_flag: boolean | null;
  effective_start_year_month: string | null;
};

type DirectoryRow = { employee_number: string; name: string; home_office_id: string | null };

export default function EmployeesPage() {
  // 労務(労務管理者以上)と 基本情報のみ(統括園長)を分けて出し分ける(第1段)。
  const [isLabor, setIsLabor] = useState<boolean | null>(null);
  const [isExec, setIsExec] = useState<boolean | null>(null);
  const [employees, setEmployees] = useState<EmployeeTaxStatus[]>([]);
  const [directory, setDirectory] = useState<DirectoryRow[]>([]);
  const [officeNames, setOfficeNames] = useState<Record<string, string>>({});
  const [listError, setListError] = useState<string | null>(null);
  const [editingEmployee, setEditingEmployee] = useState<EmployeeTaxStatus | null>(null);
  const [payEmployee, setPayEmployee] = useState<EmployeeTaxStatus | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [pinMgmtOpen, setPinMgmtOpen] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("is_labor_manager_plus").then(({ data, error }) => setIsLabor(error ? false : Boolean(data)));
    supabase.rpc("is_executive_or_system_admin").then(({ data, error }) => setIsExec(error ? false : Boolean(data)));
  }, []);

  // 労務: 源泉徴収一覧(労務RPC)。
  useEffect(() => {
    if (!isLabor) return;
    createClient()
      .rpc("fetch_employees_tax_withholding_status")
      .then(({ data, error }) => {
        if (error) {
          setListError(error.message);
          return;
        }
        setEmployees((data ?? []) as EmployeeTaxStatus[]);
      });
  }, [isLabor, reloadToken]);

  // 統括園長(労務でない): 基本情報の名簿(fetch_employee_directory)+ 所属名解決。
  useEffect(() => {
    if (isLabor || !isExec) return;
    const supabase = createClient();
    supabase.rpc("fetch_employee_directory").then(({ data, error }) => {
      if (error) {
        setListError(error.message);
        return;
      }
      setDirectory((data ?? []) as DirectoryRow[]);
    });
    supabase.rpc("fetch_my_childcare_offices").then(({ data }) => {
      const map: Record<string, string> = {};
      for (const o of (data ?? []) as { office_id: string; office_name: string }[]) map[o.office_id] = o.office_name;
      setOfficeNames(map);
    });
  }, [isLabor, isExec]);

  if (isLabor === null || isExec === null) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-400">読み込み中…</div>
      </div>
    );
  }

  if (!isLabor && !isExec) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">
          この機能を利用する権限がありません(労務管理者以上、または統括園長が必要です)。
        </div>
      </div>
    );
  }

  // 統括園長(労務でない): 基本情報のみ(名簿+PIN管理)。労務セクションは非表示。
  if (!isLabor && isExec) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <main className="flex-1 space-y-6 p-6">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-lg font-bold text-slate-800">職員マスタ(基本情報)</h2>
            <button
              onClick={() => setPinMgmtOpen(true)}
              className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-100"
            >
              職員PIN管理
            </button>
          </div>
          <p className="text-xs text-slate-400">統括園長は基本情報(職員名簿)とPIN管理を利用できます。労務情報(源泉徴収・給与等)は労務管理者以上のみです。</p>
          {listError && <p className="text-sm font-medium text-red-500">{listError}</p>}
          <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">職員番号</th>
                  <th className="px-4 py-3">氏名</th>
                  <th className="px-4 py-3">所属</th>
                </tr>
              </thead>
              <tbody>
                {directory.map((d) => (
                  <tr key={d.employee_number} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                    <td className="px-4 py-3 text-slate-500">{d.employee_number}</td>
                    <td className="px-4 py-3 font-medium text-slate-800">{d.name}</td>
                    <td className="px-4 py-3 text-slate-500">{d.home_office_id ? officeNames[d.home_office_id] ?? "—" : "—"}</td>
                  </tr>
                ))}
                {directory.length === 0 && (
                  <tr>
                    <td colSpan={3} className="px-4 py-6 text-center text-slate-400">在籍中の職員はいません</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </main>
        {pinMgmtOpen && <StaffPinManagementModal onClose={() => setPinMgmtOpen(false)} />}
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-bold text-slate-800">職員マスタ(源泉徴収区分・扶養人数)</h2>
          <button
            onClick={() => setPinMgmtOpen(true)}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-100"
          >
            職員PIN管理
          </button>
        </div>
        <p className="text-xs text-slate-400">
          6.6章: 扶養控除等申告書の提出あり=甲欄・なし=乙欄。給与計算エンジンは未設定の職員を乙欄・扶養0人として扱います。
          扶養人数は①社会保険の扶養人数(自身の健康保険等の被扶養者数)と②所得税の扶養人数(源泉控除対象扶養親族数)を別々に管理し、
          源泉徴収税額の計算には②のみを使用します。
        </p>

        {listError && <p className="text-sm font-medium text-red-500">{listError}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-4 py-3">職員</th>
                <th className="px-4 py-3">施設</th>
                <th className="px-4 py-3">源泉徴収区分</th>
                <th className="px-4 py-3">①社保扶養</th>
                <th className="px-4 py-3">②所得税扶養</th>
                <th className="px-4 py-3">適用開始年月</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              {employees.map((emp) => (
                <tr key={emp.employee_id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                  <td className="px-4 py-3 font-medium text-slate-800">{emp.employee_name}</td>
                  <td className="px-4 py-3 text-slate-500">{emp.office_name}</td>
                  <td className="px-4 py-3">
                    {emp.tax_column ? (
                      <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-600">
                        {emp.tax_column}
                      </span>
                    ) : (
                      <span className="text-xs text-amber-600">未設定(乙欄扱い)</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-slate-600">{emp.social_insurance_dependent_count ?? "—"}</td>
                  <td className="px-4 py-3 text-slate-600">{emp.income_tax_dependent_count ?? "—"}</td>
                  <td className="px-4 py-3 text-slate-500">{emp.effective_start_year_month ?? "—"}</td>
                  <td className="px-4 py-3 text-right">
                    <div className="flex justify-end gap-2">
                      <button
                        onClick={() => setPayEmployee(emp)}
                        className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                      >
                        給与・手当・通勤費
                      </button>
                      <button
                        onClick={() => setEditingEmployee(emp)}
                        className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                      >
                        編集
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {employees.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-4 py-6 text-center text-slate-400">
                    在籍中の職員はいません
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </main>

      {editingEmployee && (
        <EditTaxWithholdingModal
          employee={editingEmployee}
          onClose={() => setEditingEmployee(null)}
          onSaved={() => {
            setEditingEmployee(null);
            setReloadToken((t) => t + 1);
          }}
        />
      )}

      {payEmployee && (
        <EmployeeFacilityPayPanel
          employeeId={payEmployee.employee_id}
          employeeName={payEmployee.employee_name}
          onClose={() => setPayEmployee(null)}
        />
      )}

      {pinMgmtOpen && <StaffPinManagementModal onClose={() => setPinMgmtOpen(false)} />}
    </div>
  );
}
