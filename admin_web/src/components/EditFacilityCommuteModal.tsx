"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Props = {
  employeeId: string;
  employeeName: string;
  homeOfficeId: string;
  homeOfficeName: string;
  onClose: () => void;
  onSaved: () => void;
};

function currentDateStr(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

export function EditFacilityCommuteModal({
  employeeId,
  employeeName,
  homeOfficeId,
  homeOfficeName,
  onClose,
  onSaved,
}: Props) {
  const [commuteMethod, setCommuteMethod] = useState("");
  const [unitPrice, setUnitPrice] = useState("");
  const [calcType, setCalcType] = useState<"fixed_monthly" | "per_day_roundtrip">("fixed_monthly");
  const [taxableLimit, setTaxableLimit] = useState("");
  const [effectiveStartDate, setEffectiveStartDate] = useState(currentDateStr());
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    const unitPriceNum = Number(unitPrice);
    if (!Number.isInteger(unitPriceNum) || unitPriceNum < 0) {
      setErrorMessage("金額は0以上の整数で入力してください");
      return;
    }

    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("set_employee_facility_commute", {
      p_employee_id: employeeId,
      p_office_id: homeOfficeId,
      p_commute_method: commuteMethod || null,
      p_unit_price: unitPriceNum,
      p_calc_type: calcType,
      p_taxable_limit: taxableLimit ? Number(taxableLimit) : null,
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
        <h2 className="mb-1 text-base font-bold text-slate-800">通勤費の追加</h2>
        <p className="mb-4 text-sm text-slate-500">{employeeName}</p>

        <p className="mb-4 rounded-lg bg-sky-50 p-3 text-xs text-sky-700">
          通勤費は所属施設(<span className="font-semibold">{homeOfficeName}</span>)からのみ支給されます。
          兼務施設分は計上されません(1日1回のみの支給)。
        </p>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">通勤方法(任意)</label>
            <input
              type="text"
              value={commuteMethod}
              onChange={(e) => setCommuteMethod(e.target.value)}
              placeholder="例: 電車・バス"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">算定方法</label>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setCalcType("fixed_monthly")}
                className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                  calcType === "fixed_monthly"
                    ? "border-sky-400 bg-sky-50 text-sky-700"
                    : "border-slate-300 text-slate-600 hover:bg-slate-50"
                }`}
              >
                月額固定
              </button>
              <button
                type="button"
                onClick={() => setCalcType("per_day_roundtrip")}
                className={`rounded-lg border px-4 py-2 text-sm font-medium transition ${
                  calcType === "per_day_roundtrip"
                    ? "border-sky-400 bg-sky-50 text-sky-700"
                    : "border-slate-300 text-slate-600 hover:bg-slate-50"
                }`}
              >
                日額×勤務日数
              </button>
            </div>
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">
              {calcType === "fixed_monthly" ? "月額(円)" : "日額(円)"}
            </label>
            <input
              type="number"
              min={0}
              value={unitPrice}
              onChange={(e) => setUnitPrice(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">非課税限度額(円・任意)</label>
            <input
              type="number"
              min={0}
              value={taxableLimit}
              onChange={(e) => setTaxableLimit(e.target.value)}
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
