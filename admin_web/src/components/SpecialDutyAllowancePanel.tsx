"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type EmployeeOption = { id: string; name: string; office_name: string };

const REASON_CATEGORIES = ["処遇改善手当分配", "業務負担加算", "特別業務対応", "役割加算", "臨時補助金分配", "その他"] as const;

type SpecialDutyAllowanceRecord = {
  id: string;
  employee_id: string;
  employee_name: string;
  amount: number;
  reason_category: string;
  reason_detail: string | null;
  internal_memo: string | null;
  show_on_payslip: boolean;
  display_text: string | null;
  confirmed: boolean;
};

type Props = { month: string };

export function SpecialDutyAllowancePanel({ month }: Props) {
  const [employees, setEmployees] = useState<EmployeeOption[]>([]);
  const [records, setRecords] = useState<SpecialDutyAllowanceRecord[]>([]);
  const [listError, setListError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [employeeId, setEmployeeId] = useState("");
  const [amount, setAmount] = useState("");
  const [reasonCategory, setReasonCategory] = useState<(typeof REASON_CATEGORIES)[number]>(REASON_CATEGORIES[0]);
  const [reasonDetail, setReasonDetail] = useState("");
  const [showOnPayslip, setShowOnPayslip] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_employees_tax_withholding_status").then(({ data, error }) => {
      if (error) return;
      const list = (data ?? []) as { employee_id: string; employee_name: string; office_name: string }[];
      const opts = list.map((e) => ({ id: e.employee_id, name: e.employee_name, office_name: e.office_name }));
      setEmployees(opts);
      if (opts.length > 0) setEmployeeId((prev) => prev || opts[0].id);
    });
  }, []);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_special_duty_allowances", { p_month: `${month}-01` }).then(({ data, error }) => {
      if (error) {
        setListError(error.message);
        return;
      }
      setRecords((data ?? []) as SpecialDutyAllowanceRecord[]);
    });
  }, [month, reloadToken]);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const amountNum = Number(amount);
    if (!employeeId) {
      setFormError("職員を選択してください");
      return;
    }
    if (!Number.isInteger(amountNum) || amountNum < 0) {
      setFormError("金額は0以上の整数で入力してください");
      return;
    }

    setIsSaving(true);
    setFormError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("set_special_duty_allowance", {
      p_employee_id: employeeId,
      p_target_payroll_month: `${month}-01`,
      p_amount: amountNum,
      p_reason_category: reasonCategory,
      p_reason_detail: reasonDetail || null,
      p_internal_memo: null,
      p_show_on_payslip: showOnPayslip,
      p_display_text: null,
      p_confirmed: false,
    });
    setIsSaving(false);
    if (error) {
      setFormError(error.message);
      return;
    }
    setReasonDetail("");
    setAmount("");
    setReloadToken((t) => t + 1);
  }

  async function handleConfirm(record: SpecialDutyAllowanceRecord) {
    const supabase = createClient();
    await supabase.rpc("set_special_duty_allowance", {
      p_employee_id: record.employee_id,
      p_target_payroll_month: `${month}-01`,
      p_amount: record.amount,
      p_reason_category: record.reason_category,
      p_reason_detail: record.reason_detail,
      p_internal_memo: record.internal_memo,
      p_show_on_payslip: record.show_on_payslip,
      p_display_text: record.display_text,
      p_confirmed: true,
    });
    setReloadToken((t) => t + 1);
  }

  async function handleDelete(id: string) {
    if (!window.confirm("この特殊業務手当を削除しますか?")) return;
    const supabase = createClient();
    await supabase.rpc("delete_special_duty_allowance", { p_id: id });
    setReloadToken((t) => t + 1);
  }

  return (
    <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
      <h3 className="text-base font-bold text-slate-800">特殊業務手当</h3>
      <p className="text-xs text-slate-400">
        処遇改善手当分配・臨時補助金分配等、月ごとに個別発生する手当を登録します。
        「承認する」を押すまでは給与計算に反映されません。1職員につき対象月1件のみ登録できます(再登録は上書き)。
      </p>

      <form onSubmit={handleSubmit} className="grid gap-3 sm:grid-cols-2 lg:grid-cols-6 lg:items-end">
        <div className="lg:col-span-2">
          <label className="mb-1 block text-xs font-medium text-slate-500">職員</label>
          <select
            value={employeeId}
            onChange={(e) => setEmployeeId(e.target.value)}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          >
            {employees.map((e) => (
              <option key={e.id} value={e.id}>
                {e.name}({e.office_name})
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">区分</label>
          <select
            value={reasonCategory}
            onChange={(e) => setReasonCategory(e.target.value as (typeof REASON_CATEGORIES)[number])}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          >
            {REASON_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">詳細(任意)</label>
          <input
            type="text"
            value={reasonDetail}
            onChange={(e) => setReasonDetail(e.target.value)}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">金額(円)</label>
          <input
            type="number"
            min={0}
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>
        <div className="flex items-center gap-2 pb-2">
          <input
            id="sda-show-on-payslip"
            type="checkbox"
            checked={showOnPayslip}
            onChange={(e) => setShowOnPayslip(e.target.checked)}
            className="h-4 w-4 rounded border-slate-300"
          />
          <label htmlFor="sda-show-on-payslip" className="text-sm text-slate-700">
            明細に表示
          </label>
        </div>
        <button
          type="submit"
          disabled={isSaving}
          className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
        >
          {isSaving ? "登録中…" : "登録する"}
        </button>
      </form>
      {formError && <p className="text-sm font-medium text-red-500">{formError}</p>}

      {listError && <p className="text-sm font-medium text-red-500">{listError}</p>}
      <div className="space-y-2 border-t border-slate-100 pt-4">
        {records.length === 0 && <p className="text-sm text-slate-400">{month}分の登録はありません</p>}
        <ul className="divide-y divide-slate-100">
          {records.map((r) => (
            <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
              <div>
                <span className="font-medium text-slate-700">{r.employee_name}</span>
                <span className="ml-2 text-slate-500">{r.reason_category}</span>
                {r.reason_detail && <span className="ml-2 text-slate-500">{r.reason_detail}</span>}
                <span className="ml-2 text-slate-600">{r.amount.toLocaleString("ja-JP")}円</span>
                <span
                  className={`ml-2 rounded-full px-2 py-0.5 text-xs font-semibold ${
                    r.confirmed ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700"
                  }`}
                >
                  {r.confirmed ? "承認済み" : "未承認"}
                </span>
              </div>
              <div className="flex gap-2">
                {!r.confirmed && (
                  <button
                    onClick={() => handleConfirm(r)}
                    className="rounded-lg border border-emerald-300 px-3 py-1 text-xs font-medium text-emerald-700 hover:bg-emerald-50"
                  >
                    承認する
                  </button>
                )}
                <button
                  onClick={() => handleDelete(r.id)}
                  className="rounded-lg border border-red-300 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50"
                >
                  削除
                </button>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
