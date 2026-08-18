"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import type { SessionIdentity } from "@/lib/types";

type ItemMaster = {
  id: string;
  age_band_code: string;
  domain_code: string;
  excel_domain: string;
  item_name: string;
  observation_point: string | null;
  display_order: number;
  is_active: boolean;
  current_version: number;
  source_ref: number | null;
};

const AGE_BANDS: { code: string; label: string }[] = [
  { code: "M00_05", label: "0〜5か月" },
  { code: "M06_14", label: "6〜14か月" },
  { code: "M15_23", label: "15〜23か月" },
  { code: "AGE_2", label: "2歳児" },
  { code: "AGE_3", label: "3歳児" },
  { code: "AGE_4", label: "4歳児" },
  { code: "AGE_5", label: "5歳児" },
];

const DOMAINS: { code: string; label: string; className: string }[] = [
  { code: "health", label: "健康", className: "bg-rose-100 text-rose-700" },
  { code: "relations", label: "人間関係", className: "bg-amber-100 text-amber-700" },
  { code: "environment", label: "環境", className: "bg-emerald-100 text-emerald-700" },
  { code: "language", label: "言葉", className: "bg-sky-100 text-sky-700" },
  { code: "expression", label: "表現", className: "bg-violet-100 text-violet-700" },
];

const DOMAIN_MAP = Object.fromEntries(DOMAINS.map((d) => [d.code, d]));
const ADMIN_ROLES = new Set(["system_admin", "executive_director", "director", "office_manager"]);

/// 発達記録マスター管理(238)。全社共通の90項目。閲覧=全職員/編集=管理者以上。
/// 編集(項目名・観察ポイント・領域・表示順・有効/無効)は update_development_item_master RPC 経由で
/// 版スナップショットを自動記録する。年齢区分は項目の帰属を定義するため編集不可。
function DevelopmentMastersPageContent() {
  const [items, setItems] = useState<ItemMaster[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const [isAdmin, setIsAdmin] = useState(false);
  const [editTarget, setEditTarget] = useState<ItemMaster | null>(null);

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_session_identity").then(({ data }) => {
      if (Array.isArray(data) && data.length > 0) {
        const me = data[0] as SessionIdentity;
        setIsAdmin(!!me.role_code && ADMIN_ROLES.has(me.role_code));
      }
    });
  }, []);

  useEffect(() => {
    setIsLoading(true);
    setError(null);
    const supabase = createClient();
    supabase
      .from("development_item_masters")
      .select(
        "id, age_band_code, domain_code, excel_domain, item_name, observation_point, display_order, is_active, current_version, source_ref",
      )
      .order("age_band_code")
      .order("display_order")
      .then(({ data, error: err }) => {
        setIsLoading(false);
        if (err) {
          setError(err.message);
          setItems([]);
          return;
        }
        setItems((data ?? []) as ItemMaster[]);
      });
  }, [reloadToken]);

  const byBand = useMemo(() => {
    const map = new Map<string, ItemMaster[]>();
    for (const b of AGE_BANDS) map.set(b.code, []);
    for (const it of items) {
      if (!map.has(it.age_band_code)) map.set(it.age_band_code, []);
      map.get(it.age_band_code)!.push(it);
    }
    return map;
  }, [items]);

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <div>
          <h2 className="text-lg font-bold text-slate-800">発達記録マスター(全90項目)</h2>
          <p className="text-xs text-slate-400">
            全社共通の発達項目マスターです。年齢区分ごとに項目・観察ポイント・領域・表示順を管理します。
            {isAdmin
              ? "編集内容は版として記録されます(管理者以上)。"
              : "閲覧のみ可能です(編集は管理者以上)。"}
          </p>
        </div>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}
        {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}

        {AGE_BANDS.map((band) => {
          const rows = byBand.get(band.code) ?? [];
          if (rows.length === 0) return null;
          return (
            <section key={band.code} className="space-y-2">
              <h3 className="text-sm font-bold text-slate-700">
                {band.label}
                <span className="ml-2 text-xs font-normal text-slate-400">{rows.length}項目</span>
              </h3>
              <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
                <table className="w-full text-left text-sm">
                  <thead className="bg-slate-50 text-xs text-slate-500">
                    <tr>
                      <th className="w-10 px-3 py-2">#</th>
                      <th className="w-20 px-3 py-2">領域</th>
                      <th className="px-3 py-2">項目 / 観察ポイント</th>
                      <th className="w-24 px-3 py-2">状態</th>
                      {isAdmin && <th className="w-16 px-3 py-2"></th>}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {rows.map((it) => {
                      const dom = DOMAIN_MAP[it.domain_code];
                      return (
                        <tr key={it.id} className={it.is_active ? "" : "bg-slate-50/60 text-slate-400"}>
                          <td className="px-3 py-2 text-slate-400">{it.display_order}</td>
                          <td className="px-3 py-2">
                            <span
                              className={`rounded-md px-2 py-0.5 text-xs font-semibold ${dom?.className ?? "bg-slate-100 text-slate-600"}`}
                            >
                              {dom?.label ?? it.domain_code}
                            </span>
                          </td>
                          <td className="px-3 py-2">
                            <p className="font-medium text-slate-800">{it.item_name}</p>
                            {it.observation_point && (
                              <p className="mt-0.5 text-xs text-slate-500">{it.observation_point}</p>
                            )}
                          </td>
                          <td className="px-3 py-2 text-xs">
                            {it.is_active ? (
                              <span className="text-emerald-600">有効</span>
                            ) : (
                              <span className="text-slate-400">無効</span>
                            )}
                            {it.current_version > 1 && (
                              <span className="ml-1 text-slate-400">v{it.current_version}</span>
                            )}
                          </td>
                          {isAdmin && (
                            <td className="px-3 py-2">
                              <button
                                onClick={() => setEditTarget(it)}
                                className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-50"
                              >
                                編集
                              </button>
                            </td>
                          )}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </section>
          );
        })}
      </main>

      {editTarget && (
        <EditModal
          item={editTarget}
          onClose={() => setEditTarget(null)}
          onSaved={() => {
            setEditTarget(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

function EditModal({
  item,
  onClose,
  onSaved,
}: {
  item: ItemMaster;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [itemName, setItemName] = useState(item.item_name);
  const [observation, setObservation] = useState(item.observation_point ?? "");
  const [domain, setDomain] = useState(item.domain_code);
  const [displayOrder, setDisplayOrder] = useState(String(item.display_order));
  const [isActive, setIsActive] = useState(item.is_active);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  async function handleSave() {
    if (!itemName.trim()) {
      setSaveError("項目名は必須です");
      return;
    }
    setIsSaving(true);
    setSaveError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("update_development_item_master", {
      p_item_id: item.id,
      p_item_name: itemName.trim(),
      p_observation_point: observation.trim() || null,
      p_domain_code: domain,
      p_display_order: Number(displayOrder) || item.display_order,
      p_is_active: isActive,
    });
    setIsSaving(false);
    if (error) {
      setSaveError(error.message.includes("not authorized") ? "編集は管理者以上のみ可能です" : error.message);
      return;
    }
    onSaved();
  }

  const bandLabel = AGE_BANDS.find((b) => b.code === item.age_band_code)?.label ?? item.age_band_code;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-1 text-base font-bold text-slate-800">発達項目の編集</h2>
        <p className="mb-4 text-xs text-slate-400">
          年齢区分: {bandLabel}(区分は変更できません)
        </p>

        <div className="space-y-3">
          <label className="block">
            <span className="text-xs font-semibold text-slate-500">項目名</span>
            <input
              value={itemName}
              onChange={(e) => setItemName(e.target.value)}
              className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </label>

          <label className="block">
            <span className="text-xs font-semibold text-slate-500">観察ポイント</span>
            <textarea
              value={observation}
              onChange={(e) => setObservation(e.target.value)}
              rows={3}
              className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </label>

          <div className="flex gap-3">
            <label className="flex-1">
              <span className="text-xs font-semibold text-slate-500">領域</span>
              <select
                value={domain}
                onChange={(e) => setDomain(e.target.value)}
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              >
                {DOMAINS.map((d) => (
                  <option key={d.code} value={d.code}>
                    {d.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="w-28">
              <span className="text-xs font-semibold text-slate-500">表示順</span>
              <input
                type="number"
                value={displayOrder}
                onChange={(e) => setDisplayOrder(e.target.value)}
                className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </label>
          </div>

          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
            この項目を有効にする(無効にすると発達記録の入力候補から外れます)
          </label>
        </div>

        {saveError && <p className="mt-3 text-sm font-medium text-red-500">{saveError}</p>}

        <div className="mt-5 flex justify-end gap-3">
          <button
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            キャンセル
          </button>
          <button
            onClick={handleSave}
            disabled={isSaving}
            className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
          >
            {isSaving ? "保存中…" : "保存する"}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function DevelopmentMastersPage() {
  return (
    <Suspense fallback={null}>
      <DevelopmentMastersPageContent />
    </Suspense>
  );
}
