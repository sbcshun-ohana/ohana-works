"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

const SLOTS: { key: string; label: string }[] = [
  { key: "am_snack", label: "朝おやつ" },
  { key: "lunch", label: "昼食" },
  { key: "pm_snack", label: "午後おやつ" },
];

type BoardRow = {
  row_key: string;
  row_label: string;
  row_type: string;
  sort_order: number;
  meal_slot: string;
  child_count: number;
  staff_count: number;
  is_confirmed: boolean;
  confirmed_by_name: string | null;
};
type SpecialChild = {
  child_id: string;
  child_name: string;
  class_name: string | null;
  handling: string | null;
  elimination_targets: string[] | null;
};
type MealChange = {
  id: string;
  row_label: string | null;
  meal_slot: string;
  field: string;
  old_count: number;
  new_count: number;
  changed_by_name: string | null;
  changed_at: string;
  acknowledged_at: string | null;
};

type PivotRow = {
  row_key: string;
  row_label: string;
  row_type: string;
  sort_order: number;
  is_confirmed: boolean;
  confirmed_by_name: string | null;
  cells: Record<string, { child: number; staff: number } | undefined>;
};
type Adjustment = {
  id: string;
  row_key: string;
  row_label: string | null;
  meal_slot: string;
  field: string;
  delta: number;
  note: string | null;
  created_by_name: string | null;
  updated_at: string;
};

function todayStr(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

function ChildcareMealBoardContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const [businessDate, setBusinessDate] = useState(todayStr());
  const [board, setBoard] = useState<BoardRow[]>([]);
  const [special, setSpecial] = useState<SpecialChild[]>([]);
  const [changes, setChanges] = useState<MealChange[]>([]);
  const [adjustments, setAdjustments] = useState<Adjustment[]>([]);
  const [adjRow, setAdjRow] = useState("");
  const [adjSlot, setAdjSlot] = useState("lunch");
  const [adjDelta, setAdjDelta] = useState("1");
  const [adjNote, setAdjNote] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);

  useEffect(() => {
    function begin() {
      if (!selectedOffice) return null;
      setIsLoading(true);
      setErr(null);
      return createClient();
    }
    const supabase = begin();
    if (!supabase) return;
    void supabase
      .rpc("fetch_meal_board", { p_office_id: selectedOffice, p_business_date: businessDate })
      .then(({ data, error }) => {
        setIsLoading(false);
        if (error) setErr(error.message);
        else setBoard((data ?? []) as BoardRow[]);
      });
    void supabase
      .rpc("fetch_daily_elimination_for_office", { p_office_id: selectedOffice, p_business_date: businessDate })
      .then(({ data }) => setSpecial((data ?? []) as SpecialChild[]));
    void supabase
      .rpc("fetch_meal_changes", { p_office_id: selectedOffice, p_business_date: businessDate })
      .then(({ data }) => setChanges((data ?? []) as MealChange[]));
    void supabase
      .rpc("fetch_meal_adjustments", { p_office_id: selectedOffice, p_business_date: businessDate })
      .then(({ data }) => setAdjustments((data ?? []) as Adjustment[]));
  }, [selectedOffice, businessDate, reloadToken]);

  const run = useCallback(
    async (fn: (s: ReturnType<typeof createClient>) => Promise<{ error: { message: string } | null }>, ok: string) => {
      setBusy(true);
      const { error } = await fn(createClient());
      setBusy(false);
      if (error) {
        alert(`操作できません: ${error.message}`);
        return;
      }
      if (ok) alert(ok);
      setReloadToken((t) => t + 1);
    },
    [],
  );

  // ピボット: row_key ごとに 3区分をまとめる。
  const pivotMap = new Map<string, PivotRow>();
  for (const b of board) {
    let p = pivotMap.get(b.row_key);
    if (!p) {
      p = {
        row_key: b.row_key,
        row_label: b.row_label,
        row_type: b.row_type,
        sort_order: b.sort_order,
        is_confirmed: b.is_confirmed,
        confirmed_by_name: b.confirmed_by_name,
        cells: {},
      };
      pivotMap.set(b.row_key, p);
    }
    p.cells[b.meal_slot] = { child: b.child_count, staff: b.staff_count };
    if (b.is_confirmed) {
      p.is_confirmed = true;
      p.confirmed_by_name = b.confirmed_by_name;
    }
  }
  const pivot = [...pivotMap.values()].sort((a, b) => a.sort_order - b.sort_order);

  // 合計(提供数=児童行の合計、職員=職員行の合計)。
  const totals: Record<string, { child: number; staff: number }> = {};
  for (const s of SLOTS) totals[s.key] = { child: 0, staff: 0 };
  for (const p of pivot) {
    for (const s of SLOTS) {
      const c = p.cells[s.key];
      if (!c) continue;
      if (p.row_type === "staff") totals[s.key].staff += c.staff;
      else totals[s.key].child += c.child;
    }
  }

  function submitAdjustment() {
    if (!adjRow) {
      alert("行区分を選んでください");
      return;
    }
    const row = pivot.find((p) => p.row_key === adjRow);
    const field = row?.row_type === "staff" ? "staff" : "child";
    const delta = Number(adjDelta);
    if (!Number.isInteger(delta) || delta === 0) {
      alert("増減は0以外の整数で入力してください（例: 1 / -1）");
      return;
    }
    void run(async (s) => {
      const { error } = await s.rpc("set_meal_adjustment", {
        p_office_id: selectedOffice,
        p_business_date: businessDate,
        p_row_key: adjRow,
        p_meal_slot: adjSlot,
        p_field: field,
        p_delta: delta,
        p_note: adjNote || null,
      });
      return { error };
    }, "事前調整を登録しました");
    setAdjNote("");
  }

  function removeAdjustment(a: Adjustment) {
    void run(async (s) => {
      const { error } = await s.rpc("set_meal_adjustment", {
        p_office_id: selectedOffice,
        p_business_date: businessDate,
        p_row_key: a.row_key,
        p_meal_slot: a.meal_slot,
        p_field: a.field,
        p_delta: 0,
        p_note: null,
      });
      return { error };
    }, "");
  }

  function changeCell(p: PivotRow, slot: string) {
    const field = p.row_type === "staff" ? "staff" : "child";
    const cur = p.cells[slot];
    const cof = field === "staff" ? cur?.staff ?? 0 : cur?.child ?? 0;
    const input = window.prompt(`${p.row_label} / ${SLOTS.find((s) => s.key === slot)?.label} の人数を変更`, String(cof));
    if (input === null) return;
    const n = Number(input);
    if (!Number.isInteger(n) || n < 0) {
      alert("0以上の整数を入力してください");
      return;
    }
    void run(async (s) => {
      const { error } = await s.rpc("change_meal_row", {
        p_office_id: selectedOffice,
        p_business_date: businessDate,
        p_row_key: p.row_key,
        p_meal_slot: slot,
        p_field: field,
        p_new_count: n,
      });
      return { error };
    }, "変更しました");
  }

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">保育業務の施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }
  if (offices !== null && offices.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">保育業務機能が有効な施設がありません。</div>
      </div>
    );
  }

  const elimination = special.filter((s) => s.handling === "elimination");
  const bento = special.filter((s) => s.handling === "bento");
  const hold = special.filter((s) => s.handling === "hold");

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-5 p-6">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-slate-800">食数ボード</h2>
          <div className="flex items-center gap-3">
            <input
              type="date"
              value={businessDate}
              onChange={(e) => setBusinessDate(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm"
            />
            <button
              disabled={busy}
              onClick={() =>
                run(async (s) => {
                  const { error } = await s.rpc("compute_meal_counts", {
                    p_office_id: selectedOffice,
                    p_business_date: businessDate,
                  });
                  return { error };
                }, "再算出しました")
              }
              className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-50"
            >
              再算出
            </button>
          </div>
        </div>
        <p className="text-xs text-slate-400">
          9:31に自動算出された暫定値です。各クラスが確認して「承認」で確定。変更期限=昼食10:00 / 午後おやつ14:00 / 朝おやつ9:30。
        </p>

        {err && <p className="text-sm font-medium text-red-500">{err}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-slate-100 text-xs text-slate-400">
              <tr>
                <th className="px-3 py-2">区分</th>
                {SLOTS.map((s) => (
                  <th key={s.key} className="px-3 py-2 text-center">{s.label}</th>
                ))}
                <th className="px-3 py-2 text-center">確定</th>
                <th className="px-3 py-2" />
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr><td colSpan={SLOTS.length + 3} className="px-3 py-6 text-center text-slate-400">読み込み中…</td></tr>
              )}
              {!isLoading && pivot.length === 0 && (
                <tr><td colSpan={SLOTS.length + 3} className="px-3 py-6 text-center text-slate-400">食数がありません。「再算出」を押してください。</td></tr>
              )}
              {pivot.map((p) => (
                <tr key={p.row_key} className="border-b border-slate-100 odd:bg-slate-50/70">
                  <td className="px-3 py-2 font-medium">{p.row_label}</td>
                  {SLOTS.map((s) => {
                    const c = p.cells[s.key];
                    if (!c) return <td key={s.key} className="px-3 py-2 text-center text-slate-300">—</td>;
                    const val = p.row_type === "staff" ? c.staff : c.child;
                    return (
                      <td key={s.key} className="px-3 py-2 text-center">
                        <button
                          disabled={busy}
                          onClick={() => changeCell(p, s.key)}
                          className="rounded px-2 py-0.5 font-bold text-slate-700 hover:bg-sky-50"
                          title="クリックで変更(期限内)"
                        >
                          {val}
                        </button>
                      </td>
                    );
                  })}
                  <td className="px-3 py-2 text-center">
                    {p.is_confirmed ? (
                      <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-semibold text-emerald-700">確定</span>
                    ) : (
                      <span className="rounded-full bg-orange-100 px-2 py-0.5 text-xs font-semibold text-orange-600">確認中</span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-right">
                    {!p.is_confirmed && (
                      <button
                        disabled={busy}
                        onClick={() =>
                          run(async (s) => {
                            const { error } = await s.rpc("confirm_meal_row", {
                              p_office_id: selectedOffice,
                              p_business_date: businessDate,
                              p_row_key: p.row_key,
                            });
                            return { error };
                          }, "")
                        }
                        className="rounded-lg bg-emerald-600 px-3 py-1 text-xs font-semibold text-white hover:bg-emerald-700 disabled:opacity-50"
                      >
                        承認
                      </button>
                    )}
                  </td>
                </tr>
              ))}
              {pivot.length > 0 && (
                <tr className="border-t-2 border-slate-200 bg-slate-50 font-bold">
                  <td className="px-3 py-2">合計(提供数 / 職員)</td>
                  {SLOTS.map((s) => (
                    <td key={s.key} className="px-3 py-2 text-center">
                      {totals[s.key].child}
                      {totals[s.key].staff > 0 ? ` / 職員${totals[s.key].staff}` : ""}
                    </td>
                  ))}
                  <td colSpan={2} />
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {/* 除去食児(誤配膳防止) */}
        <div className="rounded-2xl bg-white p-4 shadow-sm">
          <h3 className="mb-2 text-sm font-bold text-red-600">共通除去食の対象児({elimination.length}名)</h3>
          {elimination.length === 0 ? (
            <p className="text-sm text-slate-400">対象児はいません</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {elimination.map((s) => (
                <div key={s.child_id} className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm">
                  <span className="font-bold">{s.child_name}</span>
                  {s.class_name ? <span className="text-xs text-slate-500">（{s.class_name}）</span> : null}
                  <span className="ml-2 font-bold text-red-700">除去: {(s.elimination_targets ?? []).join("・")}</span>
                </div>
              ))}
            </div>
          )}
          {(bento.length > 0 || hold.length > 0) && (
            <div className="mt-3 flex flex-wrap gap-4 text-xs text-slate-600">
              {bento.length > 0 && <div>弁当持参: {bento.map((s) => s.child_name).join("、")}</div>}
              {hold.length > 0 && <div>給食開始保留: {hold.map((s) => s.child_name).join("、")}</div>}
            </div>
          )}
        </div>

        {/* 事前調整(前日までの増減) */}
        <div className="rounded-2xl bg-white p-4 shadow-sm">
          <h3 className="mb-1 text-sm font-bold text-slate-700">事前調整(前日までの増減)</h3>
          <p className="mb-3 text-xs text-slate-400">
            出欠に紐づかない食数の増減(行事・来客・特別対応など)を事前に登録します。自動算出に加算され、当日の再算出でも保持されます(確定済みの行は除く)。欠席予定はデイリーボードの欠席登録をご利用ください。
          </p>
          <div className="mb-3 flex flex-wrap items-end gap-2">
            <label className="text-xs text-slate-500">
              区分
              <select
                value={adjRow}
                onChange={(e) => {
                  setAdjRow(e.target.value);
                  const r = pivot.find((p) => p.row_key === e.target.value);
                  if (r && r.cells[adjSlot] === undefined) {
                    const first = SLOTS.find((s) => r.cells[s.key] !== undefined);
                    if (first) setAdjSlot(first.key);
                  }
                }}
                className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
              >
                <option value="">選択</option>
                {pivot.map((p) => (
                  <option key={p.row_key} value={p.row_key}>{p.row_label}</option>
                ))}
              </select>
            </label>
            <label className="text-xs text-slate-500">
              食事
              <select
                value={adjSlot}
                onChange={(e) => setAdjSlot(e.target.value)}
                className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
              >
                {SLOTS.filter((s) => {
                  const r = pivot.find((p) => p.row_key === adjRow);
                  return !r || r.cells[s.key] !== undefined;
                }).map((s) => (
                  <option key={s.key} value={s.key}>{s.label}</option>
                ))}
              </select>
            </label>
            <label className="text-xs text-slate-500">
              増減
              <input
                type="number"
                value={adjDelta}
                onChange={(e) => setAdjDelta(e.target.value)}
                className="mt-0.5 block w-20 rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
              />
            </label>
            <label className="flex-1 text-xs text-slate-500">
              メモ(任意)
              <input
                value={adjNote}
                onChange={(e) => setAdjNote(e.target.value)}
                placeholder="例: 行事で来客+1"
                className="mt-0.5 block w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
              />
            </label>
            <button
              disabled={busy}
              onClick={submitAdjustment}
              className="rounded-lg bg-sky-600 px-4 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-50"
            >
              登録
            </button>
          </div>
          {adjustments.length === 0 ? (
            <p className="text-sm text-slate-400">事前調整はありません</p>
          ) : (
            <ul className="divide-y divide-slate-100">
              {adjustments.map((a) => (
                <li key={a.id} className="flex items-center gap-3 py-2 text-sm">
                  <span className="font-medium">{a.row_label ?? a.row_key}</span>
                  <span>{SLOTS.find((s) => s.key === a.meal_slot)?.label}</span>
                  <span>{a.field === "staff" ? "職員" : "園児"}</span>
                  <span className={`font-bold ${a.delta > 0 ? "text-emerald-600" : "text-red-600"}`}>
                    {a.delta > 0 ? `+${a.delta}` : a.delta}
                  </span>
                  {a.note ? <span className="text-xs text-slate-400">{a.note}</span> : null}
                  <button onClick={() => removeAdjustment(a)} className="ml-auto text-xs text-red-500 hover:underline">
                    削除
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* 変更履歴 */}
        {changes.length > 0 && (
          <div className="rounded-2xl bg-white p-4 shadow-sm">
            <h3 className="mb-2 text-sm font-bold text-slate-700">本日の変更履歴</h3>
            <ul className="space-y-1 text-sm">
              {changes.map((ch) => (
                <li key={ch.id} className="flex flex-wrap gap-2 text-slate-600">
                  <span className="text-xs text-slate-400">{new Date(ch.changed_at).toLocaleTimeString("ja-JP")}</span>
                  <span>{ch.row_label ?? ch.meal_slot}</span>
                  <span>{SLOTS.find((s) => s.key === ch.meal_slot)?.label}</span>
                  <span className="font-bold">
                    {ch.field === "staff" ? "職員" : "園児"} {ch.old_count} → {ch.new_count}
                  </span>
                  {ch.changed_by_name ? <span className="text-xs text-slate-400">（{ch.changed_by_name}）</span> : null}
                </li>
              ))}
            </ul>
          </div>
        )}
      </main>
    </div>
  );
}

export default function ChildcareMealBoardPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareMealBoardContent />
    </Suspense>
  );
}
