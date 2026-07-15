"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

type EmployeeTaxStatus = {
  employee_id: string;
  employee_name: string;
  office_name: string;
  tax_column: "甲欄" | "乙欄" | null;
  social_insurance_dependent_count: number | null;
  income_tax_dependent_count: number | null;
  submitted_flag: boolean | null;
};

type Props = {
  employee: EmployeeTaxStatus;
  onClose: () => void;
  onSaved: () => void;
};

function currentYearMonth(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

export function EditTaxWithholdingModal({ employee, onClose, onSaved }: Props) {
  const [taxColumn, setTaxColumn] = useState<"甲欄" | "乙欄">(employee.tax_column ?? "乙欄");
  const [socialInsuranceDependentCount, setSocialInsuranceDependentCount] = useState(
    String(employee.social_insurance_dependent_count ?? 0),
  );
  const [incomeTaxDependentCount, setIncomeTaxDependentCount] = useState(
    String(employee.income_tax_dependent_count ?? 0),
  );
  const [submittedFlag, setSubmittedFlag] = useState(employee.submitted_flag ?? false);
  const [effectiveYearMonth, setEffectiveYearMonth] = useState(currentYearMonth());
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const socialInsuranceDependentCountNum = Number(socialInsuranceDependentCount);
    if (!Number.isInteger(socialInsuranceDependentCountNum) || socialInsuranceDependentCountNum < 0) {
      setErrorMessage("①社会保険の扶養人数は0以上の整数で入力してください");
      return;
    }
    const incomeTaxDependentCountNum = Number(incomeTaxDependentCount);
    if (!Number.isInteger(incomeTaxDependentCountNum) || incomeTaxDependentCountNum < 0) {
      setErrorMessage("②所得税の扶養人数は0以上の整数で入力してください");
      return;
    }

    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("set_employee_tax_withholding_status", {
      p_employee_id: employee.employee_id,
      p_tax_column: taxColumn,
      p_social_insurance_dependent_count: socialInsuranceDependentCountNum,
      p_income_tax_dependent_count: incomeTaxDependentCountNum,
      p_submitted_flag: submittedFlag,
      p_effective_start_year_month: `${effectiveYearMonth}-01`,
    });

    setIsSaving(false);
    if (error) {
      setErrorMessage(error.message);
      return;
    }
    onSaved();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-1 text-base font-bold text-slate-800">源泉徴収区分・扶養人数の変更</h2>
        <p className="mb-4 text-sm text-slate-500">
          {employee.employee_name} / {employee.office_name}
        </p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">源泉徴収区分</label>
            <div className="flex gap-3">
              {(["甲欄", "乙欄"] as const).map((col) => (
                <button
                  key={col}
                  type="button"
                  onClick={() => setTaxColumn(col)}
                  className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                    taxColumn === col
                      ? "border-sky-400 bg-sky-50 text-sky-700"
                      : "border-slate-300 text-slate-600 hover:bg-slate-50"
                  }`}
                >
                  {col}
                </button>
              ))}
            </div>
            <p className="mt-1 text-xs text-slate-400">
              扶養控除等申告書の提出あり=甲欄 / 提出なし=乙欄(6.6章)
            </p>
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">①社会保険の扶養人数</label>
            <input
              type="number"
              min={0}
              value={socialInsuranceDependentCount}
              onChange={(e) => setSocialInsuranceDependentCount(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">自身の健康保険等の被扶養者数。源泉徴収税額の計算には使用しません。</p>
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">②所得税の扶養人数(源泉控除対象扶養親族の数)</label>
            <input
              type="number"
              min={0}
              value={incomeTaxDependentCount}
              onChange={(e) => setIncomeTaxDependentCount(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">源泉徴収税額表のルックアップに使用する扶養人数です。</p>
          </div>

          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input
              type="checkbox"
              checked={submittedFlag}
              onChange={(e) => setSubmittedFlag(e.target.checked)}
              className="h-4 w-4 rounded border-slate-300"
            />
            扶養控除等申告書の提出あり
          </label>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">適用開始年月</label>
            <input
              type="month"
              value={effectiveYearMonth}
              onChange={(e) => setEffectiveYearMonth(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">
              既存の適用中データがある場合、この月の前月末で自動的に履歴を閉じます
            </p>
          </div>

          {errorMessage && <p className="text-sm font-medium text-red-500">{errorMessage}</p>}

          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
            >
              キャンセル
            </button>
            <button
              type="submit"
              disabled={isSaving}
              className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
            >
              {isSaving ? "保存中…" : "保存する"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
