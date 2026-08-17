"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import {
  ENROLLMENT_EDIT_SECTIONS,
  type EditFieldDef,
} from "@/lib/enrollmentFormDefs";
import type { ChildMasterRow } from "@/lib/types";

type Props = {
  row: ChildMasterRow;
  onClose: () => void;
  onSaved: () => void;
};

type SectionData = Record<string, unknown>;
type FormData = Record<string, unknown>;

function isVisible(f: EditFieldDef, section: SectionData): boolean {
  if (!f.visibleWhenKey) return true;
  return String(section[f.visibleWhenKey] ?? "") === f.visibleWhenEquals;
}

/// 園児情報の園側修正モーダル(222)。保護者が入力する内容(入園時基本情報)を園側でも修正できる。
/// 保存すると新しい「承認済み版(園側修正)」としてスナップショットに積まれ、
/// 承認時と同じ正本反映(園児氏名・性別・生年月日/世帯住所/お迎え者名簿)が走る。
/// 在籍種別(通常/一時預かり)の変更もここに集約(俊指示 2026-08-17: 一覧のリンクは誤操作防止のため廃止)。
export function ChildRegisterEditModal({ row, onClose, onSaved }: Props) {
  const [data, setData] = useState<FormData | null>(null);
  const [childKind, setChildKind] = useState<"regular" | "temporary">(row.child_kind);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_child_register", { p_child_id: row.child_id }).then(({ data: res, error }) => {
      if (error) {
        setLoadError(error.message);
        return;
      }
      const register = (Array.isArray(res) ? res[0] : res) as
        | { register_data: FormData | null }
        | undefined;
      if (register?.register_data) {
        setData(structuredClone(register.register_data));
      } else {
        // フォーム未提出の園児: 園児マスタの現在値を初期値にして新規作成
        setData({
          basic: {
            full_name: row.full_name,
            name_kana: row.name_kana ?? "",
            nickname: row.display_name,
            gender: row.gender ?? "",
            birth_date: row.birth_date ?? "",
          },
        });
      }
    });
  }, [row]);

  function updateField(sectionKey: string, itemIndex: number | null, key: string, value: unknown) {
    setData((prev) => {
      if (!prev) return prev;
      const next = structuredClone(prev);
      if (itemIndex == null) {
        const section = ((next[sectionKey] as SectionData) ?? {}) as SectionData;
        section[key] = value;
        next[sectionKey] = section;
      } else {
        const list = (next[sectionKey] as unknown[]) ?? [];
        const item = ((list[itemIndex] as SectionData) ?? {}) as SectionData;
        item[key] = value;
        list[itemIndex] = item;
        next[sectionKey] = list;
      }
      return next;
    });
  }

  function updateListField(sectionKey: string, listKey: string, itemIndex: number, key: string, value: unknown) {
    setData((prev) => {
      if (!prev) return prev;
      const next = structuredClone(prev);
      const section = ((next[sectionKey] as SectionData) ?? {}) as SectionData;
      const list = ((section[listKey] as unknown[]) ?? []) as unknown[];
      const item = ((list[itemIndex] as SectionData) ?? {}) as SectionData;
      item[key] = value;
      list[itemIndex] = item;
      section[listKey] = list;
      next[sectionKey] = section;
      return next;
    });
  }

  function mutateList(sectionKey: string, listKey: string | null, mutate: (list: unknown[]) => void) {
    setData((prev) => {
      if (!prev) return prev;
      const next = structuredClone(prev);
      if (listKey == null) {
        const list = ((next[sectionKey] as unknown[]) ?? []) as unknown[];
        mutate(list);
        next[sectionKey] = list;
      } else {
        const section = ((next[sectionKey] as SectionData) ?? {}) as SectionData;
        const list = ((section[listKey] as unknown[]) ?? []) as unknown[];
        mutate(list);
        section[listKey] = list;
        next[sectionKey] = section;
      }
      return next;
    });
  }

  async function handleSave() {
    if (!data) return;
    if (!window.confirm("園児情報を保存しますか?(新しい承認済み版として記録され、台帳・保護者側の表示に即時反映されます)")) return;
    setIsSaving(true);
    setSaveError(null);
    const supabase = createClient();
    if (childKind !== row.child_kind) {
      const { error } = await supabase.rpc("set_child_kind", {
        p_child_id: row.child_id,
        p_child_kind: childKind,
      });
      if (error) {
        setIsSaving(false);
        setSaveError(error.message);
        return;
      }
    }
    const { error } = await supabase.rpc("update_child_register_by_staff", {
      p_child_id: row.child_id,
      p_data: data,
    });
    setIsSaving(false);
    if (error) {
      setSaveError(
        error.message.includes("pending review")
          ? "保護者の提出が確認待ちです。入園手続きタブで承認または差し戻してから修正してください"
          : error.message,
      );
      return;
    }
    onSaved();
  }

  function fieldInput(
    f: EditFieldDef,
    value: unknown,
    onChange: (v: unknown) => void,
  ) {
    const cls = "w-full rounded-lg border border-slate-300 px-3 py-1.5 text-sm focus:border-sky-400 focus:outline-none";
    switch (f.type) {
      case "toggle":
        return (
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={value === true} onChange={(e) => onChange(e.target.checked)} />
            {f.label}
          </label>
        );
      case "select":
        return (
          <select value={String(value ?? "")} onChange={(e) => onChange(e.target.value)} className={cls}>
            <option value="">—</option>
            {f.options?.map((o) => (
              <option key={o} value={o}>
                {o}
              </option>
            ))}
          </select>
        );
      case "date":
        return <input type="date" value={String(value ?? "")} onChange={(e) => onChange(e.target.value)} className={cls} />;
      case "multiline":
        return <textarea rows={2} value={String(value ?? "")} onChange={(e) => onChange(e.target.value)} className={cls} />;
      default:
        return <input value={String(value ?? "")} onChange={(e) => onChange(e.target.value)} className={cls} />;
    }
  }

  function fieldRow(f: EditFieldDef, value: unknown, onChange: (v: unknown) => void) {
    if (f.type === "toggle") {
      return <div key={f.key} className="py-1">{fieldInput(f, value, onChange)}</div>;
    }
    return (
      <div key={f.key} className="py-1">
        <label className="mb-0.5 block text-xs font-medium text-slate-500">{f.label}</label>
        {fieldInput(f, value, onChange)}
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4 py-8">
      <div className="flex max-h-full w-full max-w-3xl flex-col rounded-2xl bg-white shadow-lg">
        <div className="flex items-center justify-between border-b border-slate-200 px-6 py-4">
          <div>
            <h2 className="text-base font-bold text-slate-800">園児情報の編集</h2>
            <p className="text-xs text-slate-400">
              {row.full_name} / 保存すると新しい承認済み版として記録され、台帳・保護者側の表示へ即時反映されます
            </p>
          </div>
          <button onClick={onClose} className="rounded-lg px-3 py-1 text-sm text-slate-500 hover:bg-slate-100">
            閉じる
          </button>
        </div>

        <div className="flex-1 space-y-4 overflow-y-auto px-6 py-4">
          {loadError && <p className="text-sm font-medium text-red-500">{loadError}</p>}
          {!data && !loadError && <p className="text-sm text-slate-400">読み込み中…</p>}

          {data && (
            <>
              <div className="rounded-xl border border-slate-200 p-3">
                <p className="mb-2 text-xs font-bold text-sky-700">在籍種別</p>
                <select
                  value={childKind}
                  onChange={(e) => setChildKind(e.target.value as "regular" | "temporary")}
                  className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm focus:border-sky-400 focus:outline-none"
                >
                  <option value="regular">通常在籍</option>
                  <option value="temporary">一時預かり</option>
                </select>
              </div>

              {ENROLLMENT_EDIT_SECTIONS.map((section) => {
                if (section.isArray) {
                  const list = ((data[section.key] as unknown[]) ?? []) as SectionData[];
                  return (
                    <div key={section.key} className="rounded-xl border border-slate-200 p-3">
                      <p className="mb-2 text-xs font-bold text-sky-700">{section.title}</p>
                      {list.map((item, i) => (
                        <div key={i} className="mb-2 rounded-lg bg-slate-50 p-2">
                          <div className="flex items-center justify-between">
                            <p className="text-xs font-semibold text-slate-500">{section.itemLabel} {i + 1}</p>
                            <button
                              onClick={() => mutateList(section.key, null, (l) => l.splice(i, 1))}
                              className="text-xs text-red-500 hover:underline"
                            >
                              削除
                            </button>
                          </div>
                          <div className="grid grid-cols-2 gap-x-4">
                            {section.itemFields?.map((f) =>
                              isVisible(f, item)
                                ? fieldRow(f, item[f.key], (v) => updateField(section.key, i, f.key, v))
                                : null,
                            )}
                          </div>
                        </div>
                      ))}
                      <button
                        onClick={() => mutateList(section.key, null, (l) => l.push({}))}
                        className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                      >
                        + {section.itemLabel}を追加
                      </button>
                    </div>
                  );
                }
                const sectionData = ((data[section.key] as SectionData) ?? {}) as SectionData;
                return (
                  <div key={section.key} className="rounded-xl border border-slate-200 p-3">
                    <p className="mb-2 text-xs font-bold text-sky-700">{section.title}</p>
                    <div className="grid grid-cols-2 gap-x-4">
                      {section.fields?.map((f) =>
                        isVisible(f, sectionData)
                          ? fieldRow(f, sectionData[f.key], (v) => updateField(section.key, null, f.key, v))
                          : null,
                      )}
                    </div>
                    {section.listGroups?.map((g) => {
                      const list = ((sectionData[g.listKey] as unknown[]) ?? []) as SectionData[];
                      return (
                        <div key={g.listKey} className="mt-2">
                          <p className="mb-1 text-xs font-semibold text-slate-500">{g.itemLabel}</p>
                          {list.map((item, i) => (
                            <div key={i} className="mb-2 rounded-lg bg-slate-50 p-2">
                              <div className="flex items-center justify-between">
                                <p className="text-xs font-semibold text-slate-500">{i + 1}</p>
                                <button
                                  onClick={() => mutateList(section.key, g.listKey, (l) => l.splice(i, 1))}
                                  className="text-xs text-red-500 hover:underline"
                                >
                                  削除
                                </button>
                              </div>
                              <div className="grid grid-cols-2 gap-x-4">
                                {g.itemFields.map((f) =>
                                  isVisible(f, item)
                                    ? fieldRow(f, item[f.key], (v) => updateListField(section.key, g.listKey, i, f.key, v))
                                    : null,
                                )}
                              </div>
                            </div>
                          ))}
                          <button
                            onClick={() => mutateList(section.key, g.listKey, (l) => l.push({}))}
                            className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                          >
                            + 追加
                          </button>
                        </div>
                      );
                    })}
                  </div>
                );
              })}
            </>
          )}
        </div>

        <div className="flex items-center justify-end gap-3 border-t border-slate-200 px-6 py-4">
          {saveError && <p className="mr-auto text-sm font-medium text-red-500">{saveError}</p>}
          <button
            onClick={onClose}
            className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            キャンセル
          </button>
          <button
            onClick={handleSave}
            disabled={isSaving || !data}
            className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
          >
            {isSaving ? "保存中…" : "保存する(園側修正)"}
          </button>
        </div>
      </div>
    </div>
  );
}
