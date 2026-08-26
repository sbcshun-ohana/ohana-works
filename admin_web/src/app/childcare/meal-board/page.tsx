"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

const SLOTS: { key: string; label: string }[] = [
  { key: "am_snack", label: "午前おやつ" },
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
  requires_plating: boolean;
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
  requires_plating: boolean;
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
  // 本日の献立(267 fetch_published_menu_day・公開済み)。厨房・発注の参考に併記。
  const [menuDay, setMenuDay] = useState<
    { food_type: string; removal_kind: string | null; meal_slot: string; menu_text: string | null; removal_note: string | null }[]
  >([]);
  // 給食停止中(弁当持参・アレルギー確認中)の園児。厨房が提供対象外を把握できるよう先頭に表示(271)。
  const [suspended, setSuspended] = useState<{ child_id: string; child_name: string; note: string | null }[]>([]);
  // Mahalo Station固有(340): 牛乳本数(手入力)・明日のおやつ(翌日登園予定数)
  const [station, setStation] = useState<{ is_station: boolean; milk_bottles: number | null; next_day_snack: number } | null>(null);
  const [milkInput, setMilkInput] = useState("");
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
    void supabase
      .rpc("fetch_published_menu_day", { p_office_id: selectedOffice, p_menu_date: businessDate })
      .then(({ data }) => setMenuDay((data ?? []) as typeof menuDay));
    void supabase
      .rpc("fetch_meal_suspended_children_for_office", { p_office_id: selectedOffice })
      .then(({ data }) => setSuspended((data ?? []) as { child_id: string; child_name: string; note: string | null }[]));
    void supabase
      .rpc("fetch_meal_station_extras", { p_office: selectedOffice, p_date: businessDate })
      .then(({ data }) => {
        const s = (data?.[0] ?? null) as { is_station: boolean; milk_bottles: number | null; next_day_snack: number } | null;
        setStation(s);
        setMilkInput(s?.milk_bottles != null ? String(s.milk_bottles) : "");
      });
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
        requires_plating: b.requires_plating,
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
      <MealSubNav />
      <main className="flex-1 space-y-5 p-6">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-slate-800">給食発注数</h2>
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
            {pivot.length > 0 && (pivot.every((p) => p.is_confirmed) ? (
              <button disabled={busy}
                onClick={() => run(async (s) => { const { error } = await s.rpc("unconfirm_meal_day", { p_office_id: selectedOffice, p_business_date: businessDate }); return { error }; }, "承認を解除しました")}
                className="rounded-lg border border-emerald-300 px-3 py-1.5 text-sm font-semibold text-emerald-700 hover:bg-emerald-50 disabled:opacity-50">✓ 承認済み(解除)</button>
            ) : (
              <button disabled={busy}
                onClick={() => run(async (s) => { const { error } = await s.rpc("confirm_meal_day", { p_office_id: selectedOffice, p_business_date: businessDate }); return { error }; }, "承認しました")}
                className="rounded-lg bg-emerald-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50">この日を承認(一括)</button>
            ))}
          </div>
        </div>
        <p className="text-xs text-slate-400">
          9:31に自動算出された暫定値です。「この日を承認(一括)」で確定(クラスごとの承認は不要)。変更期限=昼食10:00 / 午後おやつ14:00 / 午前おやつ9:30。承認前でも厨房ビューには表示されます。
        </p>

        {station?.is_station && (
          <div className="flex flex-wrap items-end gap-4 rounded-2xl border border-sky-200 bg-sky-50/50 p-4 shadow-sm">
            <div>
              <div className="text-xs font-semibold text-slate-500">明日のおやつ(翌日の登園予定数)</div>
              <div className="text-2xl font-bold text-slate-800 tabular-nums">{station.next_day_snack}<span className="ml-1 text-sm font-normal">名</span></div>
            </div>
            <div className="flex items-end gap-2">
              <label className="text-xs font-semibold text-slate-500">
                <span className="mb-1 block">今日の牛乳(本)</span>
                <input
                  type="number" min={0} value={milkInput}
                  onChange={(e) => setMilkInput(e.target.value)}
                  className="w-24 rounded-lg border border-slate-300 px-3 py-1.5 text-sm tabular-nums"
                />
              </label>
              <button
                disabled={busy}
                onClick={() => run(async (s) => {
                  const { error } = await s.rpc("set_milk_bottles", {
                    p_office: selectedOffice, p_date: businessDate,
                    p_count: milkInput === "" ? null : Number(milkInput),
                  });
                  return { error };
                }, "牛乳本数を保存しました")}
                className="rounded-lg bg-sky-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-50"
              >保存</button>
            </div>
          </div>
        )}

        {err && <p className="text-sm font-medium text-red-500">{err}</p>}

        {suspended.length > 0 && (
          <div className="rounded-2xl border border-red-200 bg-red-50 p-4 shadow-sm">
            <h3 className="text-sm font-bold text-red-700">🍱 給食停止中(弁当持参・アレルギー確認中) {suspended.length}名</h3>
            <p className="mt-1 text-xs text-red-600">この園児には給食を提供しないでください(食数から除外)。</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {suspended.map((s) => (
                <span key={s.child_id} className="rounded-lg bg-white px-3 py-1 text-sm font-semibold text-red-700 shadow-sm">
                  {s.child_name}
                  {s.note ? <span className="ml-1 text-xs font-normal text-slate-500">({s.note})</span> : ""}
                </span>
              ))}
            </div>
          </div>
        )}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="w-full text-left text-sm">
            <thead className="border-b border-slate-100 text-xs text-slate-400">
              <tr>
                <th className="px-3 py-2">区分</th>
                {SLOTS.map((s) => (
                  <th key={s.key} className="px-3 py-2 text-center">{s.label}</th>
                ))}
                <th className="px-3 py-2 text-center">確定</th>
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr><td colSpan={SLOTS.length + 3} className="px-3 py-6 text-center text-slate-400">読み込み中…</td></tr>
              )}
              {!isLoading && pivot.length === 0 && (
                <tr><td colSpan={SLOTS.length + 2} className="px-3 py-6 text-center text-slate-400">食数がありません。「再算出」を押してください。</td></tr>
              )}
              {pivot.map((p) => (
                <tr key={p.row_key} className="border-b border-slate-100 odd:bg-slate-50/70">
                  <td className="px-3 py-2 font-medium">{p.row_label}</td>
                  {SLOTS.map((s) => {
                    const c = p.cells[s.key];
                    if (!c) return <td key={s.key} className="px-3 py-2 text-center text-slate-300">—</td>;
                    const val = p.row_type === "staff" ? c.staff : c.child;
                    // 盛り付けクラス(大和・児童行)の職員配分は現場(iPad)で入力。adminは読み取り表示のみ(午前おやつを除く)。
                    const showPlatingStaff = p.requires_plating && p.row_type !== "staff" && s.key !== "am_snack" && c.staff > 0;
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
                        {showPlatingStaff && (
                          <div className="text-[10px] font-semibold text-slate-400" title="盛り付け用の職員配分(iPadで入力)">職{c.staff}</div>
                        )}
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
                  <td />
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {/* 本日の献立(公開済み・267)。厨房・発注の参考に併記。 */}
        <div className="rounded-2xl bg-white p-4 shadow-sm">
          <div className="mb-2 flex items-center justify-between">
            <h3 className="text-sm font-bold text-slate-700">本日の献立</h3>
            <a
              href={`/childcare/menus/day?office=${selectedOffice}&date=${businessDate}`}
              className="text-xs font-semibold text-sky-600 hover:underline"
            >日別ビューで見る →</a>
          </div>
          {menuDay.filter((m) => !m.removal_kind).length === 0 ? (
            <p className="text-sm text-slate-400">この日の公開済み献立はありません(献立→編集→公開で表示)。</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="text-left text-xs font-semibold text-slate-500">
                    <th className="px-2 py-1">食種＼区分</th>
                    <th className="px-2 py-1">午前おやつ</th>
                    <th className="px-2 py-1">昼食</th>
                    <th className="px-2 py-1">午後おやつ</th>
                  </tr>
                </thead>
                <tbody>
                  {(
                    [
                      // 食数ボードの給食段階と統一: 上から 後期 / 完了期 / 幼児食。幼児食は over3/under3 を統合。
                      ["後期食", ["weaning_late"]],
                      ["完了期食", ["weaning_final"]],
                      ["幼児食", ["regular_over3", "regular_under3"]],
                    ] as const
                  )
                    .filter(([, srcs]) => menuDay.some((m) => !m.removal_kind && m.menu_text && srcs.some((ft) => ft === m.food_type)))
                    .map(([label, srcs]) => (
                      <tr key={label} className="border-t border-slate-100">
                        <td className="px-2 py-1 font-medium text-slate-700">{label}</td>
                        {(["am_snack", "lunch", "pm_snack"] as const).map((slot) => (
                          <td key={slot} className="whitespace-pre-wrap px-2 py-1 text-slate-600">
                            {srcs.map((ft) => menuDay.find((m) => m.food_type === ft && m.meal_slot === slot && !m.removal_kind)?.menu_text).find(Boolean) || "—"}
                          </td>
                        ))}
                      </tr>
                    ))}
                </tbody>
              </table>
              {menuDay.filter((m) => m.removal_kind).length > 0 && (
                <p className="mt-2 text-xs text-amber-700">
                  アレルギー除去食: {Array.from(new Set(menuDay.filter((m) => m.removal_kind).map((m) => m.removal_kind))).join("・")}(詳細は献立の月間一覧)
                </p>
              )}
            </div>
          )}
        </div>

        {/* 除去食児(誤配膳防止) */}
        <div className="rounded-2xl bg-white p-4 shadow-sm">
          <h3 className="mb-2 text-sm font-bold text-red-600">アレルギー除去食の対象児({elimination.length}名)</h3>
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
