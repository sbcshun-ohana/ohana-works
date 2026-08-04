"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { ChildMasterRow, ChildTherapySetting, TherapyProvider } from "@/lib/types";

type Props = {
  row: ChildMasterRow;
  officeName: string;
  onClose: () => void;
};

/**
 * 療育設定モーダル(§5.1)。対象園児×事業所×適用期間を複数行で管理(主任以上)。
 * 事業者マスタの最小限の登録手段(＋事業者を追加=統括園長以上)も同居させる。
 */
export function ChildTherapySettingModal({ row, officeName, onClose }: Props) {
  const [providers, setProviders] = useState<TherapyProvider[]>([]);
  const [settings, setSettings] = useState<ChildTherapySetting[]>([]);
  const [activeQrs, setActiveQrs] = useState<{ id: string; provider_id: string }[]>([]);
  const [providerId, setProviderId] = useState("");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [newProviderName, setNewProviderName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    function load() {
      const supabase = createClient();
      supabase
        .from("therapy_providers")
        .select("id, name, is_active")
        .eq("is_active", true)
        .order("name")
        .then(({ data }) => setProviders((data ?? []) as TherapyProvider[]));
      supabase
        .from("child_therapy_settings")
        .select("id, provider_id, start_date, end_date, therapy_providers(name)")
        .eq("child_id", row.child_id)
        .order("start_date", { ascending: false })
        .then(({ data }) => setSettings((data ?? []) as unknown as ChildTherapySetting[]));
      supabase
        .from("therapy_outing_qr_codes")
        .select("id, provider_id")
        .eq("child_id", row.child_id)
        .is("revoked_at", null)
        .then(({ data }) => setActiveQrs((data ?? []) as { id: string; provider_id: string }[]));
    }
    load();
  }, [row.child_id, reload]);

  const childName = `${row.display_name}${row.honorific_suffix ?? ""}`;

  // QR発行/再発行: issue_therapy_qr(既存有効QRを自動revoke→新規)→ 生tokenでPDFカードを生成。
  async function issueAndPrint(providerId: string, providerName: string) {
    setError(null);
    const { data, error: e } = await createClient().rpc("issue_therapy_qr", {
      p_child_id: row.child_id,
      p_provider_id: providerId,
    });
    const token = Array.isArray(data) ? (data[0]?.token as string | undefined) : undefined;
    if (e || !token) {
      setError("QR発行に失敗しました(権限=主任以上をご確認ください)");
      return;
    }
    const res = await fetch("/api/childcare/therapy-qr", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token,
        childName,
        providerName,
        officeName,
        issueDate: new Date().toLocaleDateString("ja-JP"),
      }),
    });
    if (!res.ok) {
      setError("PDF生成に失敗しました");
      return;
    }
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    window.open(url, "_blank");
    setReload((t) => t + 1);
  }

  async function revokeQr(qrId: string) {
    const { error: e } = await createClient().rpc("revoke_therapy_qr", { p_qr_id: qrId });
    if (e) {
      setError("無効化に失敗しました(権限=主任以上をご確認ください)");
      return;
    }
    setReload((t) => t + 1);
  }

  async function addSetting() {
    setError(null);
    if (!providerId || !startDate) {
      setError("事業所と開始日は必須です");
      return;
    }
    if (endDate && endDate < startDate) {
      setError("終了日は開始日以降にしてください");
      return;
    }
    const { error: e } = await createClient().rpc("add_child_therapy_setting", {
      p_child_id: row.child_id,
      p_provider_id: providerId,
      p_start_date: startDate,
      p_end_date: endDate || null,
    });
    if (e) {
      setError("追加に失敗しました(期間の重複、または権限=主任以上をご確認ください)");
      return;
    }
    setProviderId("");
    setStartDate("");
    setEndDate("");
    setReload((t) => t + 1);
  }

  async function deleteSetting(id: string) {
    const { error: e } = await createClient().rpc("delete_child_therapy_setting", { p_id: id });
    if (e) {
      setError("削除に失敗しました(権限=主任以上をご確認ください)");
      return;
    }
    setReload((t) => t + 1);
  }

  async function addProvider() {
    setError(null);
    if (!newProviderName.trim()) return;
    const { error: e } = await createClient().rpc("create_therapy_provider", { p_name: newProviderName.trim() });
    if (e) {
      setError("事業者の追加に失敗しました(統括園長以上のみ)");
      return;
    }
    setNewProviderName("");
    setReload((t) => t + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">
          療育設定 — {row.display_name}
          {row.honorific_suffix ?? ""}
        </h3>

        <div className="mt-4">
          <h4 className="text-sm font-semibold text-slate-600">設定済み</h4>
          {settings.length === 0 && <p className="mt-1 text-xs text-slate-400">設定はありません。</p>}
          <ul className="mt-2 space-y-1">
            {settings.map((s) => {
              const activeQr = activeQrs.find((q) => q.provider_id === s.provider_id);
              return (
                <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg bg-slate-50 px-3 py-2 text-sm">
                  <span>
                    {s.therapy_providers?.name ?? "—"} : {s.start_date} 〜 {s.end_date ?? "無期限"}
                    {activeQr ? (
                      <span className="ml-2 rounded-full bg-emerald-100 px-2 py-0.5 text-xs text-emerald-700">QR有効</span>
                    ) : (
                      <span className="ml-2 rounded-full bg-slate-200 px-2 py-0.5 text-xs text-slate-500">QR未発行</span>
                    )}
                  </span>
                  <span className="flex gap-1">
                    <button
                      onClick={() => issueAndPrint(s.provider_id, s.therapy_providers?.name ?? "")}
                      className="rounded border border-sky-300 px-2 py-0.5 text-xs text-sky-700 hover:bg-sky-50"
                    >
                      {activeQr ? "再発行・印刷" : "QR発行・印刷"}
                    </button>
                    {activeQr && (
                      <button
                        onClick={() => revokeQr(activeQr.id)}
                        className="rounded border border-amber-300 px-2 py-0.5 text-xs text-amber-700 hover:bg-amber-50"
                      >
                        無効化
                      </button>
                    )}
                    <button
                      onClick={() => deleteSetting(s.id)}
                      className="rounded border border-red-300 px-2 py-0.5 text-xs text-red-600 hover:bg-red-50"
                    >
                      削除
                    </button>
                  </span>
                </li>
              );
            })}
          </ul>
        </div>

        <div className="mt-5 rounded-xl border border-slate-200 p-3">
          <h4 className="text-sm font-semibold text-slate-600">追加</h4>
          <div className="mt-2 flex flex-wrap items-end gap-2">
            <div>
              <label className="mb-1 block text-xs text-slate-500">事業所</label>
              <select
                value={providerId}
                onChange={(e) => setProviderId(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm"
              >
                <option value="">選択</option>
                {providers.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="mb-1 block text-xs text-slate-500">開始日</label>
              <input type="date" value={startDate} onChange={(e) => setStartDate(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
            </div>
            <div>
              <label className="mb-1 block text-xs text-slate-500">終了日(任意)</label>
              <input type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2 text-sm" />
            </div>
            <button onClick={addSetting} className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600">
              追加
            </button>
          </div>
        </div>

        <div className="mt-4 rounded-xl border border-slate-200 p-3">
          <h4 className="text-sm font-semibold text-slate-600">事業者を追加(統括園長以上)</h4>
          <div className="mt-2 flex gap-2">
            <input
              value={newProviderName}
              onChange={(e) => setNewProviderName(e.target.value)}
              placeholder="事業者名"
              className="flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm"
            />
            <button onClick={addProvider} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">
              登録
            </button>
          </div>
        </div>

        {error && <p className="mt-3 text-xs font-medium text-red-500">{error}</p>}

        <div className="mt-6 flex justify-end">
          <button onClick={onClose} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">
            閉じる
          </button>
        </div>
      </div>
    </div>
  );
}
