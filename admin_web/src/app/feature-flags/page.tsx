"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";

type MasterOption = { id: string; name: string };

type FeatureFlag = {
  feature_key: string;
  name: string;
  description: string | null;
  default_enabled: boolean;
};

type OfficeOverride = {
  feature_key: string;
  office_id: string;
  enabled: boolean;
  note: string | null;
};

type ClassOverride = {
  feature_key: string;
  class_id: string;
  enabled: boolean;
  note: string | null;
};

type ChildcareClassOption = { id: string; class_name: string; age_group: string };

// クラス単位の判定はis_guardian_feature_enabled()(保護者アプリ向け機能)のみが参照する。
// guardian_appは施設単位のマスタースイッチ、childcare_operationsは職員側ドメインのため
// クラス設定テーブルには意味を持たない(対象から除外する)。
const CLASS_SCOPED_KEYS = new Set([
  "guardian_notices",
  "guardian_requests",
  "family_daily_report",
  "communication_book",
  "class_photos",
  "attendance_qr",
]);

export default function FeatureFlagsPage() {
  const [canManage, setCanManage] = useState<boolean | null>(null);

  const [flags, setFlags] = useState<FeatureFlag[]>([]);
  const [flagsError, setFlagsError] = useState<string | null>(null);

  const [offices, setOffices] = useState<MasterOption[]>([]);
  const [selectedOfficeId, setSelectedOfficeId] = useState("");

  const [officeOverrides, setOfficeOverrides] = useState<Record<string, OfficeOverride>>({});
  const [classes, setClasses] = useState<ChildcareClassOption[]>([]);
  const [selectedClassId, setSelectedClassId] = useState("");
  const [classOverrides, setClassOverrides] = useState<Record<string, ClassOverride>>({});

  const [reloadToken, setReloadToken] = useState(0);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    // 219: 機能フラグ管理は統括園長以上(system_admin+executive_director)
    supabase.rpc("is_executive_director_or_admin").then(({ data, error }) => {
      setCanManage(error ? false : Boolean(data));
    });
  }, []);

  useEffect(() => {
    if (!canManage) return;
    const supabase = createClient();
    supabase
      .from("feature_flags")
      .select("feature_key, name, description, default_enabled")
      .order("feature_key")
      .then(({ data, error }) => {
        if (error) {
          setFlagsError(error.message);
          return;
        }
        setFlags((data ?? []) as FeatureFlag[]);
      });
    supabase
      .from("offices")
      .select("id, name")
      .then(({ data, error }) => {
        if (error) return;
        const list = (data ?? []) as MasterOption[];
        setOffices(list);
        if (list.length > 0) setSelectedOfficeId((prev) => prev || list[0].id);
      });
  }, [canManage]);

  useEffect(() => {
    if (!canManage || !selectedOfficeId) return;
    const supabase = createClient();
    supabase
      .from("feature_flag_office_overrides")
      .select("feature_key, office_id, enabled, note")
      .eq("office_id", selectedOfficeId)
      .then(({ data, error }) => {
        if (error) return;
        const map: Record<string, OfficeOverride> = {};
        for (const row of (data ?? []) as OfficeOverride[]) map[row.feature_key] = row;
        setOfficeOverrides(map);
      });
    supabase
      .from("childcare_classes")
      .select("id, class_name, age_group")
      .eq("office_id", selectedOfficeId)
      .order("class_name")
      .then(({ data, error }) => {
        if (error) return;
        const list = (data ?? []) as ChildcareClassOption[];
        setClasses(list);
        setSelectedClassId(list.length > 0 ? list[0].id : "");
      });
  }, [canManage, selectedOfficeId, reloadToken]);

  useEffect(() => {
    function clearClassOverrides() {
      setClassOverrides({});
    }
    if (!canManage || !selectedClassId) {
      clearClassOverrides();
      return;
    }
    const supabase = createClient();
    supabase
      .from("feature_flag_class_overrides")
      .select("feature_key, class_id, enabled, note")
      .eq("class_id", selectedClassId)
      .then(({ data, error }) => {
        if (error) return;
        const map: Record<string, ClassOverride> = {};
        for (const row of (data ?? []) as ClassOverride[]) map[row.feature_key] = row;
        setClassOverrides(map);
      });
  }, [canManage, selectedClassId, reloadToken]);

  async function toggleOfficeOverride(featureKey: string, nextEnabled: boolean) {
    if (!selectedOfficeId) return;
    setActionError(null);
    setSavingKey(`office:${featureKey}`);
    const supabase = createClient();
    const currentNote = officeOverrides[featureKey]?.note ?? null;
    const { error } = await supabase.rpc("set_guardian_feature_office_override", {
      p_feature_key: featureKey,
      p_office_id: selectedOfficeId,
      p_enabled: nextEnabled,
      p_note: currentNote,
    });
    setSavingKey(null);
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function toggleClassOverride(featureKey: string, nextEnabled: boolean) {
    if (!selectedClassId) return;
    setActionError(null);
    setSavingKey(`class:${featureKey}`);
    const supabase = createClient();
    const currentNote = classOverrides[featureKey]?.note ?? null;
    const { error } = await supabase.rpc("set_guardian_feature_class_override", {
      p_feature_key: featureKey,
      p_class_id: selectedClassId,
      p_enabled: nextEnabled,
      p_note: currentNote,
    });
    setSavingKey(null);
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  if (canManage === null) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-400">読み込み中…</div>
      </div>
    );
  }

  if (!canManage) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">この画面を利用する権限がありません。</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">機能フラグ管理(段階公開)</h2>
        <p className="text-sm text-slate-500">
          施設単位・クラス単位で機能のON/OFFを設定します。優先順位は「クラス設定 → 施設設定 →
          既定値」です。既定値はすべてOFFのため、施設側で明示的にONにするまで保護者アプリの該当機能は表示されません。
        </p>

        {flagsError && <p className="text-sm font-medium text-red-500">{flagsError}</p>}
        {actionError && <p className="text-sm font-medium text-red-500">{actionError}</p>}

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOfficeId}
              onChange={(e) => setSelectedOfficeId(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">施設単位の設定</h3>
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">機能</th>
                  <th className="px-4 py-3">説明</th>
                  <th className="px-4 py-3">状態</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody>
                {flags.map((flag) => {
                  const override = officeOverrides[flag.feature_key];
                  const effective = override?.enabled ?? flag.default_enabled;
                  const isSaving = savingKey === `office:${flag.feature_key}`;
                  return (
                    <tr key={flag.feature_key} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                      <td className="px-4 py-3 font-medium text-slate-800">{flag.name}</td>
                      <td className="px-4 py-3 text-slate-500">{flag.description ?? "—"}</td>
                      <td className="px-4 py-3">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                            effective ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-500"
                          }`}
                        >
                          {effective ? "ON" : "OFF"}
                        </span>
                        {!override && <span className="ml-2 text-xs text-slate-400">(既定値のまま)</span>}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <button
                          onClick={() => toggleOfficeOverride(flag.feature_key, !effective)}
                          disabled={isSaving}
                          className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-50"
                        >
                          {isSaving ? "保存中…" : effective ? "OFFにする" : "ONにする"}
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>

        <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">クラス単位の設定(保護者アプリ機能のみ)</h3>
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">クラス</label>
            <select
              value={selectedClassId}
              onChange={(e) => setSelectedClassId(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {classes.length === 0 && <option value="">クラスがありません</option>}
              {classes.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.class_name}({c.age_group})
                </option>
              ))}
            </select>
          </div>

          {selectedClassId && (
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                    <th className="px-4 py-3">機能</th>
                    <th className="px-4 py-3">状態(このクラス)</th>
                    <th className="px-4 py-3" />
                  </tr>
                </thead>
                <tbody>
                  {flags
                    .filter((f) => CLASS_SCOPED_KEYS.has(f.feature_key))
                    .map((flag) => {
                      const override = classOverrides[flag.feature_key];
                      const officeOverride = officeOverrides[flag.feature_key];
                      const effective = override?.enabled ?? officeOverride?.enabled ?? flag.default_enabled;
                      const isSaving = savingKey === `class:${flag.feature_key}`;
                      return (
                        <tr
                          key={flag.feature_key}
                          className="border-b border-slate-100 last:border-0 hover:bg-slate-50"
                        >
                          <td className="px-4 py-3 font-medium text-slate-800">{flag.name}</td>
                          <td className="px-4 py-3">
                            <span
                              className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                                effective ? "bg-emerald-50 text-emerald-700" : "bg-slate-100 text-slate-500"
                              }`}
                            >
                              {effective ? "ON" : "OFF"}
                            </span>
                            {!override && <span className="ml-2 text-xs text-slate-400">(施設設定を継承)</span>}
                          </td>
                          <td className="px-4 py-3 text-right">
                            <button
                              onClick={() => toggleClassOverride(flag.feature_key, !effective)}
                              disabled={isSaving}
                              className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100 disabled:opacity-50"
                            >
                              {isSaving ? "保存中…" : effective ? "OFFにする" : "ONにする"}
                            </button>
                          </td>
                        </tr>
                      );
                    })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}
