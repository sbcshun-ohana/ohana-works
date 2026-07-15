"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Office = { id: string; name: string };

type Props = {
  employeeId: string;
  employeeName: string;
  onClose: () => void;
  onSaved: () => void;
};

function currentDateStr(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

export function EditFacilityWageModal({ employeeId, employeeName, onClose, onSaved }: Props) {
  const [offices, setOffices] = useState<Office[]>([]);
  const [officeId, setOfficeId] = useState("");
  const [salaryType, setSalaryType] = useState<"月給" | "時給">("月給");
  const [amount, setAmount] = useState("");
  const [effectiveStartDate, setEffectiveStartDate] = useState(currentDateStr());
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase
      .from("offices")
      .select("id, name")
      .then(({ data, error }) => {
        if (!error) {
          const list = (data ?? []) as Office[];
          setOffices(list);
          if (list.length > 0) setOfficeId(list[0].id);
        }
      });
  }, []);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const amountNum = Number(amount);
    if (!Number.isInteger(amountNum) || amountNum < 0) {
      setErrorMessage("金額は0以上の整数で入力してください");
      return;
    }
    if (!officeId) {
      setErrorMessage("施設を選択してください");
      return;
    }

    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("set_employee_facility_wage", {
      p_employee_id: employeeId,
      p_office_id: officeId,
      p_salary_type: salaryType,
      p_monthly_base_salary: salaryType === "月給" ? amountNum : null,
      p_hourly_wage: salaryType === "時給" ? amountNum : null,
      p_effective_start_date: effectiveStartDate,
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
        <h2 className="mb-1 text-base font-bold text-slate-800">施設別基本給の追加</h2>
        <p className="mb-4 text-sm text-slate-500">{employeeName}</p>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">施設</label>
            <select
              value={officeId}
              onChange={(e) => setOfficeId(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">給与形態</label>
            <div className="flex gap-3">
              {(["月給", "時給"] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setSalaryType(t)}
                  className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                    salaryType === t
                      ? "border-sky-400 bg-sky-50 text-sky-700"
                      : "border-slate-300 text-slate-600 hover:bg-slate-50"
                  }`}
                >
                  {t}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">
              {salaryType === "月給" ? "月額基本給(円)" : "時給(円)"}
            </label>
            <input
              type="number"
              min={0}
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">適用開始日</label>
            <input
              type="date"
              value={effectiveStartDate}
              onChange={(e) => setEffectiveStartDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">
              同じ施設に既存の適用中データがある場合、この日の前日で自動的に履歴を閉じます
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
