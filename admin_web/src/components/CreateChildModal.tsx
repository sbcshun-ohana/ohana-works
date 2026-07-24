"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { currentDate } from "@/lib/datetime";
import type { ChildcareClass } from "@/lib/types";

type Props = {
  officeId: string;
  classes: ChildcareClass[];
  onClose: () => void;
  onSaved: () => void;
};

/// age_groupは「クラス名／◯歳児」形式(例:「はな組／0歳児」)から歳児数を取り出す。
function parseClassAge(ageGroup: string): number | null {
  const match = ageGroup.match(/(\d+)\s*歳児/);
  return match ? Number(match[1]) : null;
}

/// 4/1基準の年度で「◯歳児クラス」相当の年齢を概算する(早生まれの厳密な学年区分けまでは行わない、
/// 大きなズレを検知するための簡易計算)。
function estimateCohortAge(birthDate: string, referenceDate: string): number {
  const [by, bm] = birthDate.split("-").map(Number);
  const [ry, rm] = referenceDate.split("-").map(Number);
  const nendoStartYear = rm >= 4 ? ry : ry - 1;
  let age = nendoStartYear - by;
  if (bm < 4) age += 1;
  return age;
}

export function CreateChildModal({ officeId, classes, onClose, onSaved }: Props) {
  const [fullName, setFullName] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [nameKana, setNameKana] = useState("");
  const [gender, setGender] = useState("男");
  const [birthDate, setBirthDate] = useState("");
  const [classId, setClassId] = useState("");
  const [enrollmentStartDate, setEnrollmentStartDate] = useState(currentDate());
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const selectedClass = classes.find((c) => c.class_id === classId);
  const classAge = selectedClass ? parseClassAge(selectedClass.age_group) : null;
  const cohortAge = birthDate ? estimateCohortAge(birthDate, currentDate()) : null;
  const showAgeMismatchWarning =
    classAge != null && cohortAge != null && Math.abs(classAge - cohortAge) >= 2;

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (!fullName.trim() || !displayName.trim() || !birthDate || !classId || !enrollmentStartDate) {
      setErrorMessage("必須項目を入力してください");
      return;
    }
    setIsSaving(true);
    setErrorMessage(null);

    const supabase = createClient();
    const { error } = await supabase.rpc("create_child", {
      p_office_id: officeId,
      p_full_name: fullName.trim(),
      p_display_name: displayName.trim(),
      p_name_kana: nameKana.trim() || null,
      p_gender: gender,
      p_birth_date: birthDate,
      p_class_id: classId,
      p_enrollment_start_date: enrollmentStartDate,
    });

    setIsSaving(false);
    if (error) {
      setErrorMessage(error.message);
      return;
    }
    onSaved();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="max-h-[85vh] w-full max-w-md overflow-y-auto rounded-2xl bg-white p-6 shadow-lg">
        <h2 className="mb-4 text-base font-bold text-slate-800">新規園児登録</h2>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">正式氏名</label>
            <input
              required
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              placeholder="例: 山田 太郎"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">呼び名(敬称は含めない)</label>
            <input
              required
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder="例: たろう"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">ふりがな(任意)</label>
            <input
              value={nameKana}
              onChange={(e) => setNameKana(e.target.value)}
              placeholder="例: やまだたろう"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">性別</label>
            <select
              value={gender}
              onChange={(e) => setGender(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="男">男</option>
              <option value="女">女</option>
              <option value="その他">その他</option>
            </select>
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">生年月日</label>
            <input
              required
              type="date"
              value={birthDate}
              onChange={(e) => setBirthDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">所属クラス</label>
            <select
              required
              value={classId}
              onChange={(e) => setClassId(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="">選択してください</option>
              {classes.map((c) => (
                <option key={c.class_id} value={c.class_id}>
                  {c.class_name}({c.age_group})
                </option>
              ))}
            </select>
            {showAgeMismatchWarning && (
              <p className="mt-1 text-xs font-medium text-amber-600">
                生年月日とクラスの年齢区分が大きく異なります。ご確認ください。
              </p>
            )}
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">在籍開始日</label>
            <input
              required
              type="date"
              value={enrollmentStartDate}
              onChange={(e) => setEnrollmentStartDate(e.target.value)}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>

          {errorMessage && <p className="text-sm font-medium text-red-500">{errorMessage}</p>}

          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
            >
              キャンセル
            </button>
            <button
              type="submit"
              disabled={isSaving}
              className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
            >
              {isSaving ? "登録中…" : "登録する"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
