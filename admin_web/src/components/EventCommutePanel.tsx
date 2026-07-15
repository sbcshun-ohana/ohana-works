"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type EmployeeOption = { id: string; name: string; office_name: string };

type EventCommuteRecord = {
  id: string;
  employee_id: string;
  employee_name: string;
  work_date: string;
  destination: string | null;
  amount: number;
  taxable: boolean;
  confirmed: boolean;
};

type Props = { month: string };

export function EventCommutePanel({ month }: Props) {
  const [employees, setEmployees] = useState<EmployeeOption[]>([]);
  const [records, setRecords] = useState<EventCommuteRecord[]>([]);
  const [listError, setListError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [employeeId, setEmployeeId] = useState("");
  const [workDate, setWorkDate] = useState(`${month}-01`);
  const [destination, setDestination] = useState("");
  const [amount, setAmount] = useState("");
  const [taxable, setTaxable] = useState(true);
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
    supabase.rpc("fetch_event_commute_records", { p_month: `${month}-01` }).then(({ data, error }) => {
      if (error) {
        setListError(error.message);
        return;
      }
      setRecords((data ?? []) as EventCommuteRecord[]);
    });
  }, [month, reloadToken]);

  useEffect(() => {
    setWorkDate(`${month}-01`);
  }, [month]);

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
    if (!workDate.startsWith(month)) {
      setFormError(`work_dateは対象月(${month})内の日付で指定してください`);
      return;
    }

    setIsSaving(true);
    setFormError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("set_event_commute_record", {
      p_employee_id: employeeId,
      p_work_date: workDate,
      p_destination: destination || null,
      p_amount: amountNum,
      p_taxable: taxable,
      p_confirmed: false,
    });
    setIsSaving(false);
    if (error) {
      setFormError(error.message);
      return;
    }
    setDestination("");
    setAmount("");
    setReloadToken((t) => t + 1);
  }

  async function handleConfirm(record: EventCommuteRecord) {
    const supabase = createClient();
    await supabase.rpc("set_event_commute_record", {
      p_employee_id: record.employee_id,
      p_work_date: record.work_date,
      p_destination: record.destination,
      p_amount: record.amount,
      p_taxable: record.taxable,
      p_confirmed: true,
    });
    setReloadToken((t) => t + 1);
  }

  async function handleDelete(id: string) {
    if (!window.confirm("このイベント通勤費を削除しますか?")) return;
    const supabase = createClient();
    await supabase.rpc("delete_event_commute_record", { p_id: id });
    setReloadToken((t) => t + 1);
  }

  return (
    <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
      <h3 className="text-base font-bold text-slate-800">イベント直行日の通勤費</h3>
      <p className="text-xs text-slate-400">
        保育園以外のイベント先へ直行した日の実費を登録します。この日は通常の施設通勤費とは重複計上されません。
        「承認する」を押すまでは給与計算に反映されません。
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
          <label className="mb-1 block text-xs font-medium text-slate-500">日付</label>
          <input
            type="date"
            value={workDate}
            onChange={(e) => setWorkDate(e.target.value)}
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
        </div>
        <div>
          <label className="mb-1 block text-xs font-medium text-slate-500">イベント先(任意)</label>
          <input
            type="text"
            value={destination}
            onChange={(e) => setDestination(e.target.value)}
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
            id="event-commute-taxable"
            type="checkbox"
            checked={taxable}
            onChange={(e) => setTaxable(e.target.checked)}
            className="h-4 w-4 rounded border-slate-300"
          />
          <label htmlFor="event-commute-taxable" className="text-sm text-slate-700">
            課税対象
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
                <span className="ml-2 text-slate-500">{r.work_date}</span>
                {r.destination && <span className="ml-2 text-slate-500">{r.destination}</span>}
                <span className="ml-2 text-slate-600">{r.amount.toLocaleString("ja-JP")}円</span>
                <span className="ml-2 text-xs text-slate-400">{r.taxable ? "課税" : "非課税"}</span>
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
