"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import type {
  ChildForAssignment,
  GuardianInvitationRow,
  GuardianRow,
} from "@/lib/types";
import { GUARDIAN_INVITATION_STATUS_LABELS } from "@/lib/types";

function ChildcareGuardiansPageContent() {
  const { offices, officesError, selectedOffice, setSelectedOffice } = useChildcareOffices();

  const [guardians, setGuardians] = useState<GuardianRow[]>([]);
  const [invitations, setInvitations] = useState<GuardianInvitationRow[]>([]);
  const [children, setChildren] = useState<ChildForAssignment[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [rowsError, setRowsError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [newInviteChildId, setNewInviteChildId] = useState("");
  const [newInviteRole, setNewInviteRole] = useState<"primary" | "additional">("primary");
  const [isIssuing, setIsIssuing] = useState(false);
  const [issuedInvite, setIssuedInvite] = useState<{ token: string; expiresAt: string } | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  useEffect(() => {
    function loadRows() {
      if (!selectedOffice) return null;
      setIsLoading(true);
      setRowsError(null);
      return createClient();
    }

    const supabase = loadRows();
    if (!supabase) return;

    supabase.rpc("fetch_guardians_for_office", { p_office_id: selectedOffice }).then(({ data, error }) => {
      setIsLoading(false);
      if (error) {
        setRowsError(error.message);
        return;
      }
      setGuardians((data ?? []) as GuardianRow[]);
    });
    supabase
      .rpc("fetch_pending_guardian_invitations", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        if (!error) setInvitations((data ?? []) as GuardianInvitationRow[]);
      });
    supabase.rpc("fetch_children_for_office", { p_office_id: selectedOffice }).then(({ data, error }) => {
      if (!error) setChildren((data ?? []) as ChildForAssignment[]);
    });
  }, [selectedOffice, reloadToken]);

  async function toggleSuspend(guardian: GuardianRow) {
    setActionError(null);
    const supabase = createClient();
    if (guardian.status === "active") {
      const reason = window.prompt("停止理由を入力してください(必須)");
      if (!reason) return;
      const { error } = await supabase.rpc("suspend_guardian_account", {
        p_guardian_id: guardian.guardian_id,
        p_reason: reason,
      });
      if (error) {
        setActionError(error.message);
        return;
      }
    } else {
      const { error } = await supabase.rpc("reactivate_guardian_account", {
        p_guardian_id: guardian.guardian_id,
      });
      if (error) {
        setActionError(error.message);
        return;
      }
    }
    setReloadToken((t) => t + 1);
  }

  async function issueInvitation() {
    if (!newInviteChildId) return;
    setIsIssuing(true);
    setActionError(null);
    setIssuedInvite(null);
    const supabase = createClient();
    const { data, error } = await supabase.rpc("create_guardian_invitation_by_staff", {
      p_child_id: newInviteChildId,
      p_role: newInviteRole,
      p_ttl_hours: 72,
    });
    setIsIssuing(false);
    if (error) {
      setActionError(error.message);
      return;
    }
    const result = (Array.isArray(data) ? data[0] : data) as { token: string; expires_at: string };
    setIssuedInvite({ token: result.token, expiresAt: result.expires_at });
    setReloadToken((t) => t + 1);
  }

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">保育業務の施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }
  if (offices !== null && offices.length === 0) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-slate-500">保育業務機能が有効な施設がありません。</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-6 p-6">
        <h2 className="text-lg font-bold text-slate-800">保護者管理・招待管理</h2>

        <div className="flex flex-wrap items-end gap-4 rounded-2xl bg-white p-4 shadow-sm">
          <div>
            <label className="mb-1 block text-xs font-medium text-slate-500">施設</label>
            <select
              value={selectedOffice}
              onChange={(e) => setSelectedOffice(e.target.value)}
              className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            >
              {offices?.map((office) => (
                <option key={office.office_id} value={office.office_id}>
                  {office.office_name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {rowsError && <p className="text-sm font-medium text-red-500">{rowsError}</p>}
        {actionError && <p className="text-sm font-medium text-red-500">{actionError}</p>}

        <div className="space-y-3 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">保護者一覧</h3>
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">氏名</th>
                  <th className="px-4 py-3">電話番号</th>
                  <th className="px-4 py-3">メール</th>
                  <th className="px-4 py-3">紐づく園児</th>
                  <th className="px-4 py-3">状態</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody>
                {isLoading && (
                  <tr>
                    <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                      読み込み中…
                    </td>
                  </tr>
                )}
                {!isLoading && guardians.length === 0 && (
                  <tr>
                    <td colSpan={6} className="px-4 py-6 text-center text-slate-400">
                      保護者が登録されていません
                    </td>
                  </tr>
                )}
                {!isLoading &&
                  guardians.map((g) => (
                    <tr key={g.guardian_id} className="border-b border-slate-100 last:border-0 hover:bg-slate-50">
                      <td className="px-4 py-3 font-medium text-slate-800">{g.name}</td>
                      <td className="px-4 py-3 text-slate-500">{g.phone ?? "—"}</td>
                      <td className="px-4 py-3 text-slate-500">{g.email ?? "—"}</td>
                      <td className="px-4 py-3 text-slate-500">{g.linked_children ?? "—"}</td>
                      <td className="px-4 py-3">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
                            g.status === "active" ? "bg-emerald-50 text-emerald-700" : "bg-red-50 text-red-600"
                          }`}
                        >
                          {g.status === "active" ? "有効" : "停止中"}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-right">
                        <button
                          onClick={() => toggleSuspend(g)}
                          className="rounded-lg border border-slate-300 px-3 py-1 text-xs font-medium text-slate-600 hover:bg-slate-100"
                        >
                          {g.status === "active" ? "停止する" : "再開する"}
                        </button>
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        </div>

        <div className="space-y-4 rounded-2xl bg-white p-6 shadow-sm">
          <h3 className="text-base font-bold text-slate-800">新規招待</h3>
          <div className="flex flex-wrap items-end gap-4">
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">園児</label>
              <select
                value={newInviteChildId}
                onChange={(e) => setNewInviteChildId(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              >
                <option value="">選択してください</option>
                {children.map((c) => (
                  <option key={c.child_id} value={c.child_id}>
                    {c.display_name}
                    {c.honorific_suffix ?? ""}
                    {c.class_name ? `(${c.class_name})` : ""}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">役割</label>
              <select
                value={newInviteRole}
                onChange={(e) => setNewInviteRole(e.target.value as "primary" | "additional")}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              >
                <option value="primary">主たる保護者</option>
                <option value="additional">追加保護者</option>
              </select>
            </div>
            <button
              onClick={issueInvitation}
              disabled={isIssuing || !newInviteChildId}
              className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
            >
              {isIssuing ? "発行中…" : "招待を発行"}
            </button>
          </div>

          {issuedInvite && (
            <div className="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
              <p className="font-semibold">
                招待コードはこの画面でのみ表示されます。保護者へ直接お伝えください(スクリーンショット等での共有は避けてください)。
              </p>
              <p className="mt-2 break-all font-mono text-xs">{issuedInvite.token}</p>
              <p className="mt-1 text-xs">
                有効期限: {new Date(issuedInvite.expiresAt).toLocaleString("ja-JP")}
              </p>
            </div>
          )}

          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                  <th className="px-4 py-3">対象園児</th>
                  <th className="px-4 py-3">役割</th>
                  <th className="px-4 py-3">期限</th>
                  <th className="px-4 py-3">状態</th>
                </tr>
              </thead>
              <tbody>
                {invitations.length === 0 && (
                  <tr>
                    <td colSpan={4} className="px-4 py-6 text-center text-slate-400">
                      招待履歴はありません
                    </td>
                  </tr>
                )}
                {invitations.map((inv) => (
                  <tr key={inv.invitation_id} className="border-b border-slate-100 last:border-0">
                    <td className="px-4 py-3">{inv.child_display_name}</td>
                    <td className="px-4 py-3 text-slate-500">
                      {inv.role === "primary" ? "主たる保護者" : "追加保護者"}
                    </td>
                    <td className="px-4 py-3 text-slate-500">
                      {new Date(inv.expires_at).toLocaleString("ja-JP")}
                    </td>
                    <td className="px-4 py-3 text-slate-500">{GUARDIAN_INVITATION_STATUS_LABELS[inv.status]}</td>
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

export default function ChildcareGuardiansPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareGuardiansPageContent />
    </Suspense>
  );
}
