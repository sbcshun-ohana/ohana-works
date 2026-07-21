"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ShiftExceptionModal } from "@/components/ShiftExceptionModal";
import { currentYearMonth, dayOfWeekLabel, formatTimeOnly, monthRange } from "@/lib/datetime";
import {
  WEEKDAY_LABELS,
  type ManageableOffice,
  type OfficeEmployee,
  type ShiftExceptionRow,
  type ShiftWeeklyTemplateRow,
} from "@/lib/types";

type WeeklyRowState = {
  hasTemplate: boolean;
  startTime: string;
  endTime: string;
  breakMinutes: number;
  isSaving: boolean;
  isDeleting: boolean;
};

function emptyWeeklyRow(): WeeklyRowState {
  return { hasTemplate: false, startTime: "09:00", endTime: "18:00", breakMinutes: 60, isSaving: false, isDeleting: false };
}

export default function ShiftsPage() {
  const [offices, setOffices] = useState<ManageableOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [selectedOffice, setSelectedOffice] = useState<string>("");

  const [employees, setEmployees] = useState<OfficeEmployee[]>([]);
  const [employeesError, setEmployeesError] = useState<string | null>(null);
  const [selectedEmployee, setSelectedEmployee] = useState<string>("");

  const [weeklyRows, setWeeklyRows] = useState<WeeklyRowState[]>(
    Array.from({ length: 7 }, () => emptyWeeklyRow()),
  );
  const [weeklyError, setWeeklyError] = useState<string | null>(null);
  const [weeklyReloadToken, setWeeklyReloadToken] = useState(0);

  const [yearMonth, setYearMonth] = useState(currentYearMonth());
  const [exceptions, setExceptions] = useState<ShiftExceptionRow[]>([]);
  const [exceptionsError, setExceptionsError] = useState<string | null>(null);
  const [exceptionsReloadToken, setExceptionsReloadToken] = useState(0);
  const [modalState, setModalState] = useState<{ initial: ShiftExceptionRow | null; defaultDate: string } | null>(null);

  const [isGenerating, setIsGenerating] = useState(false);
  const [generateMessage, setGenerateMessage] = useState<string | null>(null);
  const [generateError, setGenerateError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_manageable_offices").then(({ data, error }) => {
      if (error) {
        setOfficesError(error.message);
        return;
      }
      const list = (data ?? []) as ManageableOffice[];
      setOffices(list);
      if (list.length > 0) {
        setSelectedOffice(list[0].id);
      }
    });
  }, []);

  useEffect(() => {
    function clearEmployees() {
      setEmployees([]);
      setSelectedEmployee("");
    }
    if (!selectedOffice) {
      clearEmployees();
      return;
    }
    const supabase = createClient();
    supabase.rpc("fetch_office_employees", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (error) {
        setEmployeesError(error.message);
        return;
      }
      const list = (data ?? []) as OfficeEmployee[];
      setEmployees(list);
      setSelectedEmployee(list.length > 0 ? list[0].employee_id : "");
    });
  }, [selectedOffice]);

  useEffect(() => {
    function clearWeekly() {
      setWeeklyRows(Array.from({ length: 7 }, () => emptyWeeklyRow()));
    }
    if (!selectedEmployee) {
      clearWeekly();
      return;
    }
    const supabase = createClient();
    supabase.rpc("fetch_shift_weekly_template", { p_employee_id: selectedEmployee }).then(({ data, error }) => {
      if (error) {
        setWeeklyError(error.message);
        return;
      }
      const rows = (data ?? []) as ShiftWeeklyTemplateRow[];
      const next = Array.from({ length: 7 }, () => emptyWeeklyRow());
      for (const row of rows) {
        next[row.weekday] = {
          hasTemplate: true,
          startTime: row.start_time.slice(0, 5),
          endTime: row.end_time.slice(0, 5),
          breakMinutes: row.break_minutes,
          isSaving: false,
          isDeleting: false,
        };
      }
      setWeeklyRows(next);
    });
  }, [selectedEmployee, weeklyReloadToken]);

  useEffect(() => {
    function clearExceptions() {
      setExceptions([]);
    }
    if (!selectedEmployee) {
      clearExceptions();
      return;
    }
    const { start, end } = monthRange(yearMonth);
    const supabase = createClient();
    supabase
      .rpc("fetch_shift_exceptions", { p_employee_id: selectedEmployee, p_month_start: start, p_month_end: end })
      .then(({ data, error }) => {
        if (error) {
          setExceptionsError(error.message);
          return;
        }
        setExceptions((data ?? []) as ShiftExceptionRow[]);
      });
  }, [selectedEmployee, yearMonth, exceptionsReloadToken]);

  function updateWeeklyRow(weekday: number, patch: Partial<WeeklyRowState>) {
    setWeeklyRows((prev) => prev.map((row, i) => (i === weekday ? { ...row, ...patch } : row)));
  }

  async function handleSaveWeeklyRow(weekday: number) {
    const row = weeklyRows[weekday];
    updateWeeklyRow(weekday, { isSaving: true });
    setWeeklyError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("upsert_shift_weekly_template", {
      p_employee_id: selectedEmployee,
      p_office_id: selectedOffice,
      p_weekday: weekday,
      p_start_time: row.startTime,
      p_end_time: row.endTime,
      p_break_minutes: row.breakMinutes,
    });
    updateWeeklyRow(weekday, { isSaving: false });
    if (error) {
      setWeeklyError(error.message);
      return;
    }
    setWeeklyReloadToken((t) => t + 1);
  }

  async function handleDeleteWeeklyRow(weekday: number) {
    updateWeeklyRow(weekday, { isDeleting: true });
    setWeeklyError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("delete_shift_weekly_template", {
      p_employee_id: selectedEmployee,
      p_weekday: weekday,
    });
    updateWeeklyRow(weekday, { isDeleting: false });
    if (error) {
      setWeeklyError(error.message);
      return;
    }
    setWeeklyReloadToken((t) => t + 1);
  }

  async function handleGenerate() {
    setIsGenerating(true);
    setGenerateMessage(null);
    setGenerateError(null);
    const { start, end } = monthRange(yearMonth);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("generate_shifts_from_template", {
      p_employee_id: selectedEmployee,
      p_month_start: start,
      p_month_end: end,
    });
    setIsGenerating(false);
    if (error) {
      setGenerateError(error.message);
      return;
    }
    setGenerateMessage(`${yearMonth}分のシフトを${data}件、確定状態で生成しました。`);
  }

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  if (offices !== null && offices.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">
          この機能を利用する権限がありません(主任・園長・施設管理者以上が必要です)。
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">シフト管理(週次テンプレート・イレギュラー例外)</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices?.map((office) => (
                <option key={office.id} value={office.id}>
                  {office.name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">職員</label>
            <select
              value={selectedEmployee}
              onChange={(e) => setSelectedEmployee(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {employees.length === 0 && <option value="">(在籍職員がいません)</option>}
              {employees.map((emp) => (
                <option key={emp.employee_id} value={emp.employee_id}>
                  {emp.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {employeesError && <p className="text-sm font-medium text-red-500">{employeesError}</p>}

        {selectedEmployee && (
          <>
            <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
              <h3 className="text-base font-bold text-slate-800">週次テンプレート</h3>
              <p className="text-xs text-slate-500">
                曜日ごとの固定パターンを登録すると、翌週以降も同じ時刻で繰り返し適用されます。
              </p>
              {weeklyError && <p className="text-sm font-medium text-red-500">{weeklyError}</p>}
              <div className="overflow-x-auto">
                <table className="min-w-full text-sm">
                  <thead>
                    <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                      <th className="px-4 py-3">曜日</th>
                      <th className="px-4 py-3">開始時刻</th>
                      <th className="px-4 py-3">終了時刻</th>
                      <th className="px-4 py-3">休憩(分)</th>
                      <th className="px-4 py-3" />
                    </tr>
                  </thead>
                  <tbody>
                    {WEEKDAY_LABELS.map((label, weekday) => {
                      const row = weeklyRows[weekday];
                      return (
                        <tr key={weekday} className="border-b border-slate-100 last:border-0">
                          <td className="px-4 py-3 font-medium text-slate-800">{label}曜日</td>
                          <td className="px-4 py-3">
                            <input
                              type="time"
                              value={row.startTime}
                              onChange={(e) => updateWeeklyRow(weekday, { startTime: e.target.value })}
                              className="rounded-lg border border-slate-300 px-2 py-1 text-sm focus:border-sky-400 focus:outline-none"
                            />
                          </td>
                          <td className="px-4 py-3">
                            <input
                              type="time"
                              value={row.endTime}
                              onChange={(e) => updateWeeklyRow(weekday, { endTime: e.target.value })}
                              className="rounded-lg border border-slate-300 px-2 py-1 text-sm focus:border-sky-400 focus:outline-none"
                            />
                          </td>
                          <td className="px-4 py-3">
                            <input
                              type="number"
                              min={0}
                              value={row.breakMinutes}
                              onChange={(e) => updateWeeklyRow(weekday, { breakMinutes: Number(e.target.value) })}
                              className="w-20 rounded-lg border border-slate-300 px-2 py-1 text-sm focus:border-sky-400 focus:outline-none"
                            />
                          </td>
                          <td className="px-4 py-3 text-right">
                            <div className="flex justify-end gap-2">
                              <button
                                onClick={() => handleSaveWeeklyRow(weekday)}
                                disabled={row.isSaving}
                                className="rounded-lg bg-sky-500 px-3 py-1 text-xs font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
                              >
                                {row.isSaving ? "保存中…" : "保存"}
                              </button>
                              {row.hasTemplate && (
                                <button
                                  onClick={() => handleDeleteWeeklyRow(weekday)}
                                  disabled={row.isDeleting}
                                  className="rounded-lg border border-red-200 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                                >
                                  {row.isDeleting ? "削除中…" : "削除"}
                                </button>
                              )}
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
              <div className="flex flex-wrap items-end justify-between gap-4">
                <div>
                  <h3 className="text-base font-bold text-slate-800">イレギュラー例外</h3>
                  <p className="text-xs text-slate-500">特定の日だけ、テンプレートと異なる時刻または休みで上書きします。</p>
                </div>
                <div className="flex items-end gap-3">
                  <div>
                    <label className="mb-1 block text-xs font-medium text-slate-500">対象月</label>
                    <input
                      type="month"
                      value={yearMonth}
                      onChange={(e) => setYearMonth(e.target.value)}
                      className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                    />
                  </div>
                  <button
                    onClick={() => setModalState({ initial: null, defaultDate: monthRange(yearMonth).start })}
                    className="rounded-lg border border-sky-300 px-4 py-2 text-sm font-semibold text-sky-700 hover:bg-sky-50"
                  >
                    例外を追加
                  </button>
                </div>
              </div>

              {exceptionsError && <p className="text-sm font-medium text-red-500">{exceptionsError}</p>}

              <div className="overflow-x-auto">
                <table className="min-w-full text-sm">
                  <thead>
                    <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                      <th className="px-4 py-3">日付</th>
                      <th className="px-4 py-3">内容</th>
                      <th className="px-4 py-3">備考</th>
                      <th className="px-4 py-3" />
                    </tr>
                  </thead>
                  <tbody>
                    {exceptions.length === 0 && (
                      <tr>
                        <td colSpan={4} className="px-4 py-6 text-center text-slate-400">
                          対象月の例外はありません
                        </td>
                      </tr>
                    )}
                    {exceptions.map((exc) => (
                      <tr key={exc.id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                        <td className="px-4 py-3 font-medium text-slate-800">
                          {exc.work_date}({dayOfWeekLabel(exc.work_date)})
                        </td>
                        <td className="px-4 py-3">
                          {exc.is_day_off ? (
                            <span className="rounded-full bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-700">休み</span>
                          ) : (
                            <span className="text-slate-700">
                              {formatTimeOnly(exc.start_time)}〜{formatTimeOnly(exc.end_time)}(休憩{exc.break_minutes}分)
                            </span>
                          )}
                        </td>
                        <td className="px-4 py-3 text-slate-500">{exc.note ?? "—"}</td>
                        <td className="px-4 py-3 text-right">
                          <button
                            onClick={() => setModalState({ initial: exc, defaultDate: exc.work_date })}
                            className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                          >
                            編集
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>

            <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
              <h3 className="text-base font-bold text-slate-800">シフトの生成</h3>
              <p className="text-xs text-slate-500">
                週次テンプレート・イレギュラー例外の内容を、対象月の確定シフト(給与・勤怠集計が参照するデータ)に反映します。
                テンプレートまたは例外を変更した後は、この操作を実行してください。
              </p>
              {generateMessage && <p className="text-sm font-medium text-emerald-600">{generateMessage}</p>}
              {generateError && <p className="text-sm font-medium text-red-500">{generateError}</p>}
              <button
                onClick={handleGenerate}
                disabled={isGenerating}
                className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-60"
              >
                {isGenerating ? "生成中…" : `${yearMonth}のシフトを生成`}
              </button>
            </div>
          </>
        )}
      </main>

      {modalState && (
        <ShiftExceptionModal
          employeeId={selectedEmployee}
          officeId={selectedOffice}
          initial={modalState.initial}
          defaultDate={modalState.defaultDate}
          onClose={() => setModalState(null)}
          onSaved={() => {
            setModalState(null);
            setExceptionsReloadToken((t) => t + 1);
          }}
          onDeleted={() => {
            setModalState(null);
            setExceptionsReloadToken((t) => t + 1);
          }}
        />
      )}
    </div>
  );
}
