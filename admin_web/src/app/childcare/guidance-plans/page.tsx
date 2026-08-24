"use client";

import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";

// 指導計画・保育安全計画 Phase2 作成画面(287/288)。ヒント表示・例文挿入・自動保存・承認フロー・個人案。

type ClassRow = { class_id: string; class_name: string; age_group: string };
type PlanListRow = {
  id: string; class_id: string | null; class_name: string | null; plan_type: string;
  age_variant: string | null; month: number | null; week_start_date: string | null; status: string; updated_at: string;
};
type TemplateField = { key: string; label: string; required?: boolean; subject?: string; hint?: string; examples?: string[] };
type TemplateSection = { key: string; label: string; hint?: string; fields: TemplateField[] };
type PlanDetail = {
  plan: {
    id: string; office_id: string; class_id: string | null; plan_type: string; fiscal_year: number;
    month: number | null; week_start_date: string | null; content: Record<string, string>;
    evaluation: Record<string, string>; status: string; rejected_reason: string | null;
  };
  template: { title: string; sections: TemplateSection[] };
  individual: { child_id: string; child_name: string; content: Record<string, string> }[];
};

const PLAN_TYPES = [
  { value: "overall", label: "全体的な計画", needsClass: false },
  { value: "annual", label: "年間指導計画", needsClass: true },
  { value: "monthly", label: "月案", needsClass: true },
  { value: "weekly", label: "週案", needsClass: true },
  { value: "safety", label: "保育安全計画", needsClass: false },
];
const STATUS_LABEL: Record<string, { label: string; cls: string }> = {
  draft: { label: "下書き", cls: "bg-slate-100 text-slate-600" },
  submitted: { label: "申請中", cls: "bg-amber-50 text-amber-700" },
  chief_checked: { label: "主任確認済", cls: "bg-sky-50 text-sky-700" },
  approved: { label: "承認済", cls: "bg-emerald-50 text-emerald-700" },
};
const INDIVIDUAL_FIELDS: TemplateField[] = [
  { key: "kidsstate", label: "子どもの姿", subject: "子ども", required: true },
  { key: "aim", label: "ねらい", subject: "子ども", required: true },
  { key: "consideration", label: "配慮・環境構成", subject: "保育者", required: true },
  { key: "reflection", label: "評価・反省", subject: "保育者" },
];
const isReflection = (sectionKey: string, fieldKey: string) => sectionKey === "reflection" || fieldKey === "reflection";

function GuidancePlansContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const isManager = offices?.find((o) => o.office_id === selectedOffice)?.is_manager ?? false;
  const [isAdmin, setIsAdmin] = useState(false);
  const [classes, setClasses] = useState<ClassRow[]>([]);
  const nowYear = new Date().getFullYear();
  const [fiscalYear, setFiscalYear] = useState(nowYear);
  const [planType, setPlanType] = useState("monthly");
  const [classId, setClassId] = useState("");
  const [month, setMonth] = useState(new Date().getMonth() + 1);
  const [weekStart, setWeekStart] = useState("");
  const [plans, setPlans] = useState<PlanListRow[]>([]);
  const [templates, setTemplates] = useState<{ id: string; plan_type: string; age_variant: string | null; title: string; is_published: boolean }[]>([]);
  const [detail, setDetail] = useState<PlanDetail | null>(null);
  const [individualTargets, setIndividualTargets] = useState<{ child_id: string; display_name: string; is_kahai: boolean }[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [reloadToken, setReloadToken] = useState(0);
  const [listTab, setListTab] = useState<string>("__none__"); // 一覧のクラス別タブ(classId or '__none__'=園全体)
  const [tasks, setTasks] = useState<{ message: string; level: string }[]>([]); // 未完了タスク(主任以上・306)
  const [savedAt, setSavedAt] = useState<string | null>(null);
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const needsClass = PLAN_TYPES.find((p) => p.value === planType)?.needsClass ?? false;

  useEffect(() => {
    if (!selectedOffice) return;
    let cancelled = false;
    void (async () => {
      const supabase = createClient();
      const [{ data: adminData }, { data: cls }, { data: pl }] = await Promise.all([
        supabase.rpc("is_childcare_admin", { target_office_id: selectedOffice }),
        supabase.rpc("fetch_childcare_classes", { p_office_id: selectedOffice }),
        supabase.rpc("fetch_guidance_plans_for_office", { p_office_id: selectedOffice, p_fiscal_year: fiscalYear, p_plan_type: null }),
      ]);
      if (cancelled) return;
      setIsAdmin(adminData === true);
      setClasses((cls ?? []) as ClassRow[]);
      setPlans((pl ?? []) as PlanListRow[]);
      if (adminData === true) {
        const { data: t } = await supabase.rpc("fetch_guidance_plan_templates");
        if (!cancelled) setTemplates((t ?? []) as typeof templates);
      }
      // 未完了タスク(主任以上・306)。
      if (isManager) {
        const { data: tk } = await supabase.rpc("fetch_guidance_plan_tasks_for_office", { p_office_id: selectedOffice });
        if (!cancelled) setTasks((tk ?? []) as { message: string; level: string }[]);
      } else if (!cancelled) {
        setTasks([]);
      }
    })();
    return () => { cancelled = true; };
  }, [selectedOffice, fiscalYear, reloadToken, isManager]);

  async function openOrCreate() {
    if (!selectedOffice) return;
    if (needsClass && !classId) { alert("クラスを選択してください"); return; }
    if (planType === "weekly" && !weekStart) { alert("週(月曜日)を選択してください"); return; }
    setBusy(true); setError(null);
    const supabase = createClient();
    const { data: id, error: e } = await supabase.rpc("ensure_guidance_plan", {
      p_office_id: selectedOffice,
      p_class_id: needsClass ? classId : null,
      p_plan_type: planType,
      p_fiscal_year: fiscalYear,
      p_month: planType === "monthly" ? month : null,
      p_week_start: planType === "weekly" ? weekStart : null,
    });
    setBusy(false);
    if (e) { setError(e.message); return; }
    await loadDetail(id as string);
    setReloadToken((t) => t + 1);
  }

  async function loadDetail(id: string) {
    const supabase = createClient();
    const { data, error: e } = await supabase.rpc("fetch_guidance_plan", { p_id: id });
    if (e) { setError(e.message); return; }
    const d = data as PlanDetail;
    d.plan.content = d.plan.content ?? {};
    d.plan.evaluation = d.plan.evaluation ?? {};
    setDetail(d);
    setSavedAt(null);
    if (d.plan.plan_type === "monthly") {
      const { data: tg } = await supabase.rpc("fetch_guidance_individual_targets", { p_plan_id: id });
      setIndividualTargets((tg ?? []) as { child_id: string; display_name: string; is_kahai: boolean }[]);
    } else {
      setIndividualTargets([]);
    }
  }

  // 本文/評価の自動保存(デバウンス)。
  const scheduleSave = useCallback((d: PlanDetail) => {
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(async () => {
      const supabase = createClient();
      if (d.plan.status !== "approved") {
        await supabase.rpc("save_guidance_plan_content", { p_id: d.plan.id, p_content: d.plan.content });
      }
      await supabase.rpc("save_guidance_plan_evaluation", { p_id: d.plan.id, p_evaluation: d.plan.evaluation });
      const now = new Date();
      setSavedAt(`保存しました ${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`);
    }, 1000);
  }, []);

  function setField(sectionKey: string, key: string, value: string) {
    if (!detail) return;
    const d = structuredClone(detail);
    if (isReflection(sectionKey, key)) d.plan.evaluation[key] = value;
    else d.plan.content[key] = value;
    setDetail(d);
    scheduleSave(d);
  }
  function insertExample(sectionKey: string, key: string, text: string) {
    if (!detail) return;
    const cur = isReflection(sectionKey, key) ? detail.plan.evaluation[key] : detail.plan.content[key];
    const next = cur && cur.trim() ? `${cur}\n・${text}` : `・${text}`;
    setField(sectionKey, key, next);
  }

  async function runAction(fn: (s: ReturnType<typeof createClient>) => Promise<{ error: { message: string } | null }>, ok: string) {
    setBusy(true);
    const { error: e } = await fn(createClient());
    setBusy(false);
    if (e) { alert(`操作できません: ${e.message}`); return; }
    if (ok) alert(ok);
    if (detail) await loadDetail(detail.plan.id);
    setReloadToken((t) => t + 1);
  }

  async function saveIndividual(childId: string, content: Record<string, string>) {
    if (!detail) return;
    const supabase = createClient();
    await supabase.rpc("upsert_guidance_plan_individual", { p_plan_id: detail.plan.id, p_child_id: childId, p_content: content });
    setSavedAt("個人案を保存しました");
  }

  if (officesError) {
    return (<div className="flex flex-1 flex-col"><AppHeader /><div className="p-8 text-sm text-red-500">施設一覧の取得に失敗しました: {officesError}</div></div>);
  }

  const unpublished = templates.filter((t) => !t.is_published);

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-5 p-6">
        <h2 className="text-lg font-bold text-slate-800">指導計画・保育安全計画</h2>
        {error && <p className="text-sm font-medium text-red-500">{error}</p>}

        {/* テンプレ公開(管理者・未公開があるとき) */}
        {isAdmin && unpublished.length > 0 && (
          <div className="rounded-2xl border border-amber-200 bg-amber-50 p-4">
            <p className="text-sm font-bold text-amber-800">未公開のテンプレートがあります(公開すると作成できます)</p>
            <div className="mt-2 flex flex-wrap gap-2">
              {unpublished.map((t) => (
                <button key={t.id} onClick={() => runAction(async (s) => await s.rpc("publish_guidance_plan_template", { p_id: t.id }), `「${t.title}」を公開しました`)}
                  className="rounded-lg border border-amber-400 bg-white px-3 py-1 text-xs font-semibold text-amber-700 hover:bg-amber-100">
                  {t.title} を公開
                </button>
              ))}
            </div>
          </div>
        )}

        {/* セレクタ */}
        <section className="flex flex-wrap items-end gap-3 rounded-2xl bg-white p-4 shadow-sm">
          <label className="text-sm"><span className="mb-1 block font-medium text-slate-600">年度</span>
            <select value={fiscalYear} onChange={(e) => setFiscalYear(Number(e.target.value))} className="rounded-lg border border-slate-300 px-3 py-2">
              {[nowYear - 1, nowYear, nowYear + 1].map((y) => <option key={y} value={y}>{y}年度</option>)}
            </select>
          </label>
          <label className="text-sm"><span className="mb-1 block font-medium text-slate-600">計画種別</span>
            <select value={planType} onChange={(e) => setPlanType(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2">
              {PLAN_TYPES.map((p) => <option key={p.value} value={p.value}>{p.label}</option>)}
            </select>
          </label>
          {needsClass && (
            <label className="text-sm"><span className="mb-1 block font-medium text-slate-600">クラス</span>
              <select value={classId} onChange={(e) => setClassId(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2">
                <option value="">選択</option>
                {classes.map((c) => <option key={c.class_id} value={c.class_id}>{c.class_name}</option>)}
              </select>
            </label>
          )}
          {planType === "monthly" && (
            <label className="text-sm"><span className="mb-1 block font-medium text-slate-600">月</span>
              <select value={month} onChange={(e) => setMonth(Number(e.target.value))} className="rounded-lg border border-slate-300 px-3 py-2">
                {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => <option key={m} value={m}>{m}月</option>)}
              </select>
            </label>
          )}
          {planType === "weekly" && (
            <label className="text-sm"><span className="mb-1 block font-medium text-slate-600">週(月曜)</span>
              <input type="date" value={weekStart} onChange={(e) => setWeekStart(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-2" />
            </label>
          )}
          <button onClick={openOrCreate} disabled={busy}
            className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-50">開く / 作成</button>
        </section>

        {/* 未完了タスク(主任以上・306): 未提出=赤/承認待ち=青 */}
        {isManager && tasks.length > 0 && (
          <section className={`rounded-2xl border p-4 shadow-sm ${tasks.some((t) => t.level === "action") ? "border-red-200 bg-red-50/40" : "border-sky-200 bg-sky-50/40"}`}>
            <div className="mb-2 text-sm font-bold text-slate-800">未完了タスク({tasks.length}件)</div>
            <div className="space-y-1">
              {tasks.filter((t) => t.level === "action").map((t, i) => (
                <div key={`a${i}`} className="text-sm font-semibold text-red-600">● {t.message}</div>
              ))}
              {tasks.filter((t) => t.level === "info").map((t, i) => (
                <div key={`i${i}`} className="text-sm font-semibold text-sky-700">● {t.message}</div>
              ))}
            </div>
          </section>
        )}

        {/* 一覧: クラス別タブ + 種別ごとにグルーピング */}
        {(() => {
          const tabs = [
            ...classes.map((c) => ({ id: c.class_id, label: c.class_name })),
            { id: "__none__", label: "園全体" },
          ];
          const activeTab = tabs.some((t) => t.id === listTab) ? listTab : (tabs[0]?.id ?? "__none__");
          const inTab = plans.filter((p) => (p.class_id ?? "__none__") === activeTab);
          return (
            <section className="space-y-3">
              <div className="flex flex-wrap gap-2">
                {tabs.map((t) => (
                  <button
                    key={t.id}
                    onClick={() => setListTab(t.id)}
                    className={`rounded-lg px-3 py-1.5 text-sm font-semibold transition ${
                      activeTab === t.id ? "bg-sky-600 text-white" : "bg-white text-slate-500 shadow-sm hover:bg-slate-50"
                    }`}
                  >
                    {t.label}
                  </button>
                ))}
              </div>
              {inTab.length === 0 ? (
                <div className="rounded-2xl bg-white p-6 text-center text-sm text-slate-400 shadow-sm">このクラスの計画はまだありません</div>
              ) : (
                PLAN_TYPES.filter((pt) => inTab.some((p) => p.plan_type === pt.value)).map((pt) => (
                  <div key={pt.value} className="overflow-x-auto rounded-2xl bg-white shadow-sm">
                    <div className="border-b border-slate-100 px-4 py-2 text-sm font-bold text-sky-700">{pt.label}</div>
                    <table className="min-w-full text-sm">
                      <thead><tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                        <th className="px-3 py-2">月/週</th><th className="px-3 py-2">状態</th><th className="px-3 py-2">更新</th><th></th>
                      </tr></thead>
                      <tbody>
                        {inTab.filter((p) => p.plan_type === pt.value).map((p) => (
                          <tr key={p.id} className="border-b border-slate-100 last:border-0">
                            <td className="px-3 py-3 font-medium text-slate-800">{p.month ? `${p.month}月` : p.week_start_date ? `${p.week_start_date}〜` : "—"}</td>
                            <td className="px-3 py-3"><span className={`rounded-full px-2 py-0.5 text-xs font-semibold ${(STATUS_LABEL[p.status] ?? STATUS_LABEL.draft).cls}`}>{(STATUS_LABEL[p.status] ?? { label: p.status }).label}</span></td>
                            <td className="px-3 py-3 text-slate-400">{new Date(p.updated_at).toLocaleDateString("ja-JP")}</td>
                            <td className="px-3 py-3 text-right"><button onClick={() => loadDetail(p.id)} className="rounded-lg border border-sky-300 px-3 py-1 text-xs font-semibold text-sky-700 hover:bg-sky-50">開く</button></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                ))
              )}
            </section>
          );
        })()}

        {/* エディタ */}
        {detail && <PlanEditor detail={detail} isManager={isManager} isAdmin={isAdmin} individualTargets={individualTargets}
          savedAt={savedAt} onField={setField} onInsert={insertExample} onSaveIndividual={saveIndividual}
          onClose={() => setDetail(null)}
          onSubmit={() => runAction(async (s) => await s.rpc("submit_guidance_plan", { p_id: detail.plan.id }), "申請しました")}
          onChiefCheck={() => runAction(async (s) => await s.rpc("chief_check_guidance_plan", { p_id: detail.plan.id }), "主任確認しました")}
          onApprove={() => runAction(async (s) => await s.rpc("approve_guidance_plan", { p_id: detail.plan.id }), "承認しました")}
          onReject={() => { const r = window.prompt("差し戻し理由(必須)"); if (!r) return; void runAction(async (s) => await s.rpc("reject_guidance_plan", { p_id: detail.plan.id, p_reason: r }), "差し戻しました"); }}
          onCancel={() => { const r = window.prompt("承認取消の理由(必須)"); if (!r) return; void runAction(async (s) => await s.rpc("cancel_guidance_plan_approval", { p_id: detail.plan.id, p_reason: r }), "承認を取り消しました"); }}
          onCopyPrevious={() => { if (!window.confirm("前回(前月/前週/前年度)の内容をコピーします。現在の入力は上書きされます。よろしいですか?")) return; void runAction(async (s) => await s.rpc("copy_previous_guidance_plan", { p_id: detail.plan.id }), "前回の内容をコピーしました"); }}
          busy={busy} />}
      </main>
    </div>
  );
}

// 保育安全計画のExcel出力(こども家庭庁様式の構造で aoa 構築)。SheetJS(community)のためセル装飾は付かないが、
// 月別グリッド・マニュアル表・期別表など様式のレイアウト構造を再現する。
function exportSafetyExcel(XLSX: typeof import("xlsx"), p: { content: Record<string, string>; fiscal_year: number }, filename: string) {
  const c = (k: string) => p.content[k] ?? "";
  const H1 = [4, 5, 6, 7, 8, 9], H2 = [10, 11, 12, 1, 2, 3];
  const MANUALS: { label: string; k: string; sub?: boolean }[] = [
    { label: "重大事故防止マニュアル", k: "daijiko" },
    { label: "　└ 午睡", k: "m_nap", sub: true }, { label: "　└ 食事", k: "m_meal", sub: true },
    { label: "　└ プール・水遊び", k: "m_pool", sub: true }, { label: "　└ 園外活動", k: "m_outdoor", sub: true },
    { label: "　└ バス送迎(実施時)", k: "m_bus", sub: true }, { label: "　└ 降雪(必要時)", k: "m_snow", sub: true },
    { label: "災害時マニュアル", k: "saigai" }, { label: "119番対応時マニュアル", k: "t119" },
    { label: "救急対応時マニュアル", k: "kyukyu" }, { label: "不審者対応時マニュアル", k: "fushinsha" },
  ];
  const TERMS = [["term1", "4〜6月"], ["term2", "7〜9月"], ["term3", "10〜12月"], ["term4", "1〜3月"]];
  const aoa: string[][] = [];
  const merges: { s: { r: number; c: number }; e: { r: number; c: number } }[] = [];
  const wide = (label: string) => { merges.push({ s: { r: aoa.length, c: 0 }, e: { r: aoa.length, c: 6 } }); aoa.push([label]); };
  wide(`保育安全計画　令和${p.fiscal_year}年度`);
  wide("◎安全点検");
  wide("(1) 施設・設備・園外環境(散歩コースや緊急避難先等)の安全点検");
  aoa.push(["月", ...H1.map((m) => `${m}月`)]);
  aoa.push(["重点点検箇所", ...H1.map((m) => c(`inspect_m${m}`))]);
  aoa.push(["月", ...H2.map((m) => `${m}月`)]);
  aoa.push(["重点点検箇所", ...H2.map((m) => c(`inspect_m${m}`))]);
  wide("(2) マニュアルの策定・共有");
  aoa.push(["分野", "策定時期", "見直し(再点検)予定時期", "掲示・管理場所"]);
  for (const m of MANUALS) {
    const label = m.sub && c(`${m.k}_check`) ? `${m.label}（${c(`${m.k}_check`)}）` : m.label;
    aoa.push([label, c(`${m.k}_estab`), c(`${m.k}_review`), c(`${m.k}_place`)]);
  }
  wide("◎児童・保護者に対する安全指導等");
  wide("(1) 児童への安全指導");
  aoa.push(["", ...TERMS.map((t) => t[1])]);
  aoa.push(["乳児・1歳以上3歳未満児", ...TERMS.map((t) => c(`infant_${t[0]}`))]);
  aoa.push(["3歳以上児", ...TERMS.map((t) => c(`over3_${t[0]}`))]);
  wide("(2) 保護者への説明・共有");
  aoa.push([...TERMS.map((t) => t[1])]);
  aoa.push([...TERMS.map((t) => c(`guardian_${t[0]}`))]);
  wide("◎訓練・研修");
  wide("(1) 訓練のテーマ・取組");
  aoa.push(["月", ...H1.map((m) => `${m}月`)]);
  aoa.push(["避難訓練等", ...H1.map((m) => c(`hinan_m${m}`))]);
  aoa.push(["その他", ...H1.map((m) => c(`other_m${m}`))]);
  aoa.push(["月", ...H2.map((m) => `${m}月`)]);
  aoa.push(["避難訓練等", ...H2.map((m) => c(`hinan_m${m}`))]);
  aoa.push(["その他", ...H2.map((m) => c(`other_m${m}`))]);
  wide("(2) 訓練の参加予定者(全員参加を除く)");
  aoa.push(["訓練内容", "参加予定者"]);
  for (let i = 1; i <= 5; i++) aoa.push([c(`drill${i}_content`), c(`drill${i}_who`)]);
  wide("(3) 職員への研修・講習(園内実施・外部実施を明記)");
  aoa.push([...TERMS.map((t) => t[1])]);
  aoa.push([...TERMS.map((t) => c(`staff_${t[0]}`))]);
  wide("(4) 行政等が実施する訓練・講習スケジュール");
  aoa.push([c("admin_schedule")]);
  wide("◎再発防止策の徹底(ヒヤリ・ハット事例の収集・分析及び対策とその共有)");
  aoa.push([c("prevention")]);
  wide("◎その他の安全確保に向けた取組");
  aoa.push([c("other")]);
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  ws["!cols"] = [{ wch: 24 }, { wch: 20 }, { wch: 20 }, { wch: 20 }, { wch: 16 }, { wch: 16 }, { wch: 16 }];
  ws["!merges"] = merges;
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, "保育安全計画");
  XLSX.writeFile(wb, `${filename}.xlsx`);
}

function PlanEditor(props: {
  detail: PlanDetail; isManager: boolean; isAdmin: boolean; busy: boolean; savedAt: string | null;
  individualTargets: { child_id: string; display_name: string; is_kahai: boolean }[];
  onField: (s: string, k: string, v: string) => void;
  onInsert: (s: string, k: string, v: string) => void;
  onSaveIndividual: (childId: string, content: Record<string, string>) => void;
  onClose: () => void; onSubmit: () => void; onChiefCheck: () => void; onApprove: () => void; onReject: () => void; onCancel: () => void; onCopyPrevious: () => void;
}) {
  const { detail, isManager, isAdmin } = props;
  const p = detail.plan;
  const st = p.status;
  const targetChildren = props.individualTargets;

  // AI下書き(月案・週案・未承認時)。連絡帳等を素材に各欄の下書きを生成→チェックで一括採用/追記。
  const [aiOpen, setAiOpen] = useState(false);
  const [aiBusy, setAiBusy] = useState(false);
  const [aiSections, setAiSections] = useState<Record<string, string>>({});
  const [aiMock, setAiMock] = useState(false);
  const [aiCounts, setAiCounts] = useState<{ contacts?: number; activities?: number; home?: number }>({});
  const [aiSelected, setAiSelected] = useState<Set<string>>(new Set());
  const [aiApplied, setAiApplied] = useState<Set<string>>(new Set());
  const canAi = (p.plan_type === "monthly" || p.plan_type === "weekly") && st !== "approved";

  // fieldKey → {sectionKey, label} をテンプレから作る。
  function fieldLookup(): Record<string, { sectionKey: string; label: string }> {
    const out: Record<string, { sectionKey: string; label: string }> = {};
    for (const sec of detail.template.sections) {
      for (const f of sec.fields) {
        out[f.key] = { sectionKey: sec.key, label: sec.label === f.label || !f.label ? sec.label : `${sec.label} / ${f.label}` };
      }
    }
    return out;
  }
  const aiOrdered = Object.keys(fieldLookup()).filter((k) => k in aiSections);

  async function generateAi() {
    setAiBusy(true);
    try {
      const { data, error } = await createClient().functions.invoke("generate-guidance-draft", { body: { plan_id: p.id } });
      if (error) { alert(`AI生成に失敗しました: ${error.message}`); return; }
      const d = data as { mock?: boolean; sections?: Record<string, string>; source_counts?: { contacts?: number; activities?: number; home?: number } };
      const secs = d.sections ?? {};
      if (Object.keys(secs).length === 0) { alert("生成できる下書きがありませんでした"); return; }
      setAiSections(secs);
      setAiMock(d.mock === true);
      setAiCounts(d.source_counts ?? {});
      const lk = fieldLookup();
      setAiSelected(new Set(Object.keys(secs).filter((k) => k in lk)));
      setAiApplied(new Set());
      setAiOpen(true);
    } catch (e) {
      alert(`AI生成に失敗しました: ${e instanceof Error ? e.message : e}`);
    } finally {
      setAiBusy(false);
    }
  }

  function applyAi(append: boolean) {
    const lk = fieldLookup();
    const applied = new Set(aiApplied);
    for (const key of aiOrdered) {
      if (!aiSelected.has(key)) continue;
      const add = aiSections[key] ?? "";
      if (append) {
        const cur = detail.plan.content[key] ?? "";
        props.onField(lk[key].sectionKey, key, cur.trim() ? `${cur}\n${add}` : add);
      } else {
        props.onField(lk[key].sectionKey, key, add);
      }
      applied.add(key);
    }
    setAiApplied(applied);
  }

  async function exportExcel() {
    const XLSX = await import("xlsx");
    const val = (sk: string, key: string) => (isReflection(sk, key) ? p.evaluation[key] : p.content[key]) ?? "";
    const period = p.month ? `${p.month}月` : p.week_start_date ? `${p.week_start_date}の週` : "";
    // 保育安全計画は様式構造(月別グリッド・マニュアル表・期別表)で出力。
    if (p.plan_type === "safety") {
      exportSafetyExcel(XLSX, p, `${detail.template.title}_${p.fiscal_year}`);
      return;
    }
    const aoa: (string | number)[][] = [[detail.template.title], [`${p.fiscal_year}年度 ${period}`], []];
    for (const sec of detail.template.sections) {
      aoa.push([sec.label]);
      for (const f of sec.fields) aoa.push([f.label, val(sec.key, f.key)]);
      aoa.push([]);
    }
    if (detail.individual.length > 0) {
      aoa.push(["個人案"], ["園児", "子どもの姿", "ねらい", "配慮・環境構成", "評価・反省"]);
      for (const e of detail.individual)
        aoa.push([e.child_name, e.content.kidsstate ?? "", e.content.aim ?? "", e.content.consideration ?? "", e.content.reflection ?? ""]);
    }
    const ws = XLSX.utils.aoa_to_sheet(aoa);
    ws["!cols"] = [{ wch: 22 }, { wch: 40 }, { wch: 24 }, { wch: 24 }, { wch: 24 }];
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "指導計画");
    XLSX.writeFile(wb, `${detail.template.title}_${p.fiscal_year}${period ? "_" + period : ""}.xlsx`);
  }

  return (
    <section className="space-y-4 rounded-2xl border-2 border-sky-200 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-base font-bold text-slate-800">{detail.template.title}
          <span className={`ml-3 rounded-full px-2 py-0.5 text-xs font-semibold ${(STATUS_LABEL[st] ?? STATUS_LABEL.draft).cls}`}>{(STATUS_LABEL[st] ?? { label: st }).label}</span>
        </h3>
        <div className="flex items-center gap-3">
          {props.savedAt && <span className="text-xs text-slate-400">{props.savedAt}</span>}
          {canAi && (
            <button onClick={() => void generateAi()} disabled={aiBusy}
              className="rounded-lg border border-purple-300 px-3 py-1 text-xs font-semibold text-purple-700 hover:bg-purple-50 disabled:opacity-50">
              {aiBusy ? "生成中…" : "✨ AIで下書き"}
            </button>
          )}
          <button onClick={async () => {
            const { data, error } = await createClient().rpc("fetch_previous_guidance_plan_id", { p_id: p.id });
            if (error) { alert(error.message); return; }
            if (!data) { alert("前回の計画が見つかりません"); return; }
            window.open(`/childcare/guidance-plans/print?id=${data}`, "_blank");
          }} className="rounded-lg border border-violet-300 px-3 py-1 text-xs font-semibold text-violet-700 hover:bg-violet-50">前回を参照</button>
          {st !== "approved" && (
            <button onClick={props.onCopyPrevious} disabled={props.busy}
              className="rounded-lg border border-violet-300 px-3 py-1 text-xs font-semibold text-violet-700 hover:bg-violet-50 disabled:opacity-50">前回コピー</button>
          )}
          <button onClick={() => window.open(`/childcare/guidance-plans/print?id=${p.id}`, "_blank")}
            className="rounded-lg border border-emerald-300 px-3 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-50">印刷 / PDF</button>
          <button onClick={exportExcel}
            className="rounded-lg border border-emerald-300 px-3 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-50">Excel</button>
          <button onClick={props.onClose} className="rounded-lg border border-slate-300 px-3 py-1 text-xs text-slate-500 hover:bg-slate-50">閉じる</button>
        </div>
      </div>
      {p.rejected_reason && <p className="rounded-lg bg-red-50 p-2 text-sm text-red-600">差し戻し/取消理由: {p.rejected_reason}</p>}
      {st === "approved" && <p className="rounded-lg bg-emerald-50 p-2 text-xs text-emerald-700">承認済みです。本文は編集できません(評価・反省欄は記入可能)。修正は承認取消から。</p>}

      {aiOpen && (() => {
        const lk = fieldLookup();
        return (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setAiOpen(false)}>
            <div className="flex max-h-[88vh] w-full max-w-3xl flex-col rounded-2xl bg-white shadow-xl" onClick={(e) => e.stopPropagation()}>
              <div className="flex items-center gap-2 border-b border-slate-100 px-5 py-3">
                <span className="text-base font-bold text-purple-700">✨ AI下書きの確認</span>
                <span className="ml-auto text-xs text-slate-400">連絡帳{aiCounts.contacts ?? 0}・活動{aiCounts.activities ?? 0}・家庭{aiCounts.home ?? 0}</span>
              </div>
              {aiMock && <div className="mx-5 mt-3 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-700">※ サンプル下書きです(AIキー未設定)。キー設定後に実際の記録から生成されます。</div>}
              <div className="flex items-center gap-2 px-5 py-2">
                <span className="text-xs text-slate-500">採用する欄にチェック → 下の「選択を採用/追記」でまとめて反映。</span>
                <button className="ml-auto text-xs font-semibold text-purple-700"
                  onClick={() => setAiSelected(aiSelected.size === aiOrdered.length ? new Set() : new Set(aiOrdered))}>
                  {aiSelected.size === aiOrdered.length ? "全解除" : "全選択"}
                </button>
              </div>
              <div className="flex-1 space-y-3 overflow-y-auto px-5 pb-3">
                {aiOrdered.map((key) => {
                  const checked = aiSelected.has(key);
                  const applied = aiApplied.has(key);
                  const cur = detail.plan.content[key] ?? "";
                  return (
                    <div key={key} className={`rounded-xl border p-3 ${applied ? "border-emerald-300 bg-emerald-50/40" : checked ? "border-purple-300" : "border-slate-200"}`}>
                      <label className="flex cursor-pointer items-center gap-2">
                        <input type="checkbox" checked={checked} onChange={() => {
                          const n = new Set(aiSelected);
                          if (n.has(key)) { n.delete(key); } else { n.add(key); }
                          setAiSelected(n);
                        }} />
                        <span className="font-bold text-slate-800">{lk[key].label}</span>
                        {applied && <span className="ml-auto text-xs font-semibold text-emerald-600">反映済</span>}
                      </label>
                      {cur.trim() && <p className="mt-2 whitespace-pre-wrap text-xs text-slate-400">現在: {cur}</p>}
                      <p className="mt-1 whitespace-pre-wrap rounded-lg bg-purple-50/60 p-2 text-sm text-slate-800">{aiSections[key]}</p>
                    </div>
                  );
                })}
              </div>
              <div className="flex items-center gap-2 border-t border-slate-100 px-5 py-3">
                <span className="text-sm text-slate-500">{aiSelected.size}件選択</span>
                <button disabled={aiSelected.size === 0} onClick={() => applyAi(true)}
                  className="ml-auto rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-semibold text-slate-600 hover:bg-slate-50 disabled:opacity-50">選択を追記</button>
                <button disabled={aiSelected.size === 0} onClick={() => applyAi(false)}
                  className="rounded-lg bg-purple-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-purple-700 disabled:opacity-50">選択を採用(置換)</button>
                <button onClick={() => setAiOpen(false)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm text-slate-500 hover:bg-slate-50">閉じる</button>
              </div>
            </div>
          </div>
        );
      })()}

      {detail.template.sections.map((sec) => (
        <div key={sec.key} className="rounded-xl border border-slate-200 p-3">
          <p className="text-sm font-bold text-slate-700">{sec.label}</p>
          {sec.hint && <p className="mt-0.5 text-xs text-slate-400">💡 {sec.hint}</p>}
          <div className="mt-2 space-y-3">
            {sec.fields.map((f) => {
              const refl = isReflection(sec.key, f.key);
              const val = (refl ? p.evaluation[f.key] : p.content[f.key]) ?? "";
              const editable = refl || st !== "approved";
              return (
                <div key={f.key}>
                  <div className="mb-1 flex flex-wrap items-center gap-2">
                    <span className="text-sm font-medium text-slate-600">{f.label}{f.required && <span className="text-red-500">*</span>}</span>
                    {f.subject && <span className="rounded bg-slate-100 px-1.5 text-xs text-slate-400">{f.subject}が主語</span>}
                  </div>
                  {f.hint && <p className="mb-1 text-xs text-slate-400">💡 {f.hint}</p>}
                  <textarea value={val} disabled={!editable} rows={2}
                    onChange={(e) => props.onField(sec.key, f.key, e.target.value)}
                    className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm disabled:bg-slate-50 disabled:text-slate-400" />
                  {editable && f.examples && f.examples.length > 0 && (
                    <div className="mt-1 flex flex-wrap gap-1">
                      <span className="text-xs text-slate-400">例文:</span>
                      {f.examples.map((ex, i) => (
                        <button key={i} onClick={() => props.onInsert(sec.key, f.key, ex)}
                          className="rounded-full border border-emerald-300 px-2 py-0.5 text-xs text-emerald-700 hover:bg-emerald-50">＋ {ex.length > 24 ? ex.slice(0, 24) + "…" : ex}</button>
                      ))}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      ))}

      {/* 個人案(月案・クラスの園児) */}
      {targetChildren.length > 0 && (
        <div className="rounded-xl border border-violet-200 bg-violet-50/40 p-3">
          <p className="text-sm font-bold text-violet-700">個人案(このクラスの園児)</p>
          <div className="mt-2 space-y-3">
            {targetChildren.map((c) => {
              const existing = detail.individual.find((e) => e.child_id === c.child_id)?.content ?? {};
              return <IndividualRow key={c.child_id} child={c} initial={existing} disabled={st === "approved"} onSave={props.onSaveIndividual} />;
            })}
          </div>
        </div>
      )}

      {/* ワークフロー */}
      <div className="flex flex-wrap justify-end gap-2 border-t border-slate-100 pt-3">
        {st === "draft" && <button disabled={props.busy} onClick={props.onSubmit} className="rounded-lg bg-sky-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">申請する</button>}
        {st === "submitted" && isManager && <>
          <button disabled={props.busy} onClick={props.onReject} className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">差し戻し</button>
          <button disabled={props.busy} onClick={props.onChiefCheck} className="rounded-lg border border-sky-400 px-4 py-2 text-sm font-semibold text-sky-700 hover:bg-sky-50">主任確認(大和)</button>
          {isAdmin && <button disabled={props.busy} onClick={props.onApprove} className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">承認(企業主導型)</button>}
        </>}
        {st === "chief_checked" && isAdmin && <>
          <button disabled={props.busy} onClick={props.onReject} className="rounded-lg bg-red-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">差し戻し</button>
          <button disabled={props.busy} onClick={props.onApprove} className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">承認する</button>
        </>}
        {st === "approved" && isAdmin && <button disabled={props.busy} onClick={props.onCancel} className="rounded-lg border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50">承認取消</button>}
      </div>
    </section>
  );
}

function IndividualRow(props: { child: { child_id: string; display_name: string }; initial: Record<string, string>; disabled: boolean; onSave: (id: string, c: Record<string, string>) => void }) {
  const [content, setContent] = useState<Record<string, string>>(props.initial);
  const t = useRef<ReturnType<typeof setTimeout> | null>(null);
  function set(k: string, v: string) {
    const next = { ...content, [k]: v };
    setContent(next);
    if (t.current) clearTimeout(t.current);
    t.current = setTimeout(() => props.onSave(props.child.child_id, next), 1000);
  }
  return (
    <div className="rounded-lg border border-violet-200 bg-white p-2">
      <p className="text-sm font-bold text-slate-800">{props.child.display_name}</p>
      <div className="mt-1 grid gap-2 sm:grid-cols-2">
        {INDIVIDUAL_FIELDS.map((f) => (
          <label key={f.key} className="text-xs text-slate-500">{f.label}
            <textarea value={content[f.key] ?? ""} disabled={props.disabled} rows={2}
              onChange={(e) => set(f.key, e.target.value)}
              className="mt-0.5 w-full rounded border border-slate-300 px-2 py-1 text-sm disabled:bg-slate-50" />
          </label>
        ))}
      </div>
    </div>
  );
}

export default function GuidancePlansPage() {
  return (<Suspense fallback={<div className="p-8 text-sm text-slate-400">読み込み中…</div>}><GuidancePlansContent /></Suspense>);
}
