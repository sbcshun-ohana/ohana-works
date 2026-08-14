"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { useChildcareClass } from "@/hooks/useChildcareClass";
import { currentDate } from "@/lib/datetime";

// 健康チェック(188検温+194排便+199ミルク/食事)。Ohana Kidsの6タブ構成と同等のadmin_web版。
// 縦=園児一覧、タブごとに一覧のまま連続入力。年齢絞り込み(UI側): ミルク=生後18ヶ月未満、
// おやつ/昼食=0・1・2歳児(実年齢3歳未満)。過去日の記録・削除はサーバー側で主任以上に限定。

const TABS = [
  { key: "temp", label: "検温" },
  { key: "toileting", label: "排便" },
  { key: "milk", label: "ミルク" },
  { key: "am_snack", label: "午前おやつ" },
  { key: "lunch", label: "昼食" },
  { key: "pm_snack", label: "午後おやつ" },
] as const;
type TabKey = (typeof TABS)[number]["key"];

const TOILETING_TYPES = ["普通", "軟便", "硬便", "下痢便"];
const MEAL_AMOUNTS = ["完食", "ほとんど", "半分", "少量", "食べず"];
const TEMP_OPTIONS = Array.from({ length: 81 }, (_, i) => (34.0 + i * 0.1).toFixed(1));
const MILK_OPTIONS = Array.from({ length: 30 }, (_, i) => (i + 1) * 10);

type RosterChild = {
  child_id: string;
  display_name: string;
  honorific_suffix: string | null;
  class_name: string | null;
  enrollment_status: string;
};

type TempRecord = { child_id: string; measured_at: string; temperature: number };

type HealthRow = {
  child_id: string;
  birth_date: string;
  toileting_records: { time: string; type: string }[];
  milk_records: { time: string; amount_ml: number }[];
  meal_records: Record<string, string>;
};

function nowHm(): string {
  const n = new Date();
  return `${String(n.getHours()).padStart(2, "0")}:${String(n.getMinutes()).padStart(2, "0")}`;
}

function hm(t: string): string {
  return t.length >= 5 ? t.slice(0, 5) : t;
}

// 対象日時点の月齢(UI絞り込み用)。
function ageMonths(birthDate: string, onDate: string): number {
  const b = new Date(birthDate);
  const d = new Date(onDate);
  let months = (d.getFullYear() - b.getFullYear()) * 12 + (d.getMonth() - b.getMonth());
  if (d.getDate() < b.getDate()) months -= 1;
  return months;
}

function HealthCheckPageContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const { classes, selectedClass, setSelectedClass, selectedClassName } = useChildcareClass(selectedOffice);
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;

  const [businessDate, setBusinessDate] = useState(currentDate());
  const [tab, setTab] = useState<TabKey>("temp");
  const [roster, setRoster] = useState<RosterChild[]>([]);
  const [tempsByChild, setTempsByChild] = useState<Record<string, TempRecord[]>>({});
  const [healthByChild, setHealthByChild] = useState<Record<string, HealthRow>>({});
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const canEdit = businessDate === currentDate() || isManager;

  useEffect(() => {
    function loadAll() {
      if (!selectedOffice) return;
      setIsLoading(true);
      setError(null);
      const supabase = createClient();
      Promise.all([
        supabase.rpc("fetch_children_for_office", { p_office_id: selectedOffice }),
        supabase.rpc("fetch_child_temperatures_for_office", { p_office_id: selectedOffice, p_business_date: businessDate }),
        supabase.rpc("fetch_health_check_for_office", { p_office_id: selectedOffice, p_business_date: businessDate }),
      ]).then(([children, temps, health]) => {
        setIsLoading(false);
        if (children.error || temps.error || health.error) {
          setError(children.error?.message ?? temps.error?.message ?? health.error?.message ?? "取得に失敗しました");
          return;
        }
        setRoster(((children.data ?? []) as RosterChild[]).filter((c) => c.enrollment_status !== "退園済み"));
        const t: Record<string, TempRecord[]> = {};
        for (const r of (temps.data ?? []) as TempRecord[]) {
          (t[r.child_id] ??= []).push(r);
        }
        setTempsByChild(t);
        const h: Record<string, HealthRow> = {};
        for (const r of (health.data ?? []) as HealthRow[]) h[r.child_id] = r;
        setHealthByChild(h);
      });
    }
    loadAll();
  }, [selectedOffice, businessDate, reloadToken]);

  function reload() {
    setReloadToken((v) => v + 1);
  }

  async function call(rpc: string, params: Record<string, unknown>) {
    const { error: e } = await createClient().rpc(rpc, params);
    if (e) {
      setError(`操作に失敗しました(過去日・公開後は主任以上): ${e.message}`);
      return;
    }
    setError(null);
    reload();
  }

  // タブごとの対象園児(年齢絞り込み)。birth_date 不明の児は安全側で表示する。
  const classFiltered = selectedClassName ? roster.filter((c) => c.class_name === selectedClassName) : roster;
  const rows = classFiltered.filter((c) => {
    const b = healthByChild[c.child_id]?.birth_date;
    if (!b) return true;
    const m = ageMonths(b, businessDate);
    if (tab === "milk") return m < 18;
    if (tab === "am_snack" || tab === "lunch" || tab === "pm_snack") return m < 36;
    return true;
  });

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <ChildcareNav />
        <div className="p-8 text-sm text-red-500">保育業務の施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }
  if (offices !== null && offices.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <ChildcareNav />
        <div className="p-8 text-sm text-slate-500">保育業務機能が有効な施設がありません。</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-4 p-6">
        <h2 className="text-lg font-bold text-slate-800">健康チェック</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">クラス</label>
            <select
              value={selectedClass}
              onChange={(e) => setSelectedClass(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="">全クラス</option>
              {classes.map((c) => (
                <option key={c.class_id} value={c.class_id}>
                  {c.class_name}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">対象日</label>
            <input
              type="date"
              value={businessDate}
              onChange={(e) => setBusinessDate(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          {!canEdit && (
            <p className="pb-2 text-xs font-medium text-red-500">過去日の記録・削除は主任以上のみ可能です</p>
          )}
        </div>

        {/* カテゴリ切替タブ(6タブ) */}
        <div className="flex flex-wrap gap-2">
          {TABS.map((t) => (
            <button
              key={t.key}
              onClick={() => setTab(t.key)}
              className={`rounded-full px-4 py-1.5 text-sm font-semibold transition ${
                tab === t.key ? "bg-sky-500 text-white" : "bg-white text-slate-600 shadow-sm hover:bg-sky-50"
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}

        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-4 py-3">園児</th>
                <th className="px-4 py-3">クラス</th>
                <th className="px-4 py-3">記録</th>
                {canEdit && <th className="px-4 py-3">追加</th>}
              </tr>
            </thead>
            <tbody>
              {isLoading && (
                <tr>
                  <td colSpan={canEdit ? 4 : 3} className="px-4 py-6 text-center text-slate-400">
                    読み込み中…
                  </td>
                </tr>
              )}
              {!isLoading && rows.length === 0 && (
                <tr>
                  <td colSpan={canEdit ? 4 : 3} className="px-4 py-6 text-center text-slate-400">
                    対象の園児がいません
                  </td>
                </tr>
              )}
              {!isLoading &&
                rows.map((child) => (
                  <tr key={child.child_id} className="border-b border-slate-100 last:border-0">
                    <td className="px-4 py-3 font-medium text-slate-800">
                      {child.display_name}
                      {child.honorific_suffix ?? ""}
                    </td>
                    <td className="px-4 py-3 text-slate-500">{child.class_name}</td>
                    <td className="px-4 py-3">
                      <RecordsCell
                        tab={tab}
                        child={child}
                        temps={tempsByChild[child.child_id] ?? []}
                        health={healthByChild[child.child_id]}
                        canEdit={canEdit}
                        businessDate={businessDate}
                        onCall={call}
                      />
                    </td>
                    {canEdit && (
                      <td className="px-4 py-3">
                        <AddCell tab={tab} child={child} businessDate={businessDate} onCall={call} />
                      </td>
                    )}
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  );
}

// タブごとの記録表示(チップ+削除)。食事タブは分量トグルボタン。
function RecordsCell({
  tab,
  child,
  temps,
  health,
  canEdit,
  businessDate,
  onCall,
}: {
  tab: TabKey;
  child: RosterChild;
  temps: TempRecord[];
  health: HealthRow | undefined;
  canEdit: boolean;
  businessDate: string;
  onCall: (rpc: string, params: Record<string, unknown>) => Promise<void>;
}) {
  const chipClass = "inline-flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700";
  const delBtn = "text-slate-400 hover:text-red-500";

  if (tab === "temp") {
    if (temps.length === 0) return <span className="text-xs text-slate-400">検温 未記録</span>;
    return (
      <div className="flex flex-wrap gap-1.5">
        {temps.map((r, i) => (
          <span key={i} className={chipClass}>
            {hm(r.measured_at)} {r.temperature}℃
            {canEdit && (
              <button
                className={delBtn}
                onClick={() =>
                  onCall("delete_child_temperature", {
                    p_child_id: child.child_id,
                    p_business_date: businessDate,
                    p_measured_at: hm(r.measured_at),
                  })
                }
              >
                ×
              </button>
            )}
          </span>
        ))}
      </div>
    );
  }
  if (tab === "toileting") {
    const recs = health?.toileting_records ?? [];
    if (recs.length === 0) return <span className="text-xs text-slate-400">排便 未記録</span>;
    return (
      <div className="flex flex-wrap gap-1.5">
        {recs.map((r, i) => (
          <span key={i} className={chipClass}>
            {r.time} {r.type}
            {canEdit && (
              <button
                className={delBtn}
                onClick={() =>
                  onCall("delete_toileting_record", {
                    p_child_id: child.child_id,
                    p_business_date: businessDate,
                    p_index: i,
                  })
                }
              >
                ×
              </button>
            )}
          </span>
        ))}
      </div>
    );
  }
  if (tab === "milk") {
    const recs = health?.milk_records ?? [];
    if (recs.length === 0) return <span className="text-xs text-slate-400">ミルク 未記録</span>;
    return (
      <div className="flex flex-wrap gap-1.5">
        {recs.map((r, i) => (
          <span key={i} className={chipClass}>
            {r.time} {r.amount_ml}ml
            {canEdit && (
              <button
                className={delBtn}
                onClick={() =>
                  onCall("delete_milk_record", {
                    p_child_id: child.child_id,
                    p_business_date: businessDate,
                    p_index: i,
                  })
                }
              >
                ×
              </button>
            )}
          </span>
        ))}
      </div>
    );
  }
  // 食事(am_snack/lunch/pm_snack): 分量トグル。選択中を再クリックで未記録に戻す。
  const current = health?.meal_records?.[tab];
  return (
    <div className="flex flex-wrap gap-1.5">
      {MEAL_AMOUNTS.map((a) => (
        <button
          key={a}
          disabled={!canEdit}
          onClick={() =>
            onCall("set_meal_record", {
              p_child_id: child.child_id,
              p_business_date: businessDate,
              p_slot: tab,
              p_amount: current === a ? null : a,
            })
          }
          className={`rounded-full px-3 py-1 text-xs font-semibold transition ${
            current === a
              ? "bg-emerald-500 text-white"
              : "bg-slate-100 text-slate-600 hover:bg-emerald-50 disabled:opacity-50"
          }`}
        >
          {a}
        </button>
      ))}
    </div>
  );
}

// タブごとの追加フォーム(時刻+値)。食事タブは記録セル側のトグルで完結するため非表示。
function AddCell({
  tab,
  child,
  businessDate,
  onCall,
}: {
  tab: TabKey;
  child: RosterChild;
  businessDate: string;
  onCall: (rpc: string, params: Record<string, unknown>) => Promise<void>;
}) {
  const [time, setTime] = useState(nowHm());
  const [temp, setTemp] = useState("36.5");
  const [type, setType] = useState(TOILETING_TYPES[0]);
  const [amount, setAmount] = useState(100);

  const inputClass = "rounded-lg border border-slate-300 px-2 py-1 text-xs focus:border-sky-400 focus:outline-none";
  const addBtn = "rounded-lg border border-sky-300 bg-sky-50 px-2.5 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-100";

  if (tab === "am_snack" || tab === "lunch" || tab === "pm_snack") return null;

  return (
    <div className="flex items-center gap-1.5">
      <input type="time" value={time} onChange={(e) => setTime(e.target.value)} className={inputClass} />
      {tab === "temp" && (
        <select value={temp} onChange={(e) => setTemp(e.target.value)} className={inputClass}>
          {TEMP_OPTIONS.map((v) => (
            <option key={v} value={v}>
              {v}℃
            </option>
          ))}
        </select>
      )}
      {tab === "toileting" && (
        <select value={type} onChange={(e) => setType(e.target.value)} className={inputClass}>
          {TOILETING_TYPES.map((v) => (
            <option key={v} value={v}>
              {v}
            </option>
          ))}
        </select>
      )}
      {tab === "milk" && (
        <select value={amount} onChange={(e) => setAmount(Number(e.target.value))} className={inputClass}>
          {MILK_OPTIONS.map((v) => (
            <option key={v} value={v}>
              {v}ml
            </option>
          ))}
        </select>
      )}
      <button
        className={addBtn}
        onClick={() => {
          if (!time) return;
          if (tab === "temp") {
            void onCall("record_child_temperature", {
              p_child_id: child.child_id,
              p_business_date: businessDate,
              p_measured_at: time,
              p_temperature: Number(temp),
            });
          } else if (tab === "toileting") {
            void onCall("add_toileting_record", {
              p_child_id: child.child_id,
              p_business_date: businessDate,
              p_time: time,
              p_type: type,
            });
          } else if (tab === "milk") {
            void onCall("add_milk_record", {
              p_child_id: child.child_id,
              p_business_date: businessDate,
              p_time: time,
              p_amount_ml: amount,
            });
          }
        }}
      >
        追加
      </button>
    </div>
  );
}

export default function HealthCheckPage() {
  return (
    <Suspense>
      <HealthCheckPageContent />
    </Suspense>
  );
}
