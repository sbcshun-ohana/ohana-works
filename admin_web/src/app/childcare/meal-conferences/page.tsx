"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { MealSubNav } from "@/components/MealSubNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// アレルギー管理 Phase2-a: 給食会議の記録 + 保護者同意文言テンプレの版管理。migration 272。
// 除去食の「正式提供」は 給食会議 → 保護者同意 が前提(提供開始ゲートは 273)。

type Conference = {
  id: string;
  child_id: string;
  child_name: string;
  held_on: string | null;
  nutritionist_name: string | null;
  status: string;
  created_at: string;
  consent_at: string | null;
  attendee_names: string[] | null;
};
type Child = { child_id: string; display_name: string; class_name: string | null };
type Staff = { employee_id: string; name: string };
type Template = { id: string; version: number; body: string; is_published: boolean; created_at: string };

function fmtDate(ts: string | null): string {
  if (!ts) return "—";
  const d = new Date(ts);
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`;
}

// 保護者同意の標準文例(ワンタップ挿入用)。園ごとに手直し可。
const STANDARD_CONSENT_TEXT = `アレルギー除去食の提供について

給食会議において、除去・代替の提供方針について説明を受け、内容を理解しました。
上記の内容で除去食を提供いただくことに同意します。

なお、家庭での状況に変化があった場合や、除去内容の変更が必要になった場合は、
速やかに園へ連絡します。`;

const STATUS_LABEL: Record<string, { label: string; cls: string }> = {
  held: { label: "同意待ち", cls: "bg-amber-50 text-amber-700" },
  consented: { label: "同意済み", cls: "bg-emerald-50 text-emerald-700" },
  planned: { label: "予定", cls: "bg-slate-100 text-slate-500" },
};

function MealConferencesContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;
  const [isAdmin, setIsAdmin] = useState(false);
  const [children, setChildren] = useState<Child[]>([]);
  const [staff, setStaff] = useState<Staff[]>([]);
  const [conferences, setConferences] = useState<Conference[]>([]);
  const [templates, setTemplates] = useState<Template[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  // 会議作成フォーム
  const [formChild, setFormChild] = useState("");
  const [formHeldOn, setFormHeldOn] = useState("");
  const [formNutritionist, setFormNutritionist] = useState("");
  const [formPlan, setFormPlan] = useState("");
  const [formAttendees, setFormAttendees] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);

  // テンプレ編集
  const [tmplBody, setTmplBody] = useState("");

  useEffect(() => {
    if (!selectedOffice) return;
    let cancelled = false;
    void (async () => {
      const supabase = createClient();
      const [{ data: adminData }, { data: ch }, { data: st }, { data: conf, error: confErr }] = await Promise.all([
        supabase.rpc("is_childcare_admin", { target_office_id: selectedOffice }),
        supabase.rpc("fetch_children_for_office_master", { p_office_id: selectedOffice }),
        supabase.rpc("fetch_childcare_office_staff", { p_office_id: selectedOffice }),
        supabase.rpc("fetch_meal_conferences_for_office", { p_office_id: selectedOffice, p_only_unconsented: false }),
      ]);
      if (cancelled) return;
      setIsAdmin(adminData === true);
      setChildren((ch ?? []) as Child[]);
      setStaff((st ?? []) as Staff[]);
      if (confErr) setError(confErr.message);
      else setError(null);
      setConferences((conf ?? []) as Conference[]);
      if (adminData === true) {
        const { data: t } = await supabase.rpc("fetch_meal_consent_templates", { p_office_id: selectedOffice });
        if (!cancelled) setTemplates((t ?? []) as Template[]);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedOffice, reloadToken]);

  async function createConference() {
    if (!formChild) {
      alert("園児を選択してください");
      return;
    }
    setBusy(true);
    const supabase = createClient();
    const { error: e } = await supabase.rpc("create_meal_conference", {
      p_child_id: formChild,
      p_diagnosis_id: null,
      p_held_on: formHeldOn || null,
      p_nutritionist_name: formNutritionist || null,
      p_elimination_plan: formPlan || null,
      p_attendee_employee_ids: formAttendees.length > 0 ? formAttendees : null,
    });
    setBusy(false);
    if (e) {
      alert(`登録できません: ${e.message}`);
      return;
    }
    setFormChild("");
    setFormHeldOn("");
    setFormNutritionist("");
    setFormPlan("");
    setFormAttendees([]);
    setReloadToken((t) => t + 1);
  }

  async function cancelConference(id: string) {
    const note = window.prompt("この給食会議を取消します。理由(任意):", "") ?? "";
    const supabase = createClient();
    const { error: e } = await supabase.rpc("cancel_meal_conference", { p_id: id, p_note: note || null });
    if (e) alert(`取消できません: ${e.message}`);
    else setReloadToken((t) => t + 1);
  }

  async function saveTemplate() {
    if (!tmplBody.trim()) {
      alert("文言を入力してください");
      return;
    }
    const supabase = createClient();
    const { data: id, error: e } = await supabase.rpc("save_meal_consent_template", {
      p_office_id: selectedOffice,
      p_body: tmplBody.trim(),
    });
    if (e) {
      alert(`保存できません: ${e.message}`);
      return;
    }
    if (window.confirm("下書きを保存しました。この版をすぐ公開しますか?(公開すると保護者の同意画面で使われます)")) {
      await supabase.rpc("publish_meal_consent_template", { p_id: id });
    }
    setTmplBody("");
    setReloadToken((t) => t + 1);
  }

  async function publishTemplate(id: string) {
    if (!window.confirm("この版を公開します(他の版は非公開になります)。よろしいですか?")) return;
    const supabase = createClient();
    const { error: e } = await supabase.rpc("publish_meal_consent_template", { p_id: id });
    if (e) alert(`公開できません: ${e.message}`);
    else setReloadToken((t) => t + 1);
  }

  const publishedTemplate = templates.find((t) => t.is_published);

  if (officesError) {
    return (
      <div className="flex flex-1 flex-col">
        <AppHeader />
        <div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div>
      </div>
    );
  }

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <MealSubNav />
      <main className="flex-1 space-y-6 p-6">
        <div>
          <h2 className="text-lg font-bold text-slate-800">給食会議・保護者同意</h2>
          <p className="mt-1 text-xs text-slate-400">
            アレルギー除去食を正式に提供する前提の給食会議を記録します。記録後、保護者が保護者アプリで同意すると「同意済み」になります。
          </p>
        </div>

        {error && <p className="text-sm font-medium text-red-500">{error}</p>}

        {!isManager && (
          <p className="rounded-xl bg-amber-50 p-3 text-sm text-amber-700">
            給食会議の記録・取消は主任以上のみ可能です(閲覧のみ)。
          </p>
        )}

        {/* 給食会議の記録 */}
        {isManager && (
          <section className="space-y-3 rounded-2xl bg-white p-5 shadow-sm">
            <h3 className="text-sm font-bold text-slate-700">給食会議を記録</h3>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="text-sm">
                <span className="mb-1 block font-medium text-slate-600">園児</span>
                <select
                  value={formChild}
                  onChange={(e) => setFormChild(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2"
                >
                  <option value="">選択してください</option>
                  {children.map((c) => (
                    <option key={c.child_id} value={c.child_id}>
                      {c.class_name ? `[${c.class_name}] ` : ""}
                      {c.display_name}
                    </option>
                  ))}
                </select>
              </label>
              <label className="text-sm">
                <span className="mb-1 block font-medium text-slate-600">開催日</span>
                <input
                  type="date"
                  value={formHeldOn}
                  onChange={(e) => setFormHeldOn(e.target.value)}
                  className="w-full rounded-lg border border-slate-300 px-3 py-2"
                />
              </label>
              <label className="text-sm">
                <span className="mb-1 block font-medium text-slate-600">栄養士名(委託先)</span>
                <input
                  type="text"
                  value={formNutritionist}
                  onChange={(e) => setFormNutritionist(e.target.value)}
                  placeholder="例: ◯◯ 栄養士"
                  className="w-full rounded-lg border border-slate-300 px-3 py-2"
                />
              </label>
            </div>
            <div className="text-sm">
              <span className="mb-1 block font-medium text-slate-600">園側の出席者(職員)</span>
              {staff.length === 0 ? (
                <p className="text-xs text-slate-400">職員一覧を取得できませんでした。</p>
              ) : (
                <div className="flex max-h-40 flex-wrap gap-x-4 gap-y-2 overflow-y-auto rounded-lg border border-slate-200 bg-slate-50 p-3">
                  {staff.map((s) => (
                    <label key={s.employee_id} className="flex cursor-pointer items-center gap-2">
                      <input
                        type="checkbox"
                        className="h-4 w-4"
                        checked={formAttendees.includes(s.employee_id)}
                        onChange={(e) =>
                          setFormAttendees((prev) =>
                            e.target.checked ? [...prev, s.employee_id] : prev.filter((id) => id !== s.employee_id),
                          )
                        }
                      />
                      <span className="text-slate-700">{s.name}</span>
                    </label>
                  ))}
                </div>
              )}
            </div>
            <label className="block text-sm">
              <span className="mb-1 block font-medium text-slate-600">除去・代替の提供方針</span>
              <textarea
                value={formPlan}
                onChange={(e) => setFormPlan(e.target.value)}
                rows={3}
                placeholder="例: 卵を除去し、代替として◯◯を提供。誤配膳防止のため専用トレーで配膳。"
                className="w-full rounded-lg border border-slate-300 px-3 py-2"
              />
            </label>
            <button
              onClick={createConference}
              disabled={busy}
              className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50"
            >
              給食会議を記録
            </button>
          </section>
        )}

        {/* 会議一覧 */}
        <section className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-3 py-3">園児</th>
                <th className="px-3 py-3">開催日</th>
                <th className="px-3 py-3">栄養士</th>
                <th className="px-3 py-3">園側出席者</th>
                <th className="px-3 py-3">状態</th>
                <th className="px-3 py-3">保護者同意</th>
                <th className="px-3 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {conferences.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-3 py-6 text-center text-slate-400">
                    給食会議の記録はありません
                  </td>
                </tr>
              )}
              {conferences.map((c) => {
                const st = STATUS_LABEL[c.status] ?? { label: c.status, cls: "bg-slate-100 text-slate-500" };
                return (
                  <tr key={c.id} className="border-b border-slate-100 last:border-0">
                    <td className="px-3 py-3 font-medium text-slate-800">{c.child_name}</td>
                    <td className="px-3 py-3 text-slate-500">{fmtDate(c.held_on)}</td>
                    <td className="px-3 py-3 text-slate-500">{c.nutritionist_name || "—"}</td>
                    <td className="px-3 py-3 text-slate-500">
                      {c.attendee_names && c.attendee_names.length > 0 ? c.attendee_names.join("、") : "—"}
                    </td>
                    <td className="px-3 py-3">
                      <span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${st.cls}`}>{st.label}</span>
                    </td>
                    <td className="px-3 py-3 text-slate-500">{c.consent_at ? fmtDate(c.consent_at) : "—"}</td>
                    <td className="px-3 py-3 text-right">
                      {isManager && c.status !== "cancelled" && !c.consent_at && (
                        <button
                          onClick={() => cancelConference(c.id)}
                          className="rounded-lg border border-slate-300 px-3 py-1 text-xs text-slate-500 hover:bg-slate-50"
                        >
                          取消
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </section>

        {/* 同意文言テンプレ(管理者以上) */}
        {isAdmin && (
          <section className="space-y-3 rounded-2xl border border-slate-200 bg-slate-50 p-5">
            <h3 className="text-sm font-bold text-slate-700">保護者同意の文言テンプレ(管理者以上)</h3>
            <p className="text-xs text-slate-400">
              保護者が同意画面で読む文言です。公開版は常に1つ。同意時にその時点の文言が保存され、後で改版しても過去の同意記録は変わりません。
            </p>
            {publishedTemplate ? (
              <div className="rounded-xl bg-white p-3 text-sm text-slate-700 shadow-sm">
                <div className="mb-1 text-xs font-semibold text-emerald-600">公開中(v{publishedTemplate.version})</div>
                <div className="whitespace-pre-wrap">{publishedTemplate.body}</div>
              </div>
            ) : (
              <p className="text-sm font-medium text-amber-600">
                公開中の文言がありません。保護者は同意できません。下で作成・公開してください。
              </p>
            )}
            <label className="block text-sm">
              <div className="mb-1 flex flex-wrap items-center justify-between gap-2">
                <span className="font-medium text-slate-600">新しい版の文言</span>
                <button
                  type="button"
                  onClick={() => setTmplBody(STANDARD_CONSENT_TEXT)}
                  className="rounded-lg border border-sky-300 px-3 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-50"
                >
                  標準の文例を挿入
                </button>
              </div>
              <textarea
                value={tmplBody}
                onChange={(e) => setTmplBody(e.target.value)}
                rows={7}
                placeholder="「標準の文例を挿入」を押すと定型文が入ります。そのまま公開しても、園に合わせて手直ししてもOKです。"
                className="w-full rounded-lg border border-slate-300 px-3 py-2"
              />
            </label>
            <button
              onClick={saveTemplate}
              className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white hover:bg-sky-700"
            >
              下書き保存(必要なら公開)
            </button>
            {templates.length > 0 && (
              <div className="space-y-1 pt-2">
                <div className="text-xs font-semibold text-slate-500">版の履歴</div>
                {templates.map((t) => (
                  <div key={t.id} className="flex items-center justify-between gap-2 border-t border-slate-200 py-1 text-sm">
                    <span className="text-slate-600">
                      v{t.version}
                      {t.is_published && <span className="ml-2 text-xs font-semibold text-emerald-600">公開中</span>}
                      <span className="ml-2 text-xs text-slate-400">{fmtDate(t.created_at)}</span>
                    </span>
                    {!t.is_published && (
                      <button
                        onClick={() => publishTemplate(t.id)}
                        className="rounded-lg border border-emerald-500 px-3 py-1 text-xs font-semibold text-emerald-600 hover:bg-emerald-50"
                      >
                        この版を公開
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </section>
        )}
      </main>
    </div>
  );
}

export default function MealConferencesPage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-400">読み込み中…</div>}>
      <MealConferencesContent />
    </Suspense>
  );
}
