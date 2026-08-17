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
export function parseClassAge(ageGroup: string): number | null {
  const match = ageGroup.match(/(\d+)\s*歳児/);
  return match ? Number(match[1]) : null;
}

/// 入園日が属する年度(4/1区切り)の4/1時点での年齢区分を求める。
/// コホートは「毎年4/2生まれ〜翌年4/1生まれ」が1単位(4/1生まれは前のコホート扱い、早生まれ)。
export function estimateCohortAge(birthDate: string, enrollmentDate: string): number {
  const [by, bm, bd] = birthDate.split("-").map(Number);
  const [ry, rm] = enrollmentDate.split("-").map(Number);
  const nendoYear = rm >= 4 ? ry : ry - 1;
  const cohortYear = bm > 4 || (bm === 4 && bd >= 2) ? by : by - 1;
  return nendoYear - cohortYear - 1;
}

export function CreateChildModal({ officeId, classes, onClose, onSaved }: Props) {
  const [fullName, setFullName] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [nameKana, setNameKana] = useState("");
  const [gender, setGender] = useState("男");
  const [birthDate, setBirthDate] = useState("");
  const [classId, setClassId] = useState("");
  const [enrollmentStartDate, setEnrollmentStartDate] = useState(currentDate());
  const [childKind, setChildKind] = useState<"regular" | "temporary">("regular");
  const [isSaving, setIsSaving] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const selectedClass = classes.find((c) => c.class_id === classId);
  const classAge = selectedClass ? parseClassAge(selectedClass.age_group) : null;
  const cohortAge = birthDate && enrollmentStartDate ? estimateCohortAge(birthDate, enrollmentStartDate) : null;
  const showAgeMismatchWarning =
    classAge != null && cohortAge != null && Math.abs(classAge - cohortAge) >= 2;
  const noMatchingClass =
    cohortAge != null && !classId && !classes.some((c) => parseClassAge(c.age_group) === cohortAge);

  function suggestClassId(nextBirthDate: string, nextEnrollmentDate: string) {
    if (!nextBirthDate || !nextEnrollmentDate) return;
    const age = estimateCohortAge(nextBirthDate, nextEnrollmentDate);
    const match = classes.find((c) => parseClassAge(c.age_group) === age);
    setClassId(match ? match.class_id : "");
  }

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
      p_child_kind: childKind,
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
            <label className="mb-1 block text-sm font-medium text-slate-700">在籍種別</label>
            <select
              value={childKind}
              onChange={(e) => setChildKind(e.target.value as "regular" | "temporary")}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              <option value="regular">通常在籍</option>
              <option value="temporary">一時預かり</option>
            </select>
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
              onChange={(e) => {
                setBirthDate(e.target.value);
                suggestClassId(e.target.value, enrollmentStartDate);
              }}
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
            {noMatchingClass && (
              <p className="mt-1 text-xs font-medium text-amber-600">
                この施設には該当する年齢区分のクラスがありません。手動で選択してください。
              </p>
            )}
            {!noMatchingClass && showAgeMismatchWarning && (
              <p className="mt-1 text-xs font-medium text-amber-600">
                生年月日とクラスの年齢区分が大きく異なります。ご確認ください。
              </p>
            )}
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">在籍開始日(入園日)</label>
            <input
              required
              type="date"
              value={enrollmentStartDate}
              onChange={(e) => {
                setEnrollmentStartDate(e.target.value);
                suggestClassId(birthDate, e.target.value);
              }}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <p className="mt-1 text-xs text-slate-400">
              入園日が属する年度の4月1日時点での年齢でクラスを自動提案します(4月1日生まれは1つ上のコホート扱い)。
            </p>
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
