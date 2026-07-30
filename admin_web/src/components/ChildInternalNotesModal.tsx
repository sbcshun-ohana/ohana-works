"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { CHILD_INTERNAL_NOTE_CATEGORY_LABELS, type ChildInternalNote, type ChildInternalNoteCategory } from "@/lib/types";

const CATEGORY_ENTRIES = Object.entries(CHILD_INTERNAL_NOTE_CATEGORY_LABELS) as [ChildInternalNoteCategory, string][];
const TWENTY_FOUR_HOURS_MS = 24 * 60 * 60 * 1000;

type Props = {
  childId: string;
  childName: string;
  officeId: string;
  onClose: () => void;
};

export function ChildInternalNotesModal({ childId, childName, officeId, onClose }: Props) {
  const [notes, setNotes] = useState<ChildInternalNote[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [listError, setListError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [filterCategories, setFilterCategories] = useState<ChildInternalNoteCategory[]>([]);
  const [filterFrom, setFilterFrom] = useState("");
  const [filterTo, setFilterTo] = useState("");

  const [myEmployeeId, setMyEmployeeId] = useState<string | null>(null);
  const [isChief, setIsChief] = useState(false);

  const [newDate, setNewDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [newCategory, setNewCategory] = useState<ChildInternalNoteCategory>("handover");
  const [newBody, setNewBody] = useState("");
  const [newAiExcluded, setNewAiExcluded] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const [editingNoteId, setEditingNoteId] = useState<string | null>(null);
  const [editBody, setEditBody] = useState("");
  const [editCategory, setEditCategory] = useState<ChildInternalNoteCategory>("handover");
  const [editAiExcluded, setEditAiExcluded] = useState(false);
  const [editDate, setEditDate] = useState("");

  // 自分の職員IDと主任以上判定(表示制御のみに使う。許可の根拠はRPC側)
  useEffect(() => {
    function load() {
      const supabase = createClient();
      supabase.rpc("my_employee_id").then(({ data }) => setMyEmployeeId((data as string) ?? null));
      supabase.rpc("is_child_internal_notes_chief", { target_office_id: officeId }).then(({ data }) => setIsChief(Boolean(data)));
    }
    load();
  }, [officeId]);

  // 一覧取得。絞り込み条件はフロントで再実装せず、必ずRPCの引数として渡す
  useEffect(() => {
    function load() {
      setIsLoading(true);
      setListError(null);
      const supabase = createClient();
      supabase
        .rpc("fetch_child_internal_notes", {
          p_child_id: childId,
          p_from: filterFrom || null,
          p_to: filterTo || null,
          p_categories: filterCategories.length > 0 ? filterCategories : null,
        })
        .then(({ data, error }) => {
          setIsLoading(false);
          if (error) {
            setListError(error.message);
            return;
          }
          setNotes((data ?? []) as ChildInternalNote[]);
        });
    }
    load();
  }, [childId, filterFrom, filterTo, filterCategories, reloadToken]);

  function toggleFilterCategory(category: ChildInternalNoteCategory) {
    setFilterCategories((prev) => (prev.includes(category) ? prev.filter((c) => c !== category) : [...prev, category]));
  }

  function canEditNote(note: ChildInternalNote): boolean {
    if (isChief) return true;
    if (!myEmployeeId || note.author_employee_id !== myEmployeeId) return false;
    // 表示制御のみ(ボタンの出し分け)。実際の許可判定は必ずRPC側(24時間ルール)で行う
    const nowMs = new Date().getTime();
    return nowMs - new Date(note.created_at).getTime() < TWENTY_FOUR_HOURS_MS;
  }

  async function createNote() {
    if (!newBody.trim()) {
      setActionError("本文を入力してください");
      return;
    }
    setActionError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("create_child_internal_note", {
      p_child_id: childId,
      p_note_date: newDate,
      p_category: newCategory,
      p_body: newBody,
      p_ai_excluded: newAiExcluded,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setNewBody("");
    setNewAiExcluded(false);
    setReloadToken((t) => t + 1);
  }

  function startEdit(note: ChildInternalNote) {
    setEditingNoteId(note.id);
    setEditBody(note.body);
    setEditCategory(note.category);
    setEditAiExcluded(note.ai_excluded);
    setEditDate(note.note_date);
  }

  async function saveEdit(noteId: string) {
    setActionError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("update_child_internal_note", {
      p_note_id: noteId,
      p_body: editBody,
      p_category: editCategory,
      p_ai_excluded: editAiExcluded,
      p_note_date: editDate,
    });
    if (error) {
      setActionError(error.message);
      return;
    }
    setEditingNoteId(null);
    setReloadToken((t) => t + 1);
  }

  async function deleteNote(noteId: string) {
    if (!window.confirm("この記録を削除します。よろしいですか?")) return;
    setActionError(null);
    const supabase = createClient();
    const { error } = await supabase.rpc("soft_delete_child_internal_note", { p_note_id: noteId });
    if (error) {
      setActionError(error.message);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      {/* 保護者非公開であることを枠線・ヘッダーの配色で明示(連絡帳=保護者公開の入力欄との誤記入防止)。 */}
      <div className="max-h-[85vh] w-full max-w-2xl overflow-y-auto rounded-2xl border-2 border-amber-400 bg-white shadow-lg">
        {/* 琥珀色のヘッダー帯: この画面が職員専用・保護者非公開であることを常時明示する */}
        <div className="sticky top-0 z-10 flex items-center justify-between border-b-2 border-amber-400 bg-amber-100 px-6 py-3">
          <div className="flex items-center gap-2">
            <span aria-hidden className="text-base">🔒</span>
            <div>
              <h2 className="text-base font-bold text-amber-900">園内記録: {childName}</h2>
              <p className="text-xs font-semibold text-amber-700">職員専用 / 保護者には表示されません</p>
            </div>
          </div>
          <button onClick={onClose} className="text-sm text-amber-700 hover:text-amber-900">
            閉じる
          </button>
        </div>

        <div className="p-6">
        <p className="mb-4 rounded-lg bg-amber-50 px-3 py-2 text-xs font-medium text-amber-700">
          この記録は保護者には表示されません
        </p>

        {/* 絞り込み(区分・期間)。値はそのままRPCの引数として渡す */}
        <div className="mb-4 space-y-2 rounded-xl bg-slate-50 p-3">
          <div className="flex flex-wrap gap-2">
            {CATEGORY_ENTRIES.map(([key, label]) => (
              <label key={key} className="flex items-center gap-1 text-xs text-slate-600">
                <input type="checkbox" checked={filterCategories.includes(key)} onChange={() => toggleFilterCategory(key)} />
                {label}
              </label>
            ))}
          </div>
          <div className="flex items-center gap-2">
            <input type="date" value={filterFrom} onChange={(e) => setFilterFrom(e.target.value)} className="rounded-lg border border-slate-300 px-2 py-1 text-xs" />
            <span className="text-xs text-slate-400">〜</span>
            <input type="date" value={filterTo} onChange={(e) => setFilterTo(e.target.value)} className="rounded-lg border border-slate-300 px-2 py-1 text-xs" />
          </div>
        </div>

        {/* 新規追記(保護者非公開の記録。連絡帳の入力欄=保護者公開との取り違え防止のため琥珀色で統一) */}
        <div className="mb-4 space-y-2 rounded-xl border border-amber-300 bg-amber-50 p-3">
          <p className="text-xs font-semibold text-amber-700">新規追記(園内記録・保護者非公開)</p>
          <div className="flex flex-wrap gap-2">
            <input type="date" value={newDate} onChange={(e) => setNewDate(e.target.value)} className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
            <select
              value={newCategory}
              onChange={(e) => setNewCategory(e.target.value as ChildInternalNoteCategory)}
              className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
            >
              {CATEGORY_ENTRIES.map(([key, label]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ))}
            </select>
            <label className="flex items-center gap-1 text-xs text-slate-600">
              <input type="checkbox" checked={newAiExcluded} onChange={(e) => setNewAiExcluded(e.target.checked)} />
              AI参照から除外
            </label>
          </div>
          <textarea
            value={newBody}
            onChange={(e) => setNewBody(e.target.value)}
            rows={3}
            placeholder="本文"
            className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm"
          />
          {actionError && <p className="text-xs font-medium text-red-600">{actionError}</p>}
          <button onClick={createNote} className="rounded-lg bg-amber-600 px-4 py-1.5 text-xs font-semibold text-white hover:bg-amber-700">
            園内記録として保存
          </button>
        </div>

        {/* 一覧(新しい順) */}
        {listError && <p className="text-sm text-red-600">{listError}</p>}
        {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}
        <div className="space-y-2">
          {!isLoading && notes.length === 0 && <p className="text-sm text-slate-400">記録がありません</p>}
          {notes.map((note) => (
            <div key={note.id} className="rounded-lg border border-slate-200 p-3 text-sm">
              {editingNoteId === note.id ? (
                <div className="space-y-2">
                  <div className="flex flex-wrap gap-2">
                    <input type="date" value={editDate} onChange={(e) => setEditDate(e.target.value)} className="rounded-lg border border-slate-300 px-2 py-1 text-xs" />
                    <select
                      value={editCategory}
                      onChange={(e) => setEditCategory(e.target.value as ChildInternalNoteCategory)}
                      className="rounded-lg border border-slate-300 px-2 py-1 text-xs"
                    >
                      {CATEGORY_ENTRIES.map(([key, label]) => (
                        <option key={key} value={key}>
                          {label}
                        </option>
                      ))}
                    </select>
                    <label className="flex items-center gap-1 text-xs text-slate-600">
                      <input type="checkbox" checked={editAiExcluded} onChange={(e) => setEditAiExcluded(e.target.checked)} />
                      AI参照から除外
                    </label>
                  </div>
                  <textarea value={editBody} onChange={(e) => setEditBody(e.target.value)} rows={3} className="w-full rounded-lg border border-slate-300 px-2 py-1.5 text-sm" />
                  {actionError && <p className="text-xs font-medium text-red-600">{actionError}</p>}
                  <div className="flex gap-2">
                    <button onClick={() => saveEdit(note.id)} className="rounded-lg bg-sky-600 px-3 py-1 text-xs font-semibold text-white hover:bg-sky-700">
                      保存
                    </button>
                    <button onClick={() => setEditingNoteId(null)} className="rounded-lg border border-slate-300 px-3 py-1 text-xs text-slate-600 hover:bg-slate-100">
                      キャンセル
                    </button>
                  </div>
                </div>
              ) : (
                <>
                  <div className="mb-1 flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-600">
                        {CHILD_INTERNAL_NOTE_CATEGORY_LABELS[note.category]}
                      </span>
                      <span className="text-xs text-slate-400">{note.note_date}</span>
                      {note.ai_excluded && (
                        <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-400">AI参照対象外</span>
                      )}
                    </div>
                    {canEditNote(note) && (
                      <div className="flex gap-2">
                        <button onClick={() => startEdit(note)} className="text-xs font-medium text-sky-600 hover:underline">
                          編集
                        </button>
                        <button onClick={() => deleteNote(note.id)} className="text-xs font-medium text-red-600 hover:underline">
                          削除
                        </button>
                      </div>
                    )}
                  </div>
                  <p className="whitespace-pre-wrap text-slate-700">{note.body}</p>
                </>
              )}
            </div>
          ))}
        </div>
        </div>
      </div>
    </div>
  );
}
