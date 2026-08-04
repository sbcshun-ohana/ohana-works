"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { TherapyProvider } from "@/lib/types";

/** 事業者マスタ管理(§2.1・統括園長以上)。登録・改名・有効/無効。 */
export function TherapyProvidersModal({ onClose }: { onClose: () => void }) {
  const [providers, setProviders] = useState<TherapyProvider[]>([]);
  const [newName, setNewName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    function load() {
      createClient()
        .from("therapy_providers")
        .select("id, name, is_active")
        .order("name")
        .then(({ data }) => setProviders((data ?? []) as TherapyProvider[]));
    }
    load();
  }, [reload]);

  async function addProvider() {
    setError(null);
    if (!newName.trim()) return;
    const { error: e } = await createClient().rpc("create_therapy_provider", { p_name: newName.trim() });
    if (e) {
      setError("登録に失敗しました(統括園長以上のみ)");
      return;
    }
    setNewName("");
    setReload((t) => t + 1);
  }

  async function update(p: TherapyProvider, name: string, isActive: boolean) {
    setError(null);
    const { error: e } = await createClient().rpc("update_therapy_provider", {
      p_id: p.id,
      p_name: name,
      p_is_active: isActive,
    });
    if (e) {
      setError("更新に失敗しました(統括園長以上のみ)");
      return;
    }
    setReload((t) => t + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/30 p-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
        <h3 className="text-base font-bold text-slate-800">療育事業者マスタ</h3>
        <p className="mt-1 text-xs text-slate-500">登録・改名・有効/無効は統括園長以上のみ可能です。</p>

        <ul className="mt-4 space-y-2">
          {providers.map((p) => (
            <ProviderRow key={p.id} provider={p} onUpdate={update} />
          ))}
          {providers.length === 0 && <li className="text-xs text-slate-400">事業者がありません。</li>}
        </ul>

        <div className="mt-4 flex gap-2 border-t border-slate-200 pt-4">
          <input
            value={newName}
            onChange={(e) => setNewName(e.target.value)}
            placeholder="新規事業者名"
            className="flex-1 rounded-lg border border-slate-300 px-3 py-2 text-sm"
          />
          <button onClick={addProvider} className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600">
            登録
          </button>
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

function ProviderRow({
  provider,
  onUpdate,
}: {
  provider: TherapyProvider;
  onUpdate: (p: TherapyProvider, name: string, isActive: boolean) => void;
}) {
  const [name, setName] = useState(provider.name);
  return (
    <li className="flex items-center gap-2 rounded-lg bg-slate-50 px-3 py-2">
      <input value={name} onChange={(e) => setName(e.target.value)} className="flex-1 rounded border border-slate-300 px-2 py-1 text-sm" />
      <label className="flex items-center gap-1 text-xs text-slate-600">
        <input type="checkbox" checked={provider.is_active} onChange={(e) => onUpdate(provider, name, e.target.checked)} />
        有効
      </label>
      <button
        onClick={() => onUpdate(provider, name, provider.is_active)}
        className="rounded border border-slate-300 px-2 py-1 text-xs text-slate-600 hover:bg-slate-100"
      >
        保存
      </button>
    </li>
  );
}
