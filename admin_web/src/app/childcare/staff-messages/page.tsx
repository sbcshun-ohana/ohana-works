"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 園内連絡(156/213-215・設計書§7/8/10)。
// 一覧=自施設の全職員が閲覧可(掲示板方式)。確認ボタン=宛先該当者のみ。
// 確認状況の集計=送信者本人と主任以上のみ(RPC側で制御)。
// クラス担任設定(§5.4)=主任以上。Kids側と同じRPC群を使用しロジックは複製しない。

type StaffMessage = {
  message_id: string;
  body: string;
  target_date: string | null;
  created_at: string;
  author_employee_id: string;
  author_name: string;
  target_labels: string[];
  is_addressed_to_me: boolean;
  acknowledged_by_me: boolean;
  ack_count: number;
  addressed_count: number;
};

type StaffMember = { employee_id: string; name: string };
type TimeBand = { id: string; name: string };
type ClassRow = { class_id: string; class_name: string };

function ChildcareStaffMessagesPageContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;

  const [messages, setMessages] = useState<StaffMessage[]>([]);
  const [includeArchive, setIncludeArchive] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  // 作成フォーム
  const [body, setBody] = useState("");
  const [facility, setFacility] = useState(false);
  const [bandIds, setBandIds] = useState<Set<string>>(new Set());
  const [employeeIds, setEmployeeIds] = useState<Set<string>>(new Set());
  const [classIds, setClassIds] = useState<Set<string>>(new Set());
  const [targetDate, setTargetDate] = useState("");
  const [bands, setBands] = useState<TimeBand[]>([]);
  const [staff, setStaff] = useState<StaffMember[]>([]);
  const [classes, setClasses] = useState<ClassRow[]>([]);
  const [classMessaging, setClassMessaging] = useState(false);
  const [isSending, setIsSending] = useState(false);

  // 確認状況(送信者/主任のみ)
  const [ackDetail, setAckDetail] = useState<{ messageId: string; rows: { name: string; acknowledged: boolean }[] } | null>(null);
  // クラス担任設定
  const [homerooms, setHomerooms] = useState<Record<string, string[]>>({}); // class_id -> employee_ids
  const [showHomeroom, setShowHomeroom] = useState(false);
  const [myEmployeeId, setMyEmployeeId] = useState<string | null>(null);

  function showToast(m: string) {
    setToast(m);
    window.setTimeout(() => setToast((c) => (c === m ? null : c)), 3500);
  }

  useEffect(() => {
    function load() {
      if (!selectedOffice) return null;
      setError(null);
      return createClient();
    }
    const supabase = load();
    if (!supabase) return;
    supabase
      .rpc("fetch_staff_messages", { p_office_id: selectedOffice, p_include_archive: includeArchive })
      .then(({ data, error }) => {
        if (error) {
          setError(error.message);
          return;
        }
        setMessages((data ?? []) as StaffMessage[]);
      });
    supabase
      .from("staff_time_bands")
      .select("id, name")
      .eq("office_id", selectedOffice)
      .order("sort_order")
      .then(({ data }) => setBands((data ?? []) as TimeBand[]));
    supabase
      .rpc("fetch_childcare_office_staff", { p_office_id: selectedOffice })
      .then(({ data }) => setStaff((data ?? []) as StaffMember[]));
    supabase
      .rpc("is_feature_enabled_for_office", {
        p_feature_key: "class_messaging_enabled",
        p_office_id: selectedOffice,
      })
      .then(({ data }) => setClassMessaging(data === true));
    supabase
      .rpc("fetch_childcare_classes", { p_office_id: selectedOffice })
      .then(({ data }) =>
        setClasses(((data ?? []) as { class_id: string; class_name: string }[]).map((c) => ({
          class_id: c.class_id,
          class_name: c.class_name,
        }))),
      );
    supabase.rpc("my_employee_id").then(({ data }) => setMyEmployeeId((data as string) ?? null));
    supabase
      .from("class_homeroom_assignments")
      .select("class_id, employee_id, unassigned_at")
      .is("unassigned_at", null)
      .then(({ data }) => {
        const map: Record<string, string[]> = {};
        for (const r of (data ?? []) as { class_id: string; employee_id: string }[]) {
          (map[r.class_id] ??= []).push(r.employee_id);
        }
        setHomerooms(map);
      });
  }, [selectedOffice, includeArchive, reloadToken]);

  const needsTargetDate = bandIds.size > 0 || classIds.size > 0;

  async function send() {
    if (!selectedOffice) return;
    const targets = [
      ...(facility ? [{ type: "facility" }] : []),
      ...[...bandIds].map((b) => ({ type: "band", band_id: b })),
      ...[...employeeIds].map((e) => ({ type: "individual", employee_id: e })),
      ...[...classIds].map((c) => ({ type: "class", class_id: c })),
    ];
    if (!body.trim()) {
      showToast("本文を入力してください");
      return;
    }
    if (targets.length === 0) {
      showToast("宛先を1つ以上選択してください");
      return;
    }
    if (needsTargetDate && !targetDate) {
      showToast("時間帯・クラス宛てには対象日が必要です");
      return;
    }
    setIsSending(true);
    const { error } = await createClient().rpc("create_staff_message", {
      p_office_id: selectedOffice,
      p_body: body.trim(),
      p_target_date: needsTargetDate ? targetDate : null,
      p_targets: targets,
    });
    setIsSending(false);
    if (error) {
      showToast(`送信に失敗しました: ${error.message}`);
      return;
    }
    setBody("");
    setFacility(false);
    setBandIds(new Set());
    setEmployeeIds(new Set());
    setClassIds(new Set());
    showToast("園内連絡を送信しました(宛先該当者へプッシュされます)");
    setReloadToken((t) => t + 1);
  }

  async function acknowledge(messageId: string) {
    const { error } = await createClient().rpc("acknowledge_staff_message", { p_message_id: messageId });
    if (error) {
      showToast(`確認の記録に失敗しました: ${error.message}`);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function remove(messageId: string) {
    if (!window.confirm("この連絡を削除しますか?(一覧から非表示・記録は残ります)")) return;
    const { error } = await createClient().rpc("delete_staff_message", { p_message_id: messageId });
    if (error) {
      showToast(`削除に失敗しました: ${error.message}`);
      return;
    }
    setReloadToken((t) => t + 1);
  }

  async function openAckDetail(m: StaffMessage) {
    const { data, error } = await createClient().rpc("fetch_staff_message_ack_summary", {
      p_message_id: m.message_id,
    });
    if (error) {
      showToast(`確認状況の取得に失敗しました(送信者・主任以上のみ): ${error.message}`);
      return;
    }
    const nameById = new Map(staff.map((s) => [s.employee_id, s.name]));
    setAckDetail({
      messageId: m.message_id,
      rows: ((data ?? []) as { employee_id: string; acknowledged: boolean }[]).map((r) => ({
        name: nameById.get(r.employee_id) ?? "職員",
        acknowledged: r.acknowledged,
      })),
    });
  }

  async function toggleHomeroom(classId: string, employeeId: string, assign: boolean) {
    const { error } = await createClient().rpc("set_class_homeroom", {
      p_class_id: classId,
      p_employee_id: employeeId,
      p_assign: assign,
    });
    if (error) {
      showToast(`担任設定に失敗しました(主任以上のみ): ${error.message}`);
      return;
    }
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
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-lg font-bold text-slate-800">園内連絡</h2>
          <div className="flex items-center gap-3">
            <label className="flex items-center gap-1 text-xs text-slate-500">
              <input
                type="checkbox"
                checked={includeArchive}
                onChange={(e) => setIncludeArchive(e.target.checked)}
              />
              アーカイブ(全期間)を表示
            </label>
            {isManager && (
              <button
                onClick={() => setShowHomeroom((v) => !v)}
                className="rounded-lg border border-slate-300 px-3 py-1.5 text-xs text-slate-600 hover:bg-slate-50"
              >
                クラス担任設定
              </button>
            )}
          </div>
        </div>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}
        {toast && <p className="rounded-lg bg-slate-800 px-4 py-2 text-sm font-medium text-white">{toast}</p>}

        {/* クラス担任設定(主任以上・§5.4) */}
        {showHomeroom && isManager && (
          <div className="space-y-3 rounded-2xl bg-white p-5 shadow-sm">
            <h3 className="text-sm font-bold text-slate-700">クラス担任設定(クラス宛て連絡の宛先になります)</h3>
            {classes.map((c) => (
              <div key={c.class_id} className="flex flex-wrap items-center gap-2">
                <span className="w-24 text-sm font-medium text-slate-700">{c.class_name}</span>
                {staff.map((s) => {
                  const assigned = (homerooms[c.class_id] ?? []).includes(s.employee_id);
                  return (
                    <button
                      key={s.employee_id}
                      onClick={() => toggleHomeroom(c.class_id, s.employee_id, !assigned)}
                      className={`rounded-full px-3 py-1 text-xs font-semibold ${
                        assigned
                          ? "bg-emerald-100 text-emerald-700"
                          : "border border-slate-200 text-slate-500 hover:bg-slate-50"
                      }`}
                    >
                      {s.name}
                    </button>
                  );
                })}
              </div>
            ))}
          </div>
        )}

        {/* 新規送信 */}
        <div className="space-y-3 rounded-2xl bg-white p-5 shadow-sm">
          <h3 className="text-sm font-bold text-slate-700">新規連絡</h3>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={3}
            placeholder="連絡内容(例: 明日の早番の方へ…)"
            className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
          />
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="text-xs font-medium text-slate-500">宛先:</span>
            <button
              onClick={() => setFacility((v) => !v)}
              className={`rounded-full px-3 py-1 text-xs font-semibold ${
                facility ? "bg-sky-100 text-sky-700" : "border border-slate-200 text-slate-500 hover:bg-slate-50"
              }`}
            >
              施設全体
            </button>
            {bands.map((b) => (
              <button
                key={b.id}
                onClick={() =>
                  setBandIds((cur) => {
                    const next = new Set(cur);
                    if (next.has(b.id)) {
                      next.delete(b.id);
                    } else {
                      next.add(b.id);
                    }
                    return next;
                  })
                }
                className={`rounded-full px-3 py-1 text-xs font-semibold ${
                  bandIds.has(b.id)
                    ? "bg-sky-100 text-sky-700"
                    : "border border-slate-200 text-slate-500 hover:bg-slate-50"
                }`}
              >
                {b.name}
              </button>
            ))}
            {classMessaging &&
              classes.map((c) => (
                <button
                  key={c.class_id}
                  onClick={() =>
                    setClassIds((cur) => {
                      const next = new Set(cur);
                      if (next.has(c.class_id)) {
                        next.delete(c.class_id);
                      } else {
                        next.add(c.class_id);
                      }
                      return next;
                    })
                  }
                  className={`rounded-full px-3 py-1 text-xs font-semibold ${
                    classIds.has(c.class_id)
                      ? "bg-emerald-100 text-emerald-700"
                      : "border border-slate-200 text-slate-500 hover:bg-slate-50"
                  }`}
                >
                  {c.class_name}
                </button>
              ))}
            {staff.map((s) => (
              <button
                key={s.employee_id}
                onClick={() =>
                  setEmployeeIds((cur) => {
                    const next = new Set(cur);
                    if (next.has(s.employee_id)) {
                      next.delete(s.employee_id);
                    } else {
                      next.add(s.employee_id);
                    }
                    return next;
                  })
                }
                className={`rounded-full px-3 py-1 text-xs font-semibold ${
                  employeeIds.has(s.employee_id)
                    ? "bg-amber-100 text-amber-800"
                    : "border border-slate-200 text-slate-500 hover:bg-slate-50"
                }`}
              >
                {s.name}
              </button>
            ))}
          </div>
          <div className="flex flex-wrap items-center gap-3">
            {needsTargetDate && (
              <div>
                <label className="mr-1 text-xs font-medium text-slate-500">対象日(時間帯・クラス宛てに必須)</label>
                <input
                  type="date"
                  value={targetDate}
                  onChange={(e) => setTargetDate(e.target.value)}
                  className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>
            )}
            <button
              onClick={send}
              disabled={isSending}
              className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700 disabled:opacity-60"
            >
              {isSending ? "送信中…" : "送信する"}
            </button>
          </div>
        </div>

        {/* 一覧 */}
        <div className="space-y-3">
          {messages.length === 0 && (
            <p className="text-sm text-slate-400">
              {includeArchive ? "連絡はありません" : "直近30日の連絡はありません"}
            </p>
          )}
          {messages.map((m) => {
            const needsAck = m.is_addressed_to_me && !m.acknowledged_by_me;
            return (
              <div
                key={m.message_id}
                className={`space-y-2 rounded-2xl bg-white p-5 shadow-sm ${
                  needsAck ? "border-2 border-amber-400" : ""
                }`}
              >
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-bold text-slate-800">{m.author_name}</span>
                  <span className="text-xs text-slate-400">
                    {new Date(m.created_at).toLocaleString("ja-JP", {
                      month: "numeric",
                      day: "numeric",
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </span>
                  {(m.target_labels ?? []).map((label, i) => (
                    <span key={i} className="rounded-full bg-sky-50 px-2 py-0.5 text-xs font-semibold text-sky-700">
                      宛先: {label}
                      {m.target_date ? `(${m.target_date.slice(5).replace("-", "/")})` : ""}
                    </span>
                  ))}
                  <span className="ml-auto" />
                  {(m.author_employee_id === myEmployeeId || isManager) && (
                    <button onClick={() => remove(m.message_id)} className="text-xs text-red-500 hover:underline">
                      削除
                    </button>
                  )}
                </div>
                <p className="text-sm whitespace-pre-wrap text-slate-700">{m.body}</p>
                <div className="flex items-center gap-3">
                  <button
                    onClick={() => openAckDetail(m)}
                    className="text-xs text-slate-500 hover:underline"
                    title="確認状況(送信者・主任以上のみ)"
                  >
                    確認 {m.ack_count}/{m.addressed_count}
                  </button>
                  <span className="ml-auto" />
                  {needsAck ? (
                    <button
                      onClick={() => acknowledge(m.message_id)}
                      className="rounded-lg bg-emerald-600 px-4 py-1.5 text-sm font-semibold text-white hover:bg-emerald-700"
                    >
                      ✓ 確認しました
                    </button>
                  ) : m.is_addressed_to_me ? (
                    <span className="text-xs font-semibold text-emerald-600">✓ 確認済み</span>
                  ) : null}
                </div>
                {ackDetail?.messageId === m.message_id && (
                  <div className="rounded-xl bg-slate-50 p-3 text-xs">
                    <div className="mb-1 flex items-center justify-between">
                      <span className="font-semibold text-slate-600">宛先該当者の確認状況</span>
                      <button onClick={() => setAckDetail(null)} className="text-slate-400 hover:underline">
                        閉じる
                      </button>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      {ackDetail.rows.map((r, i) => (
                        <span
                          key={i}
                          className={`rounded-full px-2 py-0.5 font-semibold ${
                            r.acknowledged ? "bg-emerald-100 text-emerald-700" : "bg-red-50 text-red-600"
                          }`}
                        >
                          {r.acknowledged ? "✓" : "未"} {r.name}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </main>
    </div>
  );
}

export default function ChildcareStaffMessagesPage() {
  return (
    <Suspense fallback={null}>
      <ChildcareStaffMessagesPageContent />
    </Suspense>
  );
}
