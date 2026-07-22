"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import {
  COMPOSABLE_NOTICE_CATEGORIES,
  STANDARD_REPLY_OPTION_CHOICES,
  type ComposableNoticeCategory,
  type ManageableOffice,
  type NoticeCategory,
  type NoticeRow,
  type OfficeEmployee,
  type PositionRow,
  type StaffGroupRow,
} from "@/lib/types";

const NOTICE_CATEGORY_LABELS: Record<NoticeCategory, string> = {
  会社一斉: "会社一斉",
  園単位: "園単位",
  役職別: "役職別",
  個別: "個別",
  グループ: "グループ",
  勤務交代関連: "勤務交代関連(専用フロー)",
  災害モード: "災害モード(専用フロー)",
};

function emptyComposeState() {
  return {
    category: "園単位" as ComposableNoticeCategory,
    title: "",
    body: "",
    officeId: "",
    positionId: "",
    groupId: "",
    employeeIds: new Set<string>(),
    requiresReadConfirmation: false,
    replyOptions: new Set<string>(),
  };
}

export default function NoticesPage() {
  const [offices, setOffices] = useState<ManageableOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [isLaborManagerPlus, setIsLaborManagerPlus] = useState(false);

  const [positions, setPositions] = useState<PositionRow[]>([]);
  const [employees, setEmployees] = useState<OfficeEmployee[]>([]);
  const [groups, setGroups] = useState<StaffGroupRow[]>([]);

  const [compose, setCompose] = useState(emptyComposeState());
  const [isSaving, setIsSaving] = useState(false);
  const [composeError, setComposeError] = useState<string | null>(null);
  const [composeMessage, setComposeMessage] = useState<string | null>(null);

  const [notices, setNotices] = useState<NoticeRow[]>([]);
  const [noticesError, setNoticesError] = useState<string | null>(null);
  const [noticesReloadToken, setNoticesReloadToken] = useState(0);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_manageable_offices").then(({ data, error }) => {
      if (error) {
        setOfficesError(error.message);
        return;
      }
      const list = (data ?? []) as ManageableOffice[];
      setOffices(list);
      setCompose((prev) => ({ ...prev, officeId: list.length > 0 ? list[0].id : "" }));
    });
    supabase.rpc("is_labor_manager_plus").then(({ data, error }) => {
      setIsLaborManagerPlus(error ? false : Boolean(data));
    });
    supabase
      .from("positions")
      .select("id, name")
      .eq("is_active", true)
      .order("sort_order")
      .then(({ data, error }) => {
        if (!error) setPositions((data ?? []) as PositionRow[]);
      });
  }, []);

  useEffect(() => {
    function clearOfficeScoped() {
      setEmployees([]);
      setGroups([]);
    }
    const officeId = compose.officeId;
    if (!officeId) {
      clearOfficeScoped();
      return;
    }
    const supabase = createClient();
    supabase.rpc("fetch_office_employees", { p_office_id: officeId }).then(({ data, error }) => {
      if (!error) setEmployees((data ?? []) as OfficeEmployee[]);
    });
    supabase
      .from("staff_groups")
      .select("id, office_id, group_type, name, related_class_id, is_active, created_at, archived_at")
      .eq("office_id", officeId)
      .eq("is_active", true)
      .order("name")
      .then(({ data, error }) => {
        if (!error) setGroups((data ?? []) as StaffGroupRow[]);
      });
  }, [compose.officeId]);

  useEffect(() => {
    const supabase = createClient();
    supabase
      .from("notices")
      .select(
        "id, category, title, body, target_office_id, target_position_id, target_group_id, requires_read_confirmation, standard_reply_options, created_at",
      )
      .order("created_at", { ascending: false })
      .limit(50)
      .then(({ data, error }) => {
        if (error) {
          setNoticesError(error.message);
          return;
        }
        setNotices((data ?? []) as NoticeRow[]);
      });
  }, [noticesReloadToken]);

  function toggleEmployee(id: string) {
    setCompose((prev) => {
      const next = new Set(prev.employeeIds);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return { ...prev, employeeIds: next };
    });
  }

  function toggleReplyOption(option: string) {
    setCompose((prev) => {
      const next = new Set(prev.replyOptions);
      if (next.has(option)) next.delete(option);
      else next.add(option);
      return { ...prev, replyOptions: next };
    });
  }

  async function handleSubmit() {
    setComposeError(null);
    setComposeMessage(null);

    if (!compose.title.trim() || !compose.body.trim()) {
      setComposeError("タイトルと本文を入力してください。");
      return;
    }
    if (compose.category === "個別" && compose.employeeIds.size === 0) {
      setComposeError("個別連絡は宛先を1名以上選択してください。");
      return;
    }
    if (compose.category === "グループ" && !compose.groupId) {
      setComposeError("宛先グループを選択してください。");
      return;
    }
    if (compose.category === "役職別" && !compose.positionId) {
      setComposeError("宛先役職を選択してください。");
      return;
    }

    setIsSaving(true);
    const supabase = createClient();
    const { error } = await supabase.rpc("create_notice", {
      p_category: compose.category,
      p_title: compose.title,
      p_body: compose.body,
      p_target_office_id: compose.category === "園単位" ? compose.officeId : null,
      p_target_position_id: compose.category === "役職別" ? compose.positionId : null,
      p_target_group_id: compose.category === "グループ" ? compose.groupId : null,
      p_individual_employee_ids: compose.category === "個別" ? Array.from(compose.employeeIds) : null,
      p_requires_read_confirmation: compose.requiresReadConfirmation,
      p_standard_reply_options: compose.replyOptions.size > 0 ? Array.from(compose.replyOptions) : null,
    });
    setIsSaving(false);

    if (error) {
      setComposeError(error.message);
      return;
    }
    setComposeMessage("お知らせを送信しました。");
    setCompose((prev) => ({ ...emptyComposeState(), officeId: prev.officeId }));
    setNoticesReloadToken((t) => t + 1);
  }

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  if (offices !== null && offices.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">
          この機能を利用する権限がありません(主任・園長・施設管理者以上が必要です)。
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <main className="flex-1 space-y-6 p-6">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-slate-800">お知らせ・個別連絡・グループ連絡</h2>
          <Link
            href="/notices/groups"
            className="rounded-lg border border-sky-300 px-4 py-2 text-sm font-semibold text-sky-700 hover:bg-sky-50"
          >
            グループ管理へ
          </Link>
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">新規作成</h3>

          <div className="flex flex-wrap gap-4">
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">カテゴリ</label>
              <select
                value={compose.category}
                onChange={(e) => setCompose((prev) => ({ ...prev, category: e.target.value as ComposableNoticeCategory }))}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              >
                {COMPOSABLE_NOTICE_CATEGORIES.map((cat) => (
                  <option key={cat.value} value={cat.value} disabled={cat.requiresLaborManager && !isLaborManagerPlus}>
                    {cat.label}
                    {cat.requiresLaborManager && !isLaborManagerPlus ? "(権限が必要)" : ""}
                  </option>
                ))}
              </select>
            </div>

            {(compose.category === "園単位" || compose.category === "個別" || compose.category === "グループ") && (
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-500">対象施設</label>
                <select
                  value={compose.officeId}
                  onChange={(e) => setCompose((prev) => ({ ...prev, officeId: e.target.value, employeeIds: new Set(), groupId: "" }))}
                  className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                >
                  {offices?.map((office) => (
                    <option key={office.id} value={office.id}>
                      {office.name}
                    </option>
                  ))}
                </select>
              </div>
            )}

            {compose.category === "役職別" && (
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-500">対象役職</label>
                <select
                  value={compose.positionId}
                  onChange={(e) => setCompose((prev) => ({ ...prev, positionId: e.target.value }))}
                  className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                >
                  <option value="">選択してください</option>
                  {positions.map((position) => (
                    <option key={position.id} value={position.id}>
                      {position.name}
                    </option>
                  ))}
                </select>
              </div>
            )}

            {compose.category === "グループ" && (
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-500">対象グループ</label>
                <select
                  value={compose.groupId}
                  onChange={(e) => setCompose((prev) => ({ ...prev, groupId: e.target.value }))}
                  className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                >
                  <option value="">選択してください</option>
                  {groups.map((group) => (
                    <option key={group.id} value={group.id}>
                      {group.name}
                    </option>
                  ))}
                </select>
                {groups.length === 0 && (
                  <p className="mt-1 text-xs text-slate-400">この施設には有効なグループがありません。</p>
                )}
              </div>
            )}
          </div>

          {compose.category === "個別" && (
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">宛先職員(複数選択可)</label>
              <div className="flex flex-wrap gap-2">
                {employees.length === 0 && <p className="text-xs text-slate-400">この施設に在籍職員がいません。</p>}
                {employees.map((emp) => (
                  <label
                    key={emp.employee_id}
                    className="flex items-center gap-1 rounded-lg border border-slate-300 px-2 py-1 text-xs"
                  >
                    <input
                      type="checkbox"
                      checked={compose.employeeIds.has(emp.employee_id)}
                      onChange={() => toggleEmployee(emp.employee_id)}
                    />
                    {emp.name}
                  </label>
                ))}
              </div>
            </div>
          )}

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">タイトル</label>
            <input
              type="text"
              value={compose.title}
              onChange={(e) => setCompose((prev) => ({ ...prev, title: e.target.value }))}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">本文</label>
            <textarea
              value={compose.body}
              onChange={(e) => setCompose((prev) => ({ ...prev, body: e.target.value }))}
              rows={4}
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
          </div>

          <label className="flex items-center gap-2 text-sm text-slate-700">
            <input
              type="checkbox"
              checked={compose.requiresReadConfirmation}
              onChange={(e) => setCompose((prev) => ({ ...prev, requiresReadConfirmation: e.target.checked }))}
            />
            既読確認を必須にする
          </label>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">定型返信選択肢(任意)</label>
            <div className="flex flex-wrap gap-2">
              {STANDARD_REPLY_OPTION_CHOICES.map((option) => (
                <label key={option} className="flex items-center gap-1 rounded-lg border border-slate-300 px-2 py-1 text-xs">
                  <input
                    type="checkbox"
                    checked={compose.replyOptions.has(option)}
                    onChange={() => toggleReplyOption(option)}
                  />
                  {option}
                </label>
              ))}
            </div>
          </div>

          {composeError && <p className="text-sm font-medium text-red-500">{composeError}</p>}
          {composeMessage && <p className="text-sm font-medium text-emerald-600">{composeMessage}</p>}

          <button
            onClick={handleSubmit}
            disabled={isSaving}
            className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
          >
            {isSaving ? "送信中…" : "送信"}
          </button>
        </div>

        <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">送信履歴(直近50件)</h3>
          {noticesError && <p className="text-sm font-medium text-red-500">{noticesError}</p>}
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">日時</th>
                  <th className="px-4 py-3">カテゴリ</th>
                  <th className="px-4 py-3">タイトル</th>
                  <th className="px-4 py-3">既読確認</th>
                </tr>
              </thead>
              <tbody>
                {notices.length === 0 && (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-center text-slate-400">
                      お知らせはまだありません
                    </td>
                  </tr>
                )}
                {notices.map((notice) => (
                  <tr key={notice.id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                    <td className="px-4 py-3 text-slate-500">{new Date(notice.created_at).toLocaleString("ja-JP")}</td>
                    <td className="px-4 py-3 text-slate-700">{NOTICE_CATEGORY_LABELS[notice.category]}</td>
                    <td className="px-4 py-3 font-medium text-slate-800">{notice.title}</td>
                    <td className="px-4 py-3 text-slate-500">{notice.requires_read_confirmation ? "必須" : "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </main>
    </div>
  );
}
