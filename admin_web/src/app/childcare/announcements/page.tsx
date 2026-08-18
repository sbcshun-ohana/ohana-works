"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import {
  GUARDIAN_NOTICE_STATUS_LABELS,
  type GuardianNoticePreview,
  type GuardianNoticeReadSummary,
  type GuardianNoticeRow,
  type GuardianNoticeTargetInput,
  type GuardianNoticeUnreadRecipient,
  type SessionIdentity,
} from "@/lib/types";

// 園長以上(承認=送信ができる役職)。作成者がこの役職なら下書き→承認直行を出す(UX)。
// 実体の認可はRPC(is_guardian_notice_approver)で担保。
const APPROVER_ROLES = new Set(["director", "executive_director", "system_admin"]);

type DeliveryHistoryRow = {
  notice_id: string;
  title: string;
  status: string;
  scheduled_send_at: string | null;
  sent_at: string | null;
  revoked_at: string | null;
  target_summary: string;
  recipient_household_count: number;
};

// 履歴の日時は端末TZに依存させず必ずJST(Asia/Tokyo)で表示する。
function formatJst(iso: string): string {
  return new Date(iso).toLocaleString("ja-JP", {
    timeZone: "Asia/Tokyo",
    dateStyle: "short",
    timeStyle: "short",
  });
}

type ClassOption = { class_id: string; class_name: string };
type ChildOption = { child_id: string; display_name: string; class_name: string | null; enrollment_status: string };

const STATUS_BADGE: Record<string, string> = {
  draft: "bg-slate-100 text-slate-600",
  in_review: "bg-amber-100 text-amber-700",
  returned: "bg-rose-100 text-rose-700",
  approved: "bg-emerald-100 text-emerald-700",
};

function AnnouncementsPageContent() {
  // 施設選択はヘッダーに集約。selectedOffice は useChildcareOffices が ?office= に追随して供給する。
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;

  const [identity, setIdentity] = useState<SessionIdentity | null>(null);
  const canDirectApprove = APPROVER_ROLES.has(identity?.role_code ?? "");

  const [notices, setNotices] = useState<GuardianNoticeRow[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [listError, setListError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  // 208: 添付(PDF/画像)。新規フォームで選択→下書き作成時にアップロード。詳細では一覧表示+draft中の削除。
  const [pendingFiles, setPendingFiles] = useState<File[]>([]);
  const [attachments, setAttachments] = useState<
    { id: string; file_path: string; file_name: string; content_type: string | null }[]
  >([]);
  const selectedNotice = notices.find((n) => n.id === selectedId) ?? null;

  // 作成フォーム
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [targetAll, setTargetAll] = useState(false);
  const [targetOffices, setTargetOffices] = useState<Set<string>>(new Set());
  const [targetClasses, setTargetClasses] = useState<Set<string>>(new Set());
  const [targetChildren, setTargetChildren] = useState<Set<string>>(new Set());

  const [classes, setClasses] = useState<ClassOption[]>([]);
  const [children, setChildren] = useState<ChildOption[]>([]);
  const [childSearch, setChildSearch] = useState("");

  const [isBusy, setIsBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);
  const [actionMessage, setActionMessage] = useState<string | null>(null);

  // ダイアログ
  const [approveDialog, setApproveDialog] = useState<{ noticeId: string; preview: GuardianNoticePreview | null; loading: boolean; error: string | null } | null>(null);
  // 配信予定日時(datetime-local。空=承認時に即時配信)。
  const [approveScheduledAt, setApproveScheduledAt] = useState("");
  const [history, setHistory] = useState<DeliveryHistoryRow[]>([]);
  const [returnDialog, setReturnDialog] = useState<{ noticeId: string; reason: string } | null>(null);
  const [revokeDialog, setRevokeDialog] = useState<{ noticeId: string; reason: string } | null>(null);

  // 案b: 右一覧=作業中(未確定)、下=配信履歴(確定実績)に振り分け二重表示を排除する。
  //  確定 = 取消済み(revoked_at) または 配信済み(approved かつ sent_at)。作業中 = それ以外の全状態。
  const workingNotices = notices.filter((n) => !n.revoked_at && !(n.status === "approved" && n.sent_at));
  const finalizedHistory = history.filter((h) => !!h.revoked_at || !!h.sent_at);
  // 詳細パネルで予定変更/予約取消を出す条件(承認済み・未配信=配信予約中)。履歴表からは予約中を除外するため。
  const isScheduledUnsent =
    !!selectedNotice && selectedNotice.status === "approved" && !selectedNotice.sent_at && !selectedNotice.revoked_at;

  // 詳細(承認済み)の既読集計・未読世帯
  const [readSummary, setReadSummary] = useState<GuardianNoticeReadSummary | null>(null);
  const [unreadList, setUnreadList] = useState<GuardianNoticeUnreadRecipient[]>([]);

  useEffect(() => {
    createClient()
      .rpc("fetch_my_session_identity")
      .then(({ data, error }) => {
        if (!error && Array.isArray(data) && data.length > 0) setIdentity(data[0] as SessionIdentity);
      });
  }, []);

  // 施設がヘッダーで切り替わったら選択中のお知らせをリセットする(旧: 施設selectのonChangeで実施していた)。
  useEffect(() => {
    function resetSelectionOnOfficeChange() {
      setSelectedId(null);
    }
    resetSelectionOnOfficeChange();
  }, [selectedOffice]);

  // 施設のクラス・園児(宛先ピッカー用)。class/child は選択中施設の範囲で指定する。
  useEffect(() => {
    function loadTargets() {
      if (!selectedOffice) {
        setClasses([]);
        setChildren([]);
        return null;
      }
      return createClient();
    }
    const supabase = loadTargets();
    if (!supabase) return;
    supabase.rpc("fetch_childcare_classes", { p_office_id: selectedOffice }).then(({ data }) => {
      setClasses((data ?? []) as ClassOption[]);
    });
    supabase.rpc("fetch_children_for_office", { p_office_id: selectedOffice }).then(({ data }) => {
      setChildren(((data ?? []) as ChildOption[]).filter((c) => c.enrollment_status !== "退園済み"));
    });
  }, [selectedOffice]);

  // お知らせ一覧
  useEffect(() => {
    function startLoad() {
      if (!selectedOffice) return null;
      setIsLoading(true);
      return createClient();
    }
    const supabase = startLoad();
    if (!supabase) return;
    supabase
      .rpc("fetch_guardian_notices_for_staff", { p_office_id: selectedOffice })
      .then(({ data, error }) => {
        if (error) {
          setListError(error.message);
          setNotices([]);
        } else {
          setListError(null);
          setNotices((data ?? []) as GuardianNoticeRow[]);
        }
        setIsLoading(false);
      });
  }, [selectedOffice, reloadToken]);

  // 配信履歴(D-2)+ 予約中の予定変更/取消(D-1)用。scheduled_send_at/sent_at/宛先/世帯数を持つ。
  useEffect(() => {
    function load() {
      if (!selectedOffice) {
        setHistory([]);
        return;
      }
      createClient()
        .rpc("fetch_guardian_notice_delivery_history", { p_office_id: selectedOffice })
        .then(({ data, error }) => {
          if (error) {
            // 握り潰すと履歴が黙って空表示になるため、失敗はエラー表示で明示する。
            setHistory([]);
            setActionError(`配信履歴の取得に失敗しました: ${error.message}`);
          } else {
            setHistory((data ?? []) as DeliveryHistoryRow[]);
          }
        });
    }
    load();
  }, [selectedOffice, reloadToken]);

  // 選択中お知らせが承認済みなら既読集計・未読世帯を取得
  useEffect(() => {
    function startLoad() {
      if (!selectedNotice || selectedNotice.status !== "approved") {
        setReadSummary(null);
        setUnreadList([]);
        return null;
      }
      return createClient();
    }
    const supabase = startLoad();
    if (!supabase || !selectedNotice) return;
    supabase.rpc("fetch_guardian_notice_read_summary", { p_notice_id: selectedNotice.id }).then(({ data }) => {
      const row = Array.isArray(data) && data.length > 0 ? (data[0] as GuardianNoticeReadSummary) : null;
      setReadSummary(row);
    });
    supabase.rpc("fetch_guardian_notice_unread_recipients", { p_notice_id: selectedNotice.id }).then(({ data }) => {
      setUnreadList((data ?? []) as GuardianNoticeUnreadRecipient[]);
    });
    supabase
      .from("guardian_notice_attachments")
      .select("id, file_path, file_name, content_type")
      .eq("notice_id", selectedNotice.id)
      .order("sort_order")
      .then(({ data }) => setAttachments((data ?? []) as typeof attachments));
    // selectedId と status の変化のみで再取得する(オブジェクト全体を依存にすると過剰再取得)。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId, selectedNotice?.status, reloadToken]);

  function reload() {
    setReloadToken((t) => t + 1);
  }

  function resetForm() {
    setTitle("");
    setBody("");
    setTargetAll(false);
    setTargetOffices(new Set());
    setTargetClasses(new Set());
    setTargetChildren(new Set());
  }

  function toggle(set: Set<string>, id: string): Set<string> {
    const next = new Set(set);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    return next;
  }

  function buildTargets(): GuardianNoticeTargetInput[] {
    if (targetAll) return [{ type: "all" }];
    const t: GuardianNoticeTargetInput[] = [];
    targetOffices.forEach((id) => t.push({ type: "office", office_id: id }));
    targetClasses.forEach((id) => t.push({ type: "class", class_id: id }));
    targetChildren.forEach((id) => t.push({ type: "child", child_id: id }));
    return t;
  }

  const targetCount = targetAll
    ? 1
    : targetOffices.size + targetClasses.size + targetChildren.size;

  // 下書きを作成(戻り値=新規notice_id)。共通処理。
  async function createDraft(): Promise<string | null> {
    setActionError(null);
    setActionMessage(null);
    if (!title.trim() || !body.trim()) {
      setActionError("タイトルと本文を入力してください。");
      return null;
    }
    const targets = buildTargets();
    if (targets.length === 0) {
      setActionError("宛先を1つ以上選択してください。");
      return null;
    }
    const { data, error } = await createClient().rpc("create_guardian_notice", {
      p_title: title,
      p_body: body,
      p_targets: targets,
    });
    if (error) {
      setActionError(error.message);
      return null;
    }
    const noticeId = data as string;
    // 208: 選択済みファイルをアップロードして添付行を作成(失敗はエラー表示するが下書き自体は成立)
    for (let i = 0; i < pendingFiles.length; i++) {
      const f = pendingFiles[i];
      const ext = f.name.includes(".") ? f.name.slice(f.name.lastIndexOf(".")) : "";
      const path = `${noticeId}/${Date.now()}_${i}${ext}`;
      const { error: upErr } = await createClient()
        .storage.from("guardian-notice-attachments")
        .upload(path, f, { contentType: f.type || undefined });
      if (upErr) {
        setActionError(`添付「${f.name}」のアップロードに失敗しました: ${upErr.message}`);
        continue;
      }
      await createClient().from("guardian_notice_attachments").insert({
        notice_id: noticeId,
        file_path: path,
        file_name: f.name,
        content_type: f.type || null,
        file_size_bytes: f.size,
        sort_order: i,
      });
    }
    setPendingFiles([]);
    return noticeId;
  }

  async function openAttachment(filePath: string) {
    const { data, error } = await createClient()
      .storage.from("guardian-notice-attachments")
      .createSignedUrl(filePath, 300);
    if (error) {
      setActionError(`添付の表示に失敗しました: ${error.message}`);
      return;
    }
    window.open(data.signedUrl, "_blank");
  }

  async function deleteAttachment(att: { id: string; file_path: string }) {
    const supabase = createClient();
    await supabase.storage.from("guardian-notice-attachments").remove([att.file_path]);
    await supabase.from("guardian_notice_attachments").delete().eq("id", att.id);
    setAttachments((list) => list.filter((a) => a.id !== att.id));
  }

  async function handleSaveDraft() {
    setIsBusy(true);
    const id = await createDraft();
    setIsBusy(false);
    if (id) {
      resetForm();
      setActionMessage("下書きを保存しました。");
      reload();
      setSelectedId(id);
    }
  }

  async function handleSubmitNew() {
    setIsBusy(true);
    const id = await createDraft();
    if (id) {
      const { error } = await createClient().rpc("submit_guardian_notice", { p_notice_id: id });
      if (error) setActionError(error.message);
      else {
        resetForm();
        setActionMessage("承認申請しました。");
        reload();
        setSelectedId(id);
      }
    }
    setIsBusy(false);
  }

  // 作成フォームから「承認して送信」= 下書き作成→承認確認ダイアログ
  async function handleCreateThenApprove() {
    setIsBusy(true);
    const id = await createDraft();
    setIsBusy(false);
    if (id) {
      resetForm();
      reload();
      setSelectedId(id);
      openApproveDialog(id);
    }
  }

  async function openApproveDialog(noticeId: string) {
    setApproveDialog({ noticeId, preview: null, loading: true, error: null });
    const { data, error } = await createClient().rpc("preview_guardian_notice", { p_notice_id: noticeId });
    if (error) {
      setApproveDialog({ noticeId, preview: null, loading: false, error: error.message });
      return;
    }
    const row = Array.isArray(data) && data.length > 0 ? (data[0] as GuardianNoticePreview) : null;
    setApproveDialog({ noticeId, preview: row, loading: false, error: null });
  }

  async function confirmApprove() {
    if (!approveDialog) return;
    setIsBusy(true);
    // 予定日時が未来なら予約、空/過去なら即時配信(RPC側でも同判定)。
    const scheduled = approveScheduledAt ? `${approveScheduledAt}:00+09:00` : null;
    const { error } = await createClient().rpc("approve_guardian_notice", {
      p_notice_id: approveDialog.noticeId,
      p_scheduled_send_at: scheduled,
    });
    setIsBusy(false);
    if (error) {
      setApproveDialog({ ...approveDialog, error: error.message });
      return;
    }
    setApproveDialog(null);
    setApproveScheduledAt("");
    setActionMessage(scheduled ? "配信を予約しました。" : "承認して送信しました。");
    reload();
  }

  async function handleReschedule(noticeId: string) {
    const input = window.prompt("新しい配信予定日時(YYYY-MM-DD HH:MM)");
    if (!input) return;
    const iso = input.trim().replace(" ", "T");
    const { error } = await createClient().rpc("reschedule_guardian_notice", {
      p_notice_id: noticeId,
      p_scheduled_send_at: `${iso}:00+09:00`,
    });
    if (error) setActionError("予定変更に失敗しました(未配信の予約のみ変更できます)");
    else {
      setActionMessage("配信予定を変更しました。");
      reload();
    }
  }

  async function handleCancelSchedule(noticeId: string) {
    if (!window.confirm("この予約配信を取り消して下書きに戻します。よろしいですか?")) return;
    const { error } = await createClient().rpc("cancel_scheduled_guardian_notice", { p_notice_id: noticeId });
    if (error) setActionError("取消に失敗しました(未配信の予約のみ取り消せます)");
    else {
      setActionMessage("予約配信を取り消し、下書きに戻しました。");
      reload();
    }
  }

  async function handleSubmitExisting(noticeId: string) {
    setIsBusy(true);
    const { error } = await createClient().rpc("submit_guardian_notice", { p_notice_id: noticeId });
    setIsBusy(false);
    if (error) setActionError(error.message);
    else {
      setActionMessage("承認申請しました。");
      reload();
    }
  }

  async function confirmReturn() {
    if (!returnDialog) return;
    if (!returnDialog.reason.trim()) return;
    setIsBusy(true);
    const { error } = await createClient().rpc("return_guardian_notice", {
      p_notice_id: returnDialog.noticeId,
      p_reason: returnDialog.reason,
    });
    setIsBusy(false);
    if (error) setActionError(error.message);
    else {
      setReturnDialog(null);
      setActionMessage("差し戻しました。");
      reload();
    }
  }

  async function confirmRevoke() {
    if (!revokeDialog) return;
    if (!revokeDialog.reason.trim()) return;
    setIsBusy(true);
    const { error } = await createClient().rpc("revoke_guardian_notice", {
      p_notice_id: revokeDialog.noticeId,
      p_reason: revokeDialog.reason,
    });
    setIsBusy(false);
    if (error) setActionError(error.message);
    else {
      setRevokeDialog(null);
      setActionMessage("一斉配信を取り消しました。");
      reload();
    }
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
        <div>
          <h2 className="text-lg font-bold text-slate-800">一斉配信(保護者向け)</h2>
          <p className="mt-1 text-xs text-slate-500">
            保護者アプリへ一斉配信します。職員向けの連絡は上部メニューの「お知らせ(職員向け)」を使用してください。
          </p>
        </div>

        {actionError && <div className="rounded-lg bg-rose-50 px-4 py-2 text-sm text-rose-600">{actionError}</div>}
        {actionMessage && <div className="rounded-lg bg-emerald-50 px-4 py-2 text-sm text-emerald-700">{actionMessage}</div>}

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          {/* 作成フォーム(主任以上=is_manager) */}
          {isManager && (
            <section className="space-y-4 rounded-2xl bg-white p-5 shadow-sm">
              <h3 className="text-sm font-bold text-slate-700">新規の一斉配信を作成</h3>
              <p className="rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800">
                個別家庭の機微な案件(支払い・個別のトラブル等)は一斉配信に載せず、連絡帳・個別連絡をご利用ください。
              </p>
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-500">タイトル</label>
                <input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                  placeholder="例: 運動会のお知らせ"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-slate-500">本文</label>
                <textarea
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                  rows={5}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
                />
              </div>

              {/* 宛先ピッカー(階層・複数選択・全施設は排他) */}
              <div className="space-y-3 rounded-lg border border-slate-200 p-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-slate-600">宛先(複数・階層併用可)</span>
                  <span className="text-xs text-slate-400">選択中: {targetCount}件</span>
                </div>

                <label className="flex items-center gap-2 text-sm text-slate-700">
                  <input
                    type="checkbox"
                    checked={targetAll}
                    onChange={(e) => {
                      setTargetAll(e.target.checked);
                      if (e.target.checked) {
                        setTargetOffices(new Set());
                        setTargetClasses(new Set());
                        setTargetChildren(new Set());
                      }
                    }}
                  />
                  <span className="font-medium">全施設(他の宛先とは併用不可)</span>
                </label>

                <fieldset disabled={targetAll} className={targetAll ? "opacity-40" : ""}>
                  <div className="space-y-3">
                    <div>
                      <div className="mb-1 text-xs font-medium text-slate-500">施設単位</div>
                      <div className="flex flex-wrap gap-2">
                        {offices?.map((o) => (
                          <label key={o.office_id} className="flex items-center gap-1.5 rounded-md border border-slate-200 px-2 py-1 text-xs">
                            <input
                              type="checkbox"
                              checked={targetOffices.has(o.office_id)}
                              onChange={() => setTargetOffices(toggle(targetOffices, o.office_id))}
                            />
                            {o.office_name}
                          </label>
                        ))}
                      </div>
                    </div>

                    <div>
                      <div className="mb-1 text-xs font-medium text-slate-500">クラス単位(選択中施設: {classes.length}件)</div>
                      <div className="flex flex-wrap gap-2">
                        {classes.length === 0 && <span className="text-xs text-slate-400">クラスがありません。</span>}
                        {classes.map((c) => (
                          <label key={c.class_id} className="flex items-center gap-1.5 rounded-md border border-slate-200 px-2 py-1 text-xs">
                            <input
                              type="checkbox"
                              checked={targetClasses.has(c.class_id)}
                              onChange={() => setTargetClasses(toggle(targetClasses, c.class_id))}
                            />
                            {c.class_name}
                          </label>
                        ))}
                      </div>
                    </div>

                    <div>
                      <div className="mb-1 flex flex-wrap items-center justify-between gap-2">
                        <span className="text-xs font-medium text-slate-500">園児単位(選択中施設: {children.length}名)</span>
                        <input
                          type="search"
                          value={childSearch}
                          onChange={(e) => setChildSearch(e.target.value)}
                          placeholder="氏名で検索"
                          className="rounded-md border border-slate-300 px-2 py-1 text-xs focus:border-sky-400 focus:outline-none"
                        />
                      </div>
                      {/* クラス別(年齢順=classesの並び順)に分けて表示。未所属は末尾にまとめる。 */}
                      <div className="max-h-56 space-y-2 overflow-y-auto">
                        {children.length === 0 && <span className="text-xs text-slate-400">園児がいません。</span>}
                        {(() => {
                          const kw = childSearch.trim();
                          const matched = kw
                            ? children.filter((c) => c.display_name.includes(kw))
                            : children;
                          // classes は fetch_childcare_classes(年齢順)。その順でグループ化し、
                          // クラス未所属/一覧に無いクラスは「その他」として最後にまとめる。
                          const groups: { key: string; label: string; items: ChildOption[] }[] = classes.map((cl) => ({
                            key: cl.class_id,
                            label: cl.class_name,
                            items: matched.filter((c) => c.class_name === cl.class_name),
                          }));
                          const known = new Set(classes.map((cl) => cl.class_name));
                          const others = matched.filter((c) => !c.class_name || !known.has(c.class_name));
                          if (others.length > 0) groups.push({ key: "__other__", label: "その他・未所属", items: others });
                          const visible = groups.filter((g) => g.items.length > 0);
                          if (visible.length === 0) {
                            return <span className="text-xs text-slate-400">該当する園児がいません。</span>;
                          }
                          return visible.map((g) => (
                            <div key={g.key}>
                              <div className="mb-1 text-[11px] font-semibold text-slate-400">{g.label}</div>
                              <div className="flex flex-wrap gap-2">
                                {g.items.map((c) => (
                                  <label
                                    key={c.child_id}
                                    className="flex items-center gap-1.5 rounded-md border border-slate-200 px-2 py-1 text-xs"
                                  >
                                    <input
                                      type="checkbox"
                                      checked={targetChildren.has(c.child_id)}
                                      onChange={() => setTargetChildren(toggle(targetChildren, c.child_id))}
                                    />
                                    {c.display_name}
                                  </label>
                                ))}
                              </div>
                            </div>
                          ));
                        })()}
                      </div>
                    </div>
                  </div>
                </fieldset>
              </div>

              <div className="flex flex-wrap gap-2">
                {pendingFiles.length > 0 && (
                  <div className="w-full space-y-1 text-xs text-slate-600">
                    {pendingFiles.map((f, i) => (
                      <div key={i} className="flex items-center gap-2">
                        <span>📎 {f.name}</span>
                        <button
                          onClick={() => setPendingFiles((cur) => cur.filter((_, j) => j !== i))}
                          className="text-red-500 hover:underline"
                        >
                          削除
                        </button>
                      </div>
                    ))}
                  </div>
                )}
                <label className="cursor-pointer rounded-lg border border-slate-300 px-4 py-2 text-sm text-slate-600 hover:bg-slate-50">
                  📎 添付を追加(PDF/画像)
                  <input
                    type="file"
                    accept="application/pdf,image/*"
                    multiple
                    className="hidden"
                    onChange={(e) => {
                      const files = Array.from(e.target.files ?? []);
                      if (files.length) setPendingFiles((cur) => [...cur, ...files]);
                      e.target.value = "";
                    }}
                  />
                </label>
                <button
                  onClick={handleSaveDraft}
                  disabled={isBusy}
                  className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 transition hover:bg-slate-50 disabled:opacity-50"
                >
                  下書き保存
                </button>
                {canDirectApprove ? (
                  <button
                    onClick={handleCreateThenApprove}
                    disabled={isBusy}
                    className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-700 disabled:opacity-50"
                  >
                    確認して送信
                  </button>
                ) : (
                  <button
                    onClick={handleSubmitNew}
                    disabled={isBusy}
                    className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-sky-700 disabled:opacity-50"
                  >
                    承認申請
                  </button>
                )}
              </div>
            </section>
          )}

          {/* 一覧(作業中のみ: 下書き・申請中・差し戻し・承認済み未配信)。配信済み/取消済みは配信履歴へ。 */}
          <section className="space-y-3 rounded-2xl bg-white p-5 shadow-sm">
            <h3 className="text-sm font-bold text-slate-700">作業中のお知らせ</h3>
            {isLoading && <p className="text-sm text-slate-400">読み込み中…</p>}
            {listError && <p className="text-sm text-rose-500">{listError}</p>}
            {!isLoading && workingNotices.length === 0 && (
              <p className="text-sm text-slate-400">作業中のお知らせはありません。</p>
            )}
            <ul className="space-y-2">
              {workingNotices.map((n) => (
                <li key={n.id}>
                  <button
                    onClick={() => setSelectedId(n.id === selectedId ? null : n.id)}
                    className={`w-full rounded-lg border px-3 py-2 text-left transition ${
                      n.id === selectedId ? "border-sky-300 bg-sky-50" : "border-slate-200 hover:bg-slate-50"
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="truncate text-sm font-medium text-slate-800">{n.title}</span>
                      <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${STATUS_BADGE[n.status] ?? ""}`}>
                        {n.revoked_at ? "取消済み" : GUARDIAN_NOTICE_STATUS_LABELS[n.status]}
                      </span>
                    </div>
                    <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-xs text-slate-500">
                      <span>{(n.target_labels ?? []).join(" / ") || "宛先なし"}</span>
                      {n.status === "approved" && !n.revoked_at && (
                        <span className="text-emerald-600">既読 {n.read_guardians}/{n.total_guardians}名</span>
                      )}
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          </section>

          {/* 配信履歴(いつ・何時に・誰に・何世帯)+ 予約の予定変更/取消 */}
          <section className="space-y-3 rounded-2xl bg-white p-5 shadow-sm">
            <h3 className="text-sm font-bold text-slate-700">配信履歴</h3>
            {finalizedHistory.length === 0 && <p className="text-sm text-slate-400">履歴はまだありません。</p>}
            {finalizedHistory.length > 0 && (
              <div className="overflow-x-auto">
                <table className="min-w-full text-sm">
                  <thead>
                    <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                      <th className="px-3 py-2">タイトル</th>
                      <th className="px-3 py-2">状態</th>
                      <th className="px-3 py-2">配信日時 / 予定</th>
                      <th className="px-3 py-2">宛先</th>
                      <th className="px-3 py-2">世帯</th>
                      <th className="px-3 py-2" />
                    </tr>
                  </thead>
                  <tbody>
                    {finalizedHistory.map((h) => {
                      const scheduledUnsent = h.status === "approved" && !h.sent_at && !!h.scheduled_send_at && !h.revoked_at;
                      return (
                        <tr key={h.notice_id} className="border-b border-slate-100 last:border-0">
                          <td className="px-3 py-2 font-medium text-slate-800">{h.title}</td>
                          <td className="px-3 py-2">
                            {h.revoked_at ? (
                              <span className="text-rose-600">取消済み</span>
                            ) : h.sent_at ? (
                              <span className="text-emerald-700">配信済み</span>
                            ) : scheduledUnsent ? (
                              <span className="text-amber-700">配信予約</span>
                            ) : (
                              <span className="text-slate-500">{GUARDIAN_NOTICE_STATUS_LABELS[h.status as keyof typeof GUARDIAN_NOTICE_STATUS_LABELS] ?? h.status}</span>
                            )}
                          </td>
                          <td className="px-3 py-2 text-slate-500">
                            {h.sent_at
                              ? formatJst(h.sent_at)
                              : h.scheduled_send_at
                                ? `予約: ${formatJst(h.scheduled_send_at)}`
                                : "未配信"}
                          </td>
                          <td className="px-3 py-2 text-slate-500">{h.target_summary}</td>
                          <td className="px-3 py-2 text-slate-600">{h.recipient_household_count}</td>
                          <td className="px-3 py-2 text-right">
                            {scheduledUnsent && (
                              <div className="flex justify-end gap-1">
                                <button onClick={() => handleReschedule(h.notice_id)} className="rounded border border-slate-300 px-2 py-0.5 text-xs text-slate-600 hover:bg-slate-50">
                                  予定変更
                                </button>
                                <button onClick={() => handleCancelSchedule(h.notice_id)} className="rounded border border-rose-300 px-2 py-0.5 text-xs text-rose-600 hover:bg-rose-50">
                                  取消
                                </button>
                              </div>
                            )}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </div>

        {/* 詳細 */}
        {selectedNotice && (
          <section className="space-y-4 rounded-2xl bg-white p-5 shadow-sm">
            <div className="flex items-start justify-between gap-4">
              <div>
                <h3 className="text-base font-bold text-slate-800">{selectedNotice.title}</h3>
                <p className="mt-0.5 text-xs text-slate-500">
                  作成: {selectedNotice.created_by_name}
                  {selectedNotice.approver_name ? ` / 承認: ${selectedNotice.approver_name}` : ""}
                </p>
              </div>
              <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-semibold ${STATUS_BADGE[selectedNotice.status] ?? ""}`}>
                {selectedNotice.revoked_at ? "取消済み" : GUARDIAN_NOTICE_STATUS_LABELS[selectedNotice.status]}
              </span>
            </div>

            <p className="whitespace-pre-wrap rounded-lg bg-slate-50 p-3 text-sm text-slate-700">{selectedNotice.body}</p>
            <div className="text-xs text-slate-500">宛先: {(selectedNotice.target_labels ?? []).join(" / ") || "—"}</div>

            {/* 208: 添付一覧(タップで署名URL表示。draft/差し戻し中は削除可) */}
            {attachments.length > 0 && (
              <div className="space-y-1 text-sm">
                {attachments.map((a) => (
                  <div key={a.id} className="flex items-center gap-2">
                    <button onClick={() => openAttachment(a.file_path)} className="text-sky-700 hover:underline">
                      📎 {a.file_name}
                    </button>
                    {(selectedNotice.status === "draft" || selectedNotice.status === "returned") && (
                      <button onClick={() => deleteAttachment(a)} className="text-xs text-red-500 hover:underline">
                        削除
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}

            {selectedNotice.status === "returned" && selectedNotice.returned_reason && (
              <div className="rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700">差し戻し理由: {selectedNotice.returned_reason}</div>
            )}
            {selectedNotice.revoked_at && selectedNotice.revoke_reason && (
              <div className="rounded-lg bg-slate-100 px-3 py-2 text-sm text-slate-600">取り消し理由: {selectedNotice.revoke_reason}</div>
            )}

            {/* 既読集計・未読世帯(承認済み・未取消) */}
            {selectedNotice.status === "approved" && !selectedNotice.revoked_at && (
              <div className="space-y-2 rounded-lg border border-slate-200 p-3">
                <div className="text-sm font-semibold text-slate-700">
                  既読状況
                  {readSummary && (
                    <span className="ml-2 font-normal text-slate-500">
                      保護者 {readSummary.read_guardians}/{readSummary.total_guardians}名
                      {readSummary.total_children > 0 && ` ・ 未読世帯 ${readSummary.unread_children}/${readSummary.total_children}`}
                    </span>
                  )}
                </div>
                <div>
                  <div className="mb-1 text-xs font-medium text-slate-500">未読世帯一覧</div>
                  {unreadList.length === 0 ? (
                    <p className="text-xs text-emerald-600">全員が既読、または未読の世帯はありません。</p>
                  ) : (
                    <ul className="flex flex-wrap gap-2">
                      {unreadList.map((u, i) => (
                        <li key={i} className="rounded-md bg-rose-50 px-2 py-1 text-xs text-rose-700">
                          {u.kind === "child"
                            ? `${u.child_name ?? "?"}${u.class_name ? `(${u.class_name})` : ""}`
                            : `${u.guardian_name ?? "?"}(保護者)`}
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              </div>
            )}

            {/* アクション */}
            <div className="flex flex-wrap gap-2 border-t border-slate-100 pt-3">
              {(selectedNotice.status === "draft" || selectedNotice.status === "returned") && (
                <button
                  onClick={() => handleSubmitExisting(selectedNotice.id)}
                  disabled={isBusy}
                  className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-sky-700 disabled:opacity-50"
                >
                  承認申請
                </button>
              )}
              {(selectedNotice.status === "draft" || selectedNotice.status === "in_review") && selectedNotice.can_approve && (
                <button
                  onClick={() => openApproveDialog(selectedNotice.id)}
                  disabled={isBusy}
                  className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-emerald-700 disabled:opacity-50"
                >
                  承認して送信
                </button>
              )}
              {selectedNotice.status === "in_review" && selectedNotice.can_approve && (
                <button
                  onClick={() => setReturnDialog({ noticeId: selectedNotice.id, reason: "" })}
                  disabled={isBusy}
                  className="rounded-lg border border-rose-300 px-4 py-2 text-sm font-medium text-rose-600 transition hover:bg-rose-50 disabled:opacity-50"
                >
                  差し戻し
                </button>
              )}
              {selectedNotice.status === "approved" && !selectedNotice.revoked_at && selectedNotice.can_approve && (
                <button
                  onClick={() => setRevokeDialog({ noticeId: selectedNotice.id, reason: "" })}
                  disabled={isBusy}
                  className="rounded-lg border border-rose-300 px-4 py-2 text-sm font-medium text-rose-600 transition hover:bg-rose-50 disabled:opacity-50"
                >
                  取り消し
                </button>
              )}
              {/* 承認済み未配信(配信予約中)の予定変更/取消。履歴表から予約中を外したため詳細に集約。 */}
              {isScheduledUnsent && (
                <>
                  <button
                    onClick={() => handleReschedule(selectedNotice.id)}
                    disabled={isBusy}
                    className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 transition hover:bg-slate-50 disabled:opacity-50"
                  >
                    予定変更
                  </button>
                  <button
                    onClick={() => handleCancelSchedule(selectedNotice.id)}
                    disabled={isBusy}
                    className="rounded-lg border border-rose-300 px-4 py-2 text-sm font-medium text-rose-600 transition hover:bg-rose-50 disabled:opacity-50"
                  >
                    予約取消
                  </button>
                </>
              )}
            </div>
          </section>
        )}
      </main>

      {/* 承認確認ダイアログ(§6.5b・approve 直前) */}
      {approveDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md space-y-4 rounded-2xl bg-white p-6 shadow-xl">
            <h3 className="text-base font-bold text-slate-800">この内容で送信しますか?</h3>
            {approveDialog.loading && <p className="text-sm text-slate-500">配信規模を確認中…</p>}
            {approveDialog.error && <p className="text-sm text-rose-600">{approveDialog.error}</p>}
            {approveDialog.preview && (
              <div className="space-y-2 rounded-lg bg-slate-50 p-3 text-sm text-slate-700">
                <div>
                  <span className="text-slate-500">配信対象施設:</span>{" "}
                  {(approveDialog.preview.office_names ?? []).join("、") || "—"}
                </div>
                <div>
                  <span className="text-slate-500">対象の保護者アカウント数:</span>{" "}
                  <span className="font-semibold">{approveDialog.preview.guardian_count}名</span>
                </div>
                <div>
                  <span className="text-slate-500">対象の園児数:</span>{" "}
                  <span className="font-semibold">{approveDialog.preview.child_count}名</span>
                </div>
              </div>
            )}
            <div>
              <label className="mb-1 block text-xs font-medium text-slate-500">配信予定日時(空欄=承認と同時に即時配信)</label>
              <input
                type="datetime-local"
                value={approveScheduledAt}
                onChange={(e) => setApproveScheduledAt(e.target.value)}
                className="rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
              />
              <p className="mt-1 text-xs text-slate-400">未来を指定すると予約になり、その日時に自動配信されます(承認後も予定変更・取消が可能)。</p>
            </div>
            <div className="rounded-lg bg-amber-50 px-3 py-2 text-sm font-medium text-amber-800">
              ⚠ 即時配信・配信済みのプッシュ通知は取り消せません(予約は配信前なら取消可能)。
            </div>
            <div className="flex justify-end gap-2">
              <button
                onClick={() => {
                  setApproveDialog(null);
                  setApproveScheduledAt("");
                }}
                disabled={isBusy}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                onClick={confirmApprove}
                disabled={isBusy || approveDialog.loading || !approveDialog.preview}
                className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700 disabled:opacity-50"
              >
                {approveScheduledAt ? "予約する" : "送信する"}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 差し戻しダイアログ(理由必須) */}
      {returnDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md space-y-4 rounded-2xl bg-white p-6 shadow-xl">
            <h3 className="text-base font-bold text-slate-800">差し戻し</h3>
            <textarea
              value={returnDialog.reason}
              onChange={(e) => setReturnDialog({ ...returnDialog, reason: e.target.value })}
              rows={3}
              placeholder="差し戻し理由(必須)"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setReturnDialog(null)}
                disabled={isBusy}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                onClick={confirmReturn}
                disabled={isBusy || !returnDialog.reason.trim()}
                className="rounded-lg bg-rose-600 px-4 py-2 text-sm font-medium text-white hover:bg-rose-700 disabled:opacity-50"
              >
                差し戻す
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 取り消しダイアログ(理由必須・取消不可警告) */}
      {revokeDialog && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md space-y-4 rounded-2xl bg-white p-6 shadow-xl">
            <h3 className="text-base font-bold text-slate-800">一斉配信の取り消し</h3>
            <div className="rounded-lg bg-amber-50 px-3 py-2 text-sm font-medium text-amber-800">
              ⚠ アプリ内の一覧からは消えますが、既に配信済みのプッシュ通知は取り消せません。
            </div>
            <textarea
              value={revokeDialog.reason}
              onChange={(e) => setRevokeDialog({ ...revokeDialog, reason: e.target.value })}
              rows={3}
              placeholder="取り消し理由(必須)"
              className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm focus:border-sky-400 focus:outline-none"
            />
            <div className="flex justify-end gap-2">
              <button
                onClick={() => setRevokeDialog(null)}
                disabled={isBusy}
                className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                キャンセル
              </button>
              <button
                onClick={confirmRevoke}
                disabled={isBusy || !revokeDialog.reason.trim()}
                className="rounded-lg bg-rose-600 px-4 py-2 text-sm font-medium text-white hover:bg-rose-700 disabled:opacity-50"
              >
                取り消す
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function ChildcareAnnouncementsPage() {
  return (
    <Suspense fallback={null}>
      <AnnouncementsPageContent />
    </Suspense>
  );
}
