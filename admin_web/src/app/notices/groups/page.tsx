"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import {
  STAFF_GROUP_TYPE_LABELS,
  type ManageableOffice,
  type OfficeEmployee,
  type StaffGroupMemberRow,
  type StaffGroupRow,
  type StaffGroupType,
} from "@/lib/types";

const GROUP_TYPE_OPTIONS: StaffGroupType[] = ["project_team", "class_team", "custom"];

export default function StaffGroupsPage() {
  const [offices, setOffices] = useState<ManageableOffice[] | null>(null);
  const [officesError, setOfficesError] = useState<string | null>(null);
  const [selectedOffice, setSelectedOffice] = useState<string>("");

  const [employees, setEmployees] = useState<OfficeEmployee[]>([]);

  const [groups, setGroups] = useState<StaffGroupRow[]>([]);
  const [groupsError, setGroupsError] = useState<string | null>(null);
  const [groupsReloadToken, setGroupsReloadToken] = useState(0);

  const [selectedGroupId, setSelectedGroupId] = useState<string>("");
  const [members, setMembers] = useState<StaffGroupMemberRow[]>([]);
  const [membersError, setMembersError] = useState<string | null>(null);
  const [membersReloadToken, setMembersReloadToken] = useState(0);
  const [memberToggleId, setMemberToggleId] = useState<string | null>(null);

  const [newGroupType, setNewGroupType] = useState<StaffGroupType>("project_team");
  const [newGroupName, setNewGroupName] = useState("");
  const [newGroupMemberIds, setNewGroupMemberIds] = useState<Set<string>>(new Set());
  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);

  const [archivingId, setArchivingId] = useState<string | null>(null);
  const [archiveError, setArchiveError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase.rpc("fetch_my_manageable_offices").then(({ data, error }) => {
      if (error) {
        setOfficesError(error.message);
        return;
      }
      const list = (data ?? []) as ManageableOffice[];
      setOffices(list);
      if (list.length > 0) setSelectedOffice(list[0].id);
    });
  }, []);

  useEffect(() => {
    function resetForOfficeChange() {
      setSelectedGroupId("");
      if (!selectedOffice) {
        setEmployees([]);
        setGroups([]);
      }
    }
    resetForOfficeChange();
    if (!selectedOffice) {
      return;
    }
    const supabase = createClient();
    supabase.rpc("fetch_office_employees", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (!error) setEmployees((data ?? []) as OfficeEmployee[]);
    });
  }, [selectedOffice]);

  useEffect(() => {
    if (!selectedOffice) return;
    const supabase = createClient();
    supabase
      .from("staff_groups")
      .select("id, office_id, group_type, name, related_class_id, is_active, created_at, archived_at")
      .eq("office_id", selectedOffice)
      .order("is_active", { ascending: false })
      .order("created_at", { ascending: false })
      .then(({ data, error }) => {
        if (error) {
          setGroupsError(error.message);
          return;
        }
        setGroups((data ?? []) as StaffGroupRow[]);
      });
  }, [selectedOffice, groupsReloadToken]);

  useEffect(() => {
    function clearMembers() {
      setMembers([]);
    }
    if (!selectedGroupId) {
      clearMembers();
      return;
    }
    const supabase = createClient();
    supabase
      .from("staff_group_members")
      .select("id, group_id, employee_id, added_at, removed_at")
      .eq("group_id", selectedGroupId)
      .is("removed_at", null)
      .then(({ data, error }) => {
        if (error) {
          setMembersError(error.message);
          return;
        }
        setMembers((data ?? []) as StaffGroupMemberRow[]);
      });
  }, [selectedGroupId, membersReloadToken]);

  function toggleNewGroupMember(employeeId: string) {
    setNewGroupMemberIds((prev) => {
      const next = new Set(prev);
      if (next.has(employeeId)) next.delete(employeeId);
      else next.add(employeeId);
      return next;
    });
  }

  async function handleCreateGroup() {
    setCreateError(null);
    if (!newGroupName.trim()) {
      setCreateError("グループ名を入力してください。");
      return;
    }
    setIsCreating(true);
    const supabase = createClient();
    const { error } = await supabase.rpc("create_staff_group", {
      p_office_id: selectedOffice,
      p_group_type: newGroupType,
      p_name: newGroupName,
      p_related_class_id: null,
      p_member_employee_ids: Array.from(newGroupMemberIds),
    });
    setIsCreating(false);
    if (error) {
      setCreateError(error.message);
      return;
    }
    setNewGroupName("");
    setNewGroupMemberIds(new Set());
    setGroupsReloadToken((t) => t + 1);
  }

  async function handleArchiveGroup(groupId: string) {
    setArchiveError(null);
    setArchivingId(groupId);
    const supabase = createClient();
    const { error } = await supabase.rpc("archive_staff_group", { p_group_id: groupId });
    setArchivingId(null);
    if (error) {
      setArchiveError(error.message);
      return;
    }
    setGroupsReloadToken((t) => t + 1);
  }

  async function handleToggleMember(employeeId: string, isCurrentlyMember: boolean) {
    setMembersError(null);
    setMemberToggleId(employeeId);
    const supabase = createClient();
    const { error } = await supabase.rpc("update_staff_group_members", {
      p_group_id: selectedGroupId,
      p_add_employee_ids: isCurrentlyMember ? [] : [employeeId],
      p_remove_employee_ids: isCurrentlyMember ? [employeeId] : [],
    });
    setMemberToggleId(null);
    if (error) {
      setMembersError(error.message);
      return;
    }
    setMembersReloadToken((t) => t + 1);
  }

  const selectedGroup = groups.find((g) => g.id === selectedGroupId) ?? null;
  const memberEmployeeIds = new Set(members.map((m) => m.employee_id));

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
          <h2 className="text-lg font-bold text-slate-800">グループ管理</h2>
          <Link href="/notices" className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100">
            お知らせ一覧へ戻る
          </Link>
        </div>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices?.map((office) => (
                <option key={office.id} value={office.id}>
                  {office.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">新規グループ作成</h3>
          <div className="flex flex-wrap gap-4">
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">種別</label>
              <select
                value={newGroupType}
                onChange={(e) => setNewGroupType(e.target.value as StaffGroupType)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              >
                {GROUP_TYPE_OPTIONS.map((type) => (
                  <option key={type} value={type}>
                    {STAFF_GROUP_TYPE_LABELS[type]}
                  </option>
                ))}
              </select>
            </div>
            <div className="flex-1">
              <label className="mb-1 block text-xs font-medium text-slate-500">グループ名</label>
              <input
                type="text"
                value={newGroupName}
                onChange={(e) => setNewGroupName(e.target.value)}
                className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
            </div>
          </div>

          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">初期メンバー(複数選択可・後から変更できます)</label>
            <div className="flex flex-wrap gap-2">
              {employees.length === 0 && <p className="text-xs text-slate-400">この施設に在籍職員がいません。</p>}
              {employees.map((emp) => (
                <label key={emp.employee_id} className="flex items-center gap-1 rounded-lg border border-slate-300 px-2 py-1 text-xs">
                  <input
                    type="checkbox"
                    checked={newGroupMemberIds.has(emp.employee_id)}
                    onChange={() => toggleNewGroupMember(emp.employee_id)}
                  />
                  {emp.name}
                </label>
              ))}
            </div>
          </div>

          {createError && <p className="text-sm font-medium text-red-500">{createError}</p>}

          <button
            onClick={handleCreateGroup}
            disabled={isCreating}
            className="rounded-lg bg-sky-500 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-600 disabled:opacity-60"
          >
            {isCreating ? "作成中…" : "グループを作成"}
          </button>
        </div>

        <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">グループ一覧</h3>
          {groupsError && <p className="text-sm font-medium text-red-500">{groupsError}</p>}
          {archiveError && <p className="text-sm font-medium text-red-500">{archiveError}</p>}
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">グループ名</th>
                  <th className="px-4 py-3">種別</th>
                  <th className="px-4 py-3">状態</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody>
                {groups.length === 0 && (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-center text-slate-400">
                      グループはまだありません
                    </td>
                  </tr>
                )}
                {groups.map((group) => (
                  <tr key={group.id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                    <td className="px-4 py-3 font-medium text-slate-800">
                      <button onClick={() => setSelectedGroupId(group.id)} className="hover:underline">
                        {group.name}
                      </button>
                    </td>
                    <td className="px-4 py-3 text-slate-600">{STAFF_GROUP_TYPE_LABELS[group.group_type]}</td>
                    <td className="px-4 py-3">
                      {group.is_active ? (
                        <span className="rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700">運用中</span>
                      ) : (
                        <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">終了済み</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <div className="flex justify-end gap-2">
                        <button
                          onClick={() => setSelectedGroupId(group.id)}
                          className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                        >
                          メンバー編集
                        </button>
                        {group.is_active && (
                          <button
                            onClick={() => handleArchiveGroup(group.id)}
                            disabled={archivingId === group.id}
                            className="rounded-lg border border-red-200 px-3 py-1 text-xs font-medium text-red-600 hover:bg-red-50 disabled:opacity-60"
                          >
                            {archivingId === group.id ? "終了中…" : "グループを終了"}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {selectedGroup && (
          <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
            <h3 className="text-base font-bold text-slate-800">
              「{selectedGroup.name}」のメンバー編集
              {!selectedGroup.is_active && <span className="ml-2 text-xs font-normal text-slate-400">(終了済みグループ)</span>}
            </h3>
            <p className="text-xs text-slate-500">
              チェックを外すとメンバーから除外されますが、過去に送信済みのグループ宛お知らせの既読・返信状況には影響しません。
            </p>
            {membersError && <p className="text-sm font-medium text-red-500">{membersError}</p>}
            <div className="flex flex-wrap gap-2">
              {employees.map((emp) => {
                const isMember = memberEmployeeIds.has(emp.employee_id);
                return (
                  <label key={emp.employee_id} className="flex items-center gap-1 rounded-lg border border-slate-300 px-2 py-1 text-xs">
                    <input
                      type="checkbox"
                      checked={isMember}
                      disabled={!selectedGroup.is_active || memberToggleId === emp.employee_id}
                      onChange={() => handleToggleMember(emp.employee_id, isMember)}
                    />
                    {emp.name}
                  </label>
                );
              })}
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
