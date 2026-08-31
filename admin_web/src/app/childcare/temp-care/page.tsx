"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 一時預かり(Phase9 T1・405)。簡易入園=氏名・生年月日・性別で登録すると、
// 生年月日から年齢クラスを自動算出し「一時預かり(N歳)」クラスへ自動在籍。
// 0-2歳=連絡帳・午睡あり / 3-5歳=なし(登降園・給食・請求のみ)は既存のクラス年齢フラグで自動。
// 登録後は通常の園児と同様にデイリーボード・連絡帳・食数に現れる(当日精算請求はT3)。

type TempChild = {
  child_id: string;
  display_name: string;
  name_kana: string | null;
  birth_date: string;
  gender: string | null;
  nursery_age: number;
  class_name: string | null;
  contact_required: boolean;
  nap_required: boolean;
  enrollment_date: string;
  is_active: boolean;  // 利用中(=デイリーボード表示中) / 休止中
};

function TempCarePageContent() {
  const { officesError, selectedOffice } = useChildcareOffices();
  const [rows, setRows] = useState<TempChild[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);

  const [name, setName] = useState("");
  const [kana, setKana] = useState("");
  const [birth, setBirth] = useState("");
  const [gender, setGender] = useState("");
  const [editId, setEditId] = useState<string | null>(null);  // null=新規登録 / child_id=編集中

  const reload = useCallback(() => setReloadToken((t) => t + 1), []);

  useEffect(() => {
    if (!selectedOffice) return;
    let stale = false;
    setLoadError(null);
    createClient()
      .rpc("fetch_temp_care_children", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        if (stale) return;
        if (error) {
          setLoadError(
            error.message.includes("not authorized") ? "このページは主任以上のみ利用できます" : error.message,
          );
          setRows([]);
          return;
        }
        setRows((data ?? []) as TempChild[]);
      });
    return () => { stale = true; };
  }, [selectedOffice, reloadToken]);

  function closeForm() {
    setName(""); setKana(""); setBirth(""); setGender(""); setEditId(null);
    setShowForm(false); setFormError(null);
  }

  function openEdit(r: TempChild) {
    setEditId(r.child_id);
    setName(r.display_name);
    setKana(r.name_kana ?? "");
    setBirth(r.birth_date);
    setGender(r.gender ?? "");
    setShowForm(true);
    setFormError(null);
  }

  async function handleSubmit() {
    if (!name.trim()) { setFormError("氏名を入力してください"); return; }
    if (!birth) { setFormError("生年月日を入力してください"); return; }
    setBusy(true);
    setFormError(null);
    const client = createClient();
    const { error } = editId
      ? await client.rpc("update_temp_care_child", {
          p_child_id: editId,
          p_full_name: name.trim(),
          p_birth_date: birth,
          p_gender: gender || null,
          p_name_kana: kana.trim() || null,
        })
      : await client.rpc("enroll_temp_care_child", {
          p_office_id: selectedOffice,
          p_full_name: name.trim(),
          p_birth_date: birth,
          p_gender: gender || null,
          p_name_kana: kana.trim() || null,
        });
    setBusy(false);
    if (error) {
      setFormError(error.message);
      return;
    }
    closeForm();
    reload();
  }

  async function handleRemove(r: TempChild) {
    if (!window.confirm(`「${r.display_name}」の登録を取り消しますか?(一覧から除外されます)`)) return;
    const { error } = await createClient().rpc("remove_temp_care_child", { p_child_id: r.child_id });
    if (error) {
      window.alert(`取消に失敗しました: ${error.message}`);
      return;
    }
    reload();
  }

  async function handleToggleActive(r: TempChild) {
    const to = !r.is_active;
    if (to) {
      if (!window.confirm(`「${r.display_name}」の利用を再開しますか?(デイリーボードに表示されます)`)) return;
    } else {
      if (!window.confirm(`「${r.display_name}」を休止しますか?(翌日以降デイリーボードから非表示・登録情報は保持されます)`)) return;
    }
    const { error } = await createClient().rpc("set_temp_care_active", { p_child_id: r.child_id, p_active: to });
    if (error) {
      window.alert(`変更に失敗しました: ${error.message}`);
      return;
    }
    reload();
  }

  // プレビュー: 入力した生年月日から保育年齢(4/1時点)を概算表示
  function previewAge(): number | null {
    if (!birth) return null;
    const b = new Date(birth);
    const now = new Date();
    const fiscal = now.getMonth() + 1 >= 4 ? now.getFullYear() : now.getFullYear() - 1;
    const apr1 = new Date(fiscal, 3, 1);
    let age = apr1.getFullYear() - b.getFullYear();
    if (apr1.getMonth() < b.getMonth() || (apr1.getMonth() === b.getMonth() && apr1.getDate() < b.getDate())) age--;
    return Math.max(0, Math.min(5, age));
  }
  const pAge = previewAge();

  return (
    <div className="min-h-screen bg-slate-50">
      <AppHeader />
      <main className="mx-auto max-w-4xl px-6 py-6">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-xl font-bold text-slate-800">一時預かり</h2>
            <p className="mt-1 text-sm text-slate-500">
              氏名・生年月日で簡易登録すると、年齢に応じた「一時預かり」クラスへ自動で在籍します
              （0〜2歳は連絡帳・午睡あり、3〜5歳は登降園・給食のみ）。
            </p>
          </div>
          <button
            onClick={() => { if (showForm) { closeForm(); } else { setEditId(null); setName(""); setKana(""); setBirth(""); setGender(""); setShowForm(true); setFormError(null); } }}
            className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
          >
            + 一時預かり児を登録
          </button>
        </div>

        {officesError && <p className="mb-4 text-sm font-medium text-red-500">{officesError}</p>}
        {loadError && (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-medium text-red-600">
            {loadError}
          </div>
        )}

        {showForm && (
          <div className="mb-5 rounded-xl border border-sky-200 bg-white p-4">
            <h3 className="mb-3 text-sm font-bold text-slate-700">{editId ? "登録内容の修正" : "簡易登録"}</h3>
            <div className="flex flex-wrap items-end gap-3">
              <label className="text-xs text-slate-600">
                氏名 <span className="text-red-500">*</span>
                <input type="text" value={name} onChange={(e) => setName(e.target.value)}
                  className="mt-0.5 block w-44 rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
              </label>
              <label className="text-xs text-slate-600">
                ふりがな
                <input type="text" value={kana} onChange={(e) => setKana(e.target.value)}
                  className="mt-0.5 block w-40 rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
              </label>
              <label className="text-xs text-slate-600">
                生年月日 <span className="text-red-500">*</span>
                <input type="date" value={birth} onChange={(e) => setBirth(e.target.value)}
                  className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
              </label>
              <label className="text-xs text-slate-600">
                性別
                <select value={gender} onChange={(e) => setGender(e.target.value)}
                  className="mt-0.5 block rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                  <option value="">未選択</option>
                  <option value="男">男</option>
                  <option value="女">女</option>
                  <option value="その他">その他</option>
                </select>
              </label>
              <button onClick={handleSubmit} disabled={busy}
                className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60">
                {busy ? "保存中…" : editId ? "更新する" : "登録する"}
              </button>
              {editId && (
                <button onClick={closeForm}
                  className="rounded-lg border border-slate-300 px-4 py-2 text-sm text-slate-600 hover:bg-slate-50">
                  キャンセル
                </button>
              )}
            </div>
            {pAge !== null && (
              <p className="mt-2 text-xs text-slate-500">
                → 保育年齢 <span className="font-bold text-slate-700">{pAge}歳</span>：
                「一時預かり」クラスに在籍します（
                {pAge <= 2 ? "連絡帳・午睡あり" : "登降園・給食のみ"}）
              </p>
            )}
            {formError && <p className="mt-2 text-sm font-medium text-red-500">{formError}</p>}
          </div>
        )}

        <section className="overflow-hidden rounded-xl border border-slate-200 bg-white">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-slate-400">
                <th className="px-4 py-2 font-medium">氏名</th>
                <th className="px-2 py-2 font-medium">生年月日</th>
                <th className="px-2 py-2 font-medium">保育年齢</th>
                <th className="px-2 py-2 font-medium">クラス</th>
                <th className="px-2 py-2 font-medium">連絡帳/午睡</th>
                <th className="px-2 py-2 font-medium">状態</th>
                <th className="px-2 py-2 font-medium">登録日</th>
                <th className="px-4 py-2 text-right font-medium">操作</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.child_id} className="border-t border-slate-100">
                  <td className="px-4 py-2 font-medium text-slate-700">
                    {r.display_name}
                    {r.name_kana && <span className="ml-1 text-xs text-slate-400">{r.name_kana}</span>}
                  </td>
                  <td className="px-2 py-2 tabular-nums text-slate-600">{r.birth_date}</td>
                  <td className="px-2 py-2 text-slate-700">{r.nursery_age}歳</td>
                  <td className="px-2 py-2 text-slate-600">{r.class_name ?? ""}</td>
                  <td className="px-2 py-2">
                    {r.contact_required ? (
                      <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-xs font-semibold text-emerald-700">あり</span>
                    ) : (
                      <span className="rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-500">なし</span>
                    )}
                  </td>
                  <td className="px-2 py-2">
                    {r.is_active ? (
                      <span className="rounded bg-emerald-50 px-1.5 py-0.5 text-xs font-semibold text-emerald-700">利用中</span>
                    ) : (
                      <span className="rounded bg-slate-100 px-1.5 py-0.5 text-xs text-slate-500">休止中</span>
                    )}
                  </td>
                  <td className="px-2 py-2 tabular-nums text-slate-500">{r.enrollment_date}</td>
                  <td className="px-4 py-2 text-right">
                    <div className="flex justify-end gap-1.5">
                      <button onClick={() => handleToggleActive(r)}
                        className={`rounded border px-2 py-1 text-xs ${r.is_active
                          ? "border-amber-200 text-amber-600 hover:bg-amber-50"
                          : "border-emerald-200 text-emerald-700 hover:bg-emerald-50"}`}>
                        {r.is_active ? "休止" : "再開"}
                      </button>
                      <button onClick={() => openEdit(r)}
                        className="rounded border border-slate-200 px-2 py-1 text-xs text-slate-500 hover:bg-slate-50">
                        編集
                      </button>
                      <button onClick={() => handleRemove(r)}
                        className="rounded border border-red-200 px-2 py-1 text-xs text-red-500 hover:bg-red-50">
                        取消
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
              {rows.length === 0 && !loadError && (
                <tr><td colSpan={8} className="px-4 py-3 text-sm text-slate-400">一時預かり児はまだ登録されていません</td></tr>
              )}
            </tbody>
          </table>
        </section>
      </main>
    </div>
  );
}

export default function TempCarePage() {
  return (
    <Suspense fallback={null}>
      <TempCarePageContent />
    </Suspense>
  );
}
