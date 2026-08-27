"use client";

import { Suspense, useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { AppHeader } from "@/components/AppHeader";
import { ChildcareNav } from "@/components/ChildcareNav";
import { useChildcareOffices } from "@/hooks/useChildcareOffices";
import { exportRegisterXlsx, exportTimeXlsx, exportChildXlsx } from "@/lib/export/attendanceExports";

// 登降園管理(314/317/318/323/324)。日別=時刻の行内修正+備考、月間=出欠/時刻/園児別の3ビュー。主任以上。
type Row = {
  child_id: string;
  child_name: string;
  class_name: string | null;
  business_date: string;
  in_time: string | null;
  out_time: string | null;
  return_time: string | null;
  depart_time: string | null;
  is_absent: boolean;
  absence_reason: string | null;
  absence_kind: string | null;
  note: string | null;
};
// 出席簿の記号: 病=病欠 / 都=都合欠 / 欠=種別不明の欠席 / ◯=出席 / 空=記録なし。
function registerSymbol(r: Row): string {
  if (r.is_absent) return r.absence_kind === "sick_absence" ? "病" : r.absence_kind === "personal_absence" ? "都" : "欠";
  if (r.in_time || r.depart_time) return "◯";
  return "";
}
type Edit = { in: string; out: string; ret: string; depart: string; note: string };
// Phase B(317): 要確認(anomaly)。severity=action は補正必須(確認済み不可)。
type Anomaly = { child_id: string; business_date: string; anomaly_type: string; label: string; severity: string };
type AuditRow = { occurred_at: string; operator: string; target_type: string; action: string; before_data: Record<string, unknown> | null; after_data: Record<string, unknown> | null };
type ReportLog = { output_at: string; operator: string; report_type: string; format: string; params: Record<string, unknown> | null; row_count: number | null };
const REPORT_TYPE_LABEL: Record<string, string> = { attendance_register: "出席簿", attendance_actuals: "登降園実績表" };
const anomKey = (childId: string, date: string) => `${childId}__${date.slice(0, 10)}`;

function todayStr(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}
const hhmm = (t: string | null) => (t ? t.slice(0, 5) : "");
const WEEKDAYS = ["日", "月", "火", "水", "木", "金", "土"];
// 欠席理由プルダウン: 出席(none)/病欠/都合欠。set_child_absence_kind(325)へ渡す。
const ABSENCE_OPTIONS: { v: string; l: string }[] = [
  { v: "none", l: "出席" },
  { v: "sick_absence", l: "病欠" },
  { v: "personal_absence", l: "都合欠" },
];
// 現在の状態→プルダウン値。種別不明の欠席は "" (未選択)にして再選択を促す。
function kindValue(r: Row | undefined): string {
  if (!r || !r.is_absent) return "none";
  if (r.absence_kind === "sick_absence" || r.absence_kind === "personal_absence") return r.absence_kind;
  return "";
}

// ── 監査履歴(378)の表示ヘルパ ──
const auditTargetLabel = (t: string): string =>
  ({ child_daily_attendance: "出欠", child_attendance_events: "打刻", child_outings: "外出" } as Record<string, string>)[t] ?? t;
const auditActionLabel = (a: string): string =>
  ({ INSERT: "登録", UPDATE: "変更", DELETE: "取消" } as Record<string, string>)[a] ?? a;
// target_type ごとに、履歴に出す列と日本語ラベル。
const AUDIT_FIELDS: Record<string, [string, string][]> = {
  child_daily_attendance: [["is_absent", "欠席"], ["attendance_kind", "区分"], ["absence_reason", "欠席理由"], ["attendance_note", "出欠メモ"]],
  child_attendance_events: [["event_type", "種別"], ["occurred_at", "時刻"], ["rejection_reason", "却下理由"], ["admin_override_reason", "上書き理由"]],
  child_outings: [["reason", "理由"], ["reason_note", "補足"], ["out_at", "外出"], ["return_planned_at", "戻り予定"], ["return_at", "戻り"], ["converted_to_departure", "降園変換"]],
};
function fmtAuditVal(key: string, raw: unknown): string {
  if (raw == null || raw === "") return "—";
  const s = String(raw);
  if (key === "is_absent") return s === "true" ? "欠席" : "出席";
  if (key === "converted_to_departure") return s === "true" ? "はい" : "いいえ";
  if (key === "attendance_kind") return ({ none: "出席", late: "遅刻", early_leave: "早退", sick_absence: "病欠", personal_absence: "都合欠" } as Record<string, string>)[s] ?? s;
  if (key === "event_type")
    return ({ drop_off: "登園", pick_up: "降園", proxy_drop_off: "代理登園", proxy_pick_up: "代理降園", rejected: "却下", out: "外出", return: "戻り" } as Record<string, string>)[s] ?? s;
  if (key === "reason") return ({ therapy: "療育", checkup: "健診", other: "その他" } as Record<string, string>)[s] ?? s;
  if (["occurred_at", "out_at", "return_planned_at", "return_at"].includes(key)) {
    const d = new Date(s);
    return isNaN(d.getTime()) ? s : d.toLocaleString("ja-JP", { timeZone: "Asia/Tokyo", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
  }
  return s;
}
// 1件の監査行を「登園08:30 のように」人間可読な差分文にする。
// UPDATE=before→after で変化した列のみ / INSERT=after の主要列 / DELETE=before の主要列。
function auditDetail(row: AuditRow): { field: string; text: string }[] {
  const fields = AUDIT_FIELDS[row.target_type] ?? [];
  const before = row.before_data ?? {};
  const after = row.after_data ?? {};
  const out: { field: string; text: string }[] = [];
  for (const [key, label] of fields) {
    const b = before[key] ?? null;
    const a = after[key] ?? null;
    if (row.action === "UPDATE") {
      if (String(b ?? "") === String(a ?? "")) continue;
      out.push({ field: label, text: `${fmtAuditVal(key, b)} → ${fmtAuditVal(key, a)}` });
    } else {
      const v = row.action === "DELETE" ? b : a;
      if (v == null || v === "") continue;
      out.push({ field: label, text: fmtAuditVal(key, v) });
    }
  }
  return out;
}
const MONTH_COL_WIDTH = 34; // 月間の日カラム最小幅(出欠/時刻で揃える。全幅テーブルで31日+集計が横スクロールなしで収まる目安)。

function AttendanceContent() {
  const { offices, officesError, selectedOffice } = useChildcareOffices();
  const officeName = offices?.find((o) => o.office_id === selectedOffice)?.office_name ?? "";
  const now = new Date();
  const [mode, setMode] = useState<"day" | "month">("day");
  const [monthSub, setMonthSub] = useState<"attendance" | "time" | "child">("attendance");
  const [date, setDate] = useState(todayStr());
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [rows, setRows] = useState<Row[]>([]);
  const [anomalies, setAnomalies] = useState<Anomaly[]>([]);
  const [edits, setEdits] = useState<Record<string, Edit>>({});
  const [selectedChild, setSelectedChild] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  // 休園日(網掛け・開所日数・375)。day番号 → 理由/ラベル。
  const [closures, setClosures] = useState<Record<number, { reason: string | null; label: string | null }>>({});
  const [openDays, setOpenDays] = useState<number | null>(null);
  // 監査履歴モーダル(378)。開いている園児と取得行。
  const [reportLogsOpen, setReportLogsOpen] = useState(false);
  const [reportLogs, setReportLogs] = useState<ReportLog[] | null>(null);
  const [auditFor, setAuditFor] = useState<{ childId: string; name: string } | null>(null);
  const [auditRows, setAuditRows] = useState<AuditRow[] | null>(null);

  useEffect(() => {
    if (!selectedOffice) return;
    const p = (n: number) => String(n).padStart(2, "0");
    const start = mode === "day" ? date : `${year}-${p(month)}-01`;
    const end = mode === "day" ? date : `${year}-${p(month)}-${p(new Date(year, month, 0).getDate())}`;
    const supabase = createClient();
    supabase
      .rpc("fetch_attendance_matrix_for_office", { p_office_id: selectedOffice, p_start: start, p_end: end })
      .then(({ data, error }) => {
        if (error) { setErr(error.message); setRows([]); return; }
        setErr(null);
        const rs = (data ?? []) as Row[];
        setRows(rs);
        if (mode === "day") {
          const e: Record<string, Edit> = {};
          for (const r of rs) e[r.child_id] = { in: hhmm(r.in_time), out: hhmm(r.out_time), ret: hhmm(r.return_time), depart: hhmm(r.depart_time), note: r.note ?? "" };
          setEdits(e);
        }
      });
    // 要確認(317)。付加情報のため失敗しても本体表示は継続。
    supabase
      .rpc("fetch_attendance_anomalies_for_office", { p_office_id: selectedOffice, p_start: start, p_end: end })
      .then(({ data }) => setAnomalies((data ?? []) as Anomaly[]));
    // 休園日カレンダー(375)。月間ビューの網掛け・開所日数。
    if (mode === "month") {
      supabase
        .rpc("fetch_office_closure_calendar", { p_office: selectedOffice, p_year: year, p_month: month })
        .then(({ data }) => {
          const map: Record<number, { reason: string | null; label: string | null }> = {};
          for (const c of (data ?? []) as { business_date: string; closed: boolean; reason: string | null; label: string | null }[]) {
            if (c.closed) map[Number(c.business_date.slice(8, 10))] = { reason: c.reason, label: c.label };
          }
          setClosures(map);
        });
      supabase
        .rpc("count_office_open_days", { p_office: selectedOffice, p_year: year, p_month: month })
        .then(({ data }) => setOpenDays((data as number | null) ?? null));
    } else {
      setClosures({});
      setOpenDays(null);
    }
  }, [selectedOffice, mode, date, year, month, reloadToken]);

  // (child_id+日) → 要確認ラベル配列。
  const anomByKey = new Map<string, string[]>();
  for (const a of anomalies) {
    const k = anomKey(a.child_id, a.business_date);
    if (!anomByKey.has(k)) anomByKey.set(k, []);
    anomByKey.get(k)!.push(a.label);
  }

  async function saveActuals(childId: string) {
    const e = edits[childId];
    if (!e) return;
    setBusy(true);
    const s = createClient();
    const { error } = await s.rpc("set_child_attendance_actuals", {
      p_child_id: childId, p_business_date: date,
      p_in: e.in || null, p_out: e.out || null, p_return: e.ret || null, p_depart: e.depart || null,
    });
    // 備考も同時に保存(324)。
    const { error: noteErr } = await s.rpc("set_child_attendance_note", { p_child_id: childId, p_business_date: date, p_note: e.note || null });
    setBusy(false);
    if (error || noteErr) return setErr((error ?? noteErr)!.message);
    setErr(null);
    setReloadToken((t) => t + 1);
  }

  // 監査履歴を開く(378)。園児×当日の登降園・打刻・外出の変更履歴を event_logs から取得。
  async function openAudit(childId: string, name: string) {
    setAuditFor({ childId, name });
    setAuditRows(null);
    const { data, error } = await createClient().rpc("fetch_child_attendance_audit", { p_child_id: childId, p_business_date: date });
    if (error) { setErr(error.message); setAuditRows([]); return; }
    setAuditRows((data ?? []) as AuditRow[]);
  }

  // 備考のみ保存(欠席児は時刻の保存ボタンが無効なため、備考はフォーカスアウトで即保存)。
  async function saveNote(childId: string, note: string) {
    const { error } = await createClient().rpc("set_child_attendance_note", { p_child_id: childId, p_business_date: date, p_note: note || null });
    if (error) { setErr(error.message); return; }
    setErr(null);
  }

  // 欠席理由(出席/病欠/都合欠)の保存(325)。日別・園児別のプルダウンから。
  async function saveAbsenceKind(childId: string, businessDate: string, kind: string) {
    setBusy(true);
    const { error } = await createClient().rpc("set_child_absence_kind", {
      p_child_id: childId, p_business_date: businessDate, p_kind: kind,
    });
    setBusy(false);
    if (error) return setErr(error.message);
    setErr(null);
    setReloadToken((t) => t + 1);
  }

  // 要確認セルをクリック→その日の日別(修正)へ移動し、登降園時刻をその場で登録/修正できる(俊指示 2026-08-25)。
  function jumpToDayEdit(businessDate: string) {
    setDate(businessDate.slice(0, 10));
    setMode("day");
  }

  // Excel出力(俊指示 2026-08-25: CSV→Excel・月付き日付・中央寄せ・罫線・縞模様・欠席児下部・集計)。
  // 出欠→出席簿(◯/病欠/都合欠+集計) / 時刻→登降園時刻(登園/降園/欠席の3行) / 園児別→選択児の1ヶ月。
  function onExport() {
    if (monthSub === "attendance") { void exportRegisterXlsx(rows, year, month, closures, openDays); return; }
    if (monthSub === "time") { void exportTimeXlsx(rows, year, month); return; }
    const seen = new Set<string>();
    const children: { id: string; name: string; cls: string | null }[] = [];
    for (const r of rows) if (!seen.has(r.child_id)) { seen.add(r.child_id); children.push({ id: r.child_id, name: r.child_name, cls: r.class_name }); }
    const cid = selectedChild && children.some((c) => c.id === selectedChild) ? selectedChild : children[0]?.id ?? "";
    const c = children.find((x) => x.id === cid);
    if (c) void exportChildXlsx(rows, year, month, c.id, c.name, c.cls);
  }

  // 帳票出力履歴(§7・379)。管理者以上のみ閲覧可(RPCが権限判定)。
  async function openReportLogs() {
    setReportLogsOpen(true);
    setReportLogs(null);
    const { data, error } = await createClient().rpc("fetch_report_output_logs", { p_office_id: selectedOffice, p_limit: 100 });
    if (error) { setErr(error.message); setReportLogs([]); return; }
    setReportLogs((data ?? []) as ReportLog[]);
  }

  // 帳票PDF(§7)。出席簿/登降園実績表をサーバー生成(pdfkit)→DL→監査ログ(log_report_output・379)。
  async function onExportPdf(reportType: "register" | "actuals") {
    if (rows.length === 0) return;
    setBusy(true);
    try {
      const res = await fetch("/api/childcare/attendance-pdf", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          reportType, officeName, year, month, openDays,
          closureDays: Object.keys(closures).map(Number),
          rows,
        }),
      });
      if (!res.ok) throw new Error("PDF生成に失敗しました");
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${reportType === "actuals" ? "登降園実績表" : "出席簿"}_${year}-${String(month).padStart(2, "0")}.pdf`;
      a.click();
      URL.revokeObjectURL(url);
      // DL成功後に出力を記録(主任以上)。失敗しても帳票DLは成立しているのでUIは止めない。
      const childCount = new Set(rows.map((r) => r.child_id)).size;
      await createClient().rpc("log_report_output", {
        p_office_id: selectedOffice,
        p_report_type: reportType === "actuals" ? "attendance_actuals" : "attendance_register",
        p_format: "pdf",
        p_params: { year, month },
        p_row_count: childCount,
      });
      setErr(null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : "PDF生成に失敗しました");
    } finally {
      setBusy(false);
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

  return (
    <div className="flex flex-1 flex-col">
      <AppHeader />
      <ChildcareNav />
      <main className="flex-1 space-y-4 p-6">
        <div className="flex flex-wrap items-center gap-3">
          <h2 className="text-lg font-bold text-slate-800">登降園管理</h2>
          <div className="ml-2 flex gap-1 rounded-lg bg-slate-100 p-1">
            <button onClick={() => setMode("day")} className={`rounded-md px-3 py-1 text-sm font-semibold ${mode === "day" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>日別</button>
            <button onClick={() => setMode("month")} className={`rounded-md px-3 py-1 text-sm font-semibold ${mode === "month" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>月間</button>
          </div>
          {mode === "day" ? (
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm" />
          ) : (
            <>
              <select value={year} onChange={(e) => setYear(Number(e.target.value))} className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                {[year - 1, year, year + 1].map((y) => <option key={y} value={y}>{y}年</option>)}
              </select>
              <select value={month} onChange={(e) => setMonth(Number(e.target.value))} className="rounded-lg border border-slate-300 px-2 py-1.5 text-sm">
                {Array.from({ length: 12 }, (_, i) => i + 1).map((m) => <option key={m} value={m}>{m}月</option>)}
              </select>
              {/* 月間の表示種類: 出欠(◯/欠) / 時刻(登降園時刻) / 園児別(1名の1ヶ月) */}
              <div className="flex gap-1 rounded-lg bg-slate-100 p-1">
                <button onClick={() => setMonthSub("attendance")} className={`rounded-md px-2.5 py-1 text-xs font-semibold ${monthSub === "attendance" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>出欠</button>
                <button onClick={() => setMonthSub("time")} className={`rounded-md px-2.5 py-1 text-xs font-semibold ${monthSub === "time" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>時刻</button>
                <button onClick={() => setMonthSub("child")} className={`rounded-md px-2.5 py-1 text-xs font-semibold ${monthSub === "child" ? "bg-white text-emerald-700 shadow-sm" : "text-slate-500"}`}>園児別</button>
              </div>
              <button
                onClick={onExport}
                disabled={rows.length === 0}
                className="rounded-lg bg-emerald-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-emerald-700 disabled:opacity-40"
              >
                {monthSub === "attendance" ? "出席簿Excel" : monthSub === "child" ? "園児別Excel" : "時刻Excel"}
              </button>
              {/* 帳票PDF(§7・主任以上)。出席簿/登降園実績表。出力は監査ログに記録。 */}
              <button
                onClick={() => void onExportPdf("register")}
                disabled={rows.length === 0 || busy}
                className="rounded-lg border border-emerald-600 px-3 py-1.5 text-sm font-semibold text-emerald-700 hover:bg-emerald-50 disabled:opacity-40"
              >
                出席簿PDF
              </button>
              <button
                onClick={() => void onExportPdf("actuals")}
                disabled={rows.length === 0 || busy}
                className="rounded-lg border border-emerald-600 px-3 py-1.5 text-sm font-semibold text-emerald-700 hover:bg-emerald-50 disabled:opacity-40"
              >
                実績表PDF
              </button>
              {/* 出力履歴(§7・管理者以上)。誰がいつ何を出力したか。 */}
              <button
                onClick={() => void openReportLogs()}
                className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-slate-50"
              >
                出力履歴
              </button>
            </>
          )}
          <span className="text-xs text-slate-400">※ 赤=要確認(補正が必要)。編集は主任以上。</span>
        </div>
        {anomalies.length > 0 && (
          <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-2 text-sm text-red-700">
            <span className="font-bold">⚠ 要確認 {anomalies.length}件</span>
            <span className="ml-2 text-red-600">— 登降園実績を補正してください(補正まで請求候補に進みません)。</span>
          </div>
        )}
        {err && <div className="rounded-lg bg-red-50 px-4 py-2 text-sm text-red-600">{err}</div>}

        {mode === "day" ? <DayView /> : monthSub === "child" ? <ChildMonthView /> : <MonthGridView withTime={monthSub === "time"} />}
      </main>
      {auditFor && <AuditModal />}
      {reportLogsOpen && <ReportLogsModal />}
    </div>
  );

  // 帳票出力履歴モーダル(§7・379)。管理者以上が閲覧。
  function ReportLogsModal() {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setReportLogsOpen(false)}>
        <div className="max-h-[80vh] w-full max-w-2xl overflow-y-auto rounded-2xl bg-white shadow-xl" onClick={(e) => e.stopPropagation()}>
          <div className="flex items-center justify-between border-b border-slate-200 px-5 py-3">
            <div>
              <div className="text-sm font-bold text-slate-800">帳票 出力履歴</div>
              <div className="text-xs text-slate-400">誰がいつ何を出力したか(管理者以上)</div>
            </div>
            <button onClick={() => setReportLogsOpen(false)} className="rounded-lg px-2 py-1 text-lg leading-none text-slate-400 hover:bg-slate-100">×</button>
          </div>
          <div className="p-5">
            {reportLogs === null && <div className="py-8 text-center text-sm text-slate-400">読み込み中…</div>}
            {reportLogs !== null && reportLogs.length === 0 && <div className="py-8 text-center text-sm text-slate-400">出力履歴はありません。</div>}
            {reportLogs !== null && reportLogs.length > 0 && (
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                    <th className="px-2 py-1.5">日時</th><th className="px-2 py-1.5">操作者</th><th className="px-2 py-1.5">帳票</th>
                    <th className="px-2 py-1.5">形式</th><th className="px-2 py-1.5">対象</th><th className="px-2 py-1.5">件数</th>
                  </tr>
                </thead>
                <tbody>
                  {reportLogs.map((l, i) => {
                    const p = l.params ?? {};
                    const period = p.year && p.month ? `${p.year}年${p.month}月` : "";
                    return (
                      <tr key={i} className="border-b border-slate-100">
                        <td className="px-2 py-1.5 font-mono text-xs text-slate-500">{new Date(l.output_at).toLocaleString("ja-JP", { timeZone: "Asia/Tokyo", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" })}</td>
                        <td className="px-2 py-1.5 text-slate-700">{l.operator}</td>
                        <td className="px-2 py-1.5 text-slate-700">{REPORT_TYPE_LABEL[l.report_type] ?? l.report_type}</td>
                        <td className="px-2 py-1.5 uppercase text-slate-500">{l.format}</td>
                        <td className="px-2 py-1.5 text-slate-500">{period}</td>
                        <td className="px-2 py-1.5 tabular-nums text-slate-500">{l.row_count ?? "—"}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        </div>
      </div>
    );
  }

  // 監査履歴モーダル(378)。園児×当日の登降園・打刻・外出の変更を時系列で表示。
  function AuditModal() {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setAuditFor(null)}>
        <div className="max-h-[80vh] w-full max-w-2xl overflow-y-auto rounded-2xl bg-white shadow-xl" onClick={(e) => e.stopPropagation()}>
          <div className="flex items-center justify-between border-b border-slate-200 px-5 py-3">
            <div>
              <div className="text-sm font-bold text-slate-800">{auditFor!.name} — 変更履歴</div>
              <div className="text-xs text-slate-400">{date} の登降園・打刻・外出の記録</div>
            </div>
            <button onClick={() => setAuditFor(null)} className="rounded-lg px-2 py-1 text-lg leading-none text-slate-400 hover:bg-slate-100">×</button>
          </div>
          <div className="p-5">
            {auditRows === null && <div className="py-8 text-center text-sm text-slate-400">読み込み中…</div>}
            {auditRows !== null && auditRows.length === 0 && <div className="py-8 text-center text-sm text-slate-400">この日の変更履歴はありません。</div>}
            {auditRows !== null && auditRows.length > 0 && (
              <ol className="space-y-2">
                {auditRows.map((r, i) => {
                  const diffs = auditDetail(r);
                  const time = new Date(r.occurred_at).toLocaleString("ja-JP", { timeZone: "Asia/Tokyo", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
                  return (
                    <li key={i} className="rounded-xl border border-slate-200 px-4 py-2.5">
                      <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
                        <span className="font-mono text-slate-400">{time}</span>
                        <span className="rounded bg-slate-100 px-1.5 py-0.5 font-semibold text-slate-600">{auditTargetLabel(r.target_type)}</span>
                        <span className={`rounded px-1.5 py-0.5 font-semibold ${r.action === "DELETE" ? "bg-red-100 text-red-600" : r.action === "INSERT" ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700"}`}>{auditActionLabel(r.action)}</span>
                        <span className="text-slate-500">{r.operator}</span>
                      </div>
                      {diffs.length > 0 && (
                        <div className="mt-1.5 flex flex-wrap gap-x-4 gap-y-0.5 text-sm text-slate-700">
                          {diffs.map((d, j) => (
                            <span key={j}><span className="text-slate-400">{d.field}:</span> {d.text}</span>
                          ))}
                        </div>
                      )}
                    </li>
                  );
                })}
              </ol>
            )}
          </div>
        </div>
      </div>
    );
  }

  function DayView() {
    return (
      <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
              <th className="px-3 py-2">クラス</th><th className="px-3 py-2">園児</th><th className="px-3 py-2">欠席</th>
              <th className="px-3 py-2">登園</th><th className="px-3 py-2">外出</th><th className="px-3 py-2">戻り</th><th className="px-3 py-2">降園</th>
              <th className="px-3 py-2"></th><th className="px-3 py-2">備考</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan={9} className="px-3 py-6 text-center text-slate-400">在籍児がいません</td></tr>}
            {rows.map((r) => {
              const e = edits[r.child_id] ?? { in: "", out: "", ret: "", depart: "", note: "" };
              const set = (k: keyof Edit, v: string) => setEdits((prev) => ({ ...prev, [r.child_id]: { ...e, [k]: v } }));
              const anoms = anomByKey.get(anomKey(r.child_id, date)) ?? [];
              const miss = anoms.length > 0;
              return (
                <tr key={r.child_id} className={`border-b border-slate-100 ${miss ? "bg-red-50" : ""}`}>
                  <td className="px-3 py-2 text-slate-500">{r.class_name ?? "—"}</td>
                  <td className="px-3 py-2 font-medium text-slate-800">
                    {r.child_name}
                    {anoms.map((l) => (
                      <span key={l} className="ml-1 rounded bg-red-100 px-1.5 py-0.5 text-xs font-bold text-red-600">{l}</span>
                    ))}
                  </td>
                  <td className="px-3 py-2">
                    {/* 欠席理由プルダウン(出席/病欠/都合欠)。選択で set_child_absence_kind に保存。 */}
                    <select value={kindValue(r)} onChange={(ev) => void saveAbsenceKind(r.child_id, date, ev.target.value)}
                      className={`rounded border px-1.5 py-1 text-xs ${r.is_absent ? "border-red-300 bg-red-50 text-red-700" : "border-slate-300"}`}>
                      {kindValue(r) === "" && <option value="">欠席(種別未設定)</option>}
                      {ABSENCE_OPTIONS.map((o) => <option key={o.v} value={o.v}>{o.l}</option>)}
                    </select>
                  </td>
                  {(["in", "out", "ret", "depart"] as (keyof Edit)[]).map((k) => (
                    <td key={k} className="px-2 py-2">
                      <input type="time" value={e[k]} disabled={r.is_absent} onChange={(ev) => set(k, ev.target.value)}
                        className="rounded border border-slate-300 px-1 py-1 text-sm disabled:bg-slate-100" />
                    </td>
                  ))}
                  <td className="px-3 py-2">
                    <div className="flex items-center gap-2">
                      <button disabled={busy || r.is_absent} onClick={() => void saveActuals(r.child_id)}
                        className="rounded-lg bg-emerald-600 px-3 py-1 text-xs font-semibold text-white hover:bg-emerald-700 disabled:opacity-40">保存</button>
                      <button onClick={() => void openAudit(r.child_id, r.child_name)}
                        className="rounded-lg border border-slate-300 px-2 py-1 text-xs font-medium text-slate-600 hover:bg-slate-50">履歴</button>
                    </div>
                  </td>
                  <td className="px-2 py-2">
                    {/* 備考(小さめ・主任以上)。フォーカスアウトで自動保存。 */}
                    <input type="text" value={e.note} placeholder="備考" onChange={(ev) => set("note", ev.target.value)}
                      onBlur={() => void saveNote(r.child_id, e.note)}
                      className="w-36 rounded border border-slate-300 px-2 py-1 text-xs" />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    );
  }

  // 月間グリッド(出欠 ◯/欠 または 時刻 登降園)。園児×日。
  function MonthGridView({ withTime }: { withTime: boolean }) {
    const daysInMonth = new Date(year, month, 0).getDate();
    const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);
    const byChild = new Map<string, { name: string; cls: string | null; days: Map<number, Row> }>();
    for (const r of rows) {
      const d = new Date(r.business_date).getDate();
      if (!byChild.has(r.child_id)) byChild.set(r.child_id, { name: r.child_name, cls: r.class_name, days: new Map() });
      byChild.get(r.child_id)!.days.set(d, r);
    }
    const children = [...byChild.entries()];
    const dowColor = (d: number) => {
      const g = new Date(year, month - 1, d).getDay();
      return g === 0 ? "text-red-500" : g === 6 ? "text-sky-500" : "text-slate-400";
    };
    return (
      <div className="space-y-2">
      {openDays !== null && (
        <div className="flex items-center gap-3 text-sm">
          <span className="rounded-lg bg-emerald-50 px-3 py-1 font-semibold text-emerald-700">開所日数 {openDays}日</span>
          <span className="text-xs text-slate-400">網掛け=休園日(日曜/祝日/年末年始、土曜はマハロステーション・ハレレアのみ)。稼働曜日で自動判定。</span>
        </div>
      )}
      <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-slate-200">
              <th className="sticky left-0 z-10 bg-white px-2 py-2 text-left text-slate-500">園児</th>
              {days.map((d) => (
                <th key={d} className={`px-0.5 py-2 text-center font-semibold ${dowColor(d)} ${closures[d] ? "bg-slate-200" : ""}`} style={{ minWidth: MONTH_COL_WIDTH }}
                    title={closures[d]?.label ?? undefined}>
                  <div>{d}</div>
                  <div className="text-[10px] font-normal">{WEEKDAYS[new Date(year, month - 1, d).getDay()]}</div>
                </th>
              ))}
              <th className="border-l border-slate-200 bg-slate-50 px-2 py-2 text-center font-semibold text-slate-500">出席</th>
              <th className="bg-slate-50 px-2 py-2 text-center font-semibold text-slate-500">病欠</th>
              <th className="bg-slate-50 px-2 py-2 text-center font-semibold text-slate-500">都合欠</th>
            </tr>
          </thead>
          <tbody>
            {children.length === 0 && <tr><td colSpan={daysInMonth + 4} className="px-3 py-6 text-center text-slate-400">この月の記録はありません</td></tr>}
            {children.map(([cid, c]) => {
              // 右端の集計(出席=登降園あり / 病欠 / 都合欠)。
              let cP = 0, cS = 0, cPe = 0;
              c.days.forEach((r) => {
                if (r.is_absent) { if (r.absence_kind === "sick_absence") cS++; else if (r.absence_kind === "personal_absence") cPe++; }
                else if (r.in_time || r.depart_time) cP++;
              });
              return (
              <tr key={cid} className="border-b border-slate-100 hover:bg-slate-50">
                <td className="sticky left-0 z-10 bg-white px-2 py-1.5 font-medium text-slate-700 whitespace-nowrap">
                  {c.name}<span className="ml-1 text-slate-400">{c.cls ?? ""}</span>
                </td>
                {days.map((d) => {
                  const shut = closures[d] ? "bg-slate-100" : "";
                  const r = c.days.get(d);
                  if (!r) return <td key={d} className={`px-0.5 py-1.5 text-center text-slate-200 ${shut}`}>·</td>;
                  const anoms = anomByKey.get(anomKey(r.child_id, r.business_date)) ?? [];
                  const miss = anoms.length > 0;
                  if (r.is_absent) {
                    const sym = registerSymbol(r);
                    return <td key={d} className={`px-0.5 py-1.5 text-center font-bold text-slate-400 ${shut}`} title={r.absence_reason ?? "欠席"}>{sym}</td>;
                  }
                  if (withTime) {
                    return (
                      <td key={d} onClick={miss ? () => jumpToDayEdit(r.business_date) : undefined}
                        className={`px-0.5 py-1 text-center tabular-nums leading-tight ${miss ? "cursor-pointer bg-red-50 hover:bg-red-100" : shut}`}
                        title={miss ? `要確認: ${anoms.join(" / ")}(クリックで修正)` : undefined}>
                        <div className={miss && !r.in_time ? "text-red-600 font-bold" : "text-slate-700"}>{hhmm(r.in_time) || "—"}</div>
                        <div className={miss && !r.depart_time ? "text-red-600 font-bold" : "text-slate-400"}>{hhmm(r.depart_time) || "—"}</div>
                      </td>
                    );
                  }
                  return (
                    <td key={d} onClick={miss ? () => jumpToDayEdit(r.business_date) : undefined}
                      className={`px-0.5 py-1.5 text-center ${miss ? "cursor-pointer bg-red-100 font-bold text-red-600 hover:bg-red-200" : `text-emerald-600 ${shut}`}`}
                      title={miss ? `要確認: ${anoms.join(" / ")}(クリックで修正)` : `${hhmm(r.in_time) || "—"} 〜 ${hhmm(r.depart_time) || "—"}`}>
                      {miss ? "!" : "◯"}
                    </td>
                  );
                })}
                <td className="border-l border-slate-200 bg-slate-50/60 px-2 py-1.5 text-center font-semibold tabular-nums text-emerald-700">{cP}</td>
                <td className="bg-slate-50/60 px-2 py-1.5 text-center font-semibold tabular-nums text-slate-600">{cS}</td>
                <td className="bg-slate-50/60 px-2 py-1.5 text-center font-semibold tabular-nums text-slate-600">{cPe}</td>
              </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      </div>
    );
  }

  // 園児単位の1ヶ月一覧(1名を選び、日ごとに 出欠・登降園時刻・備考を縦に表示)。
  function ChildMonthView() {
    const daysInMonth = new Date(year, month, 0).getDate();
    // 園児一覧(RPCの年齢/氏名順を保持)。
    const seen = new Set<string>();
    const children: { id: string; name: string; cls: string | null }[] = [];
    for (const r of rows) {
      if (!seen.has(r.child_id)) { seen.add(r.child_id); children.push({ id: r.child_id, name: r.child_name, cls: r.class_name }); }
    }
    const cid = selectedChild && children.some((c) => c.id === selectedChild) ? selectedChild : children[0]?.id ?? "";
    const byDay = new Map<number, Row>();
    for (const r of rows) if (r.child_id === cid) byDay.set(new Date(r.business_date).getDate(), r);
    const dateStr = (d: number) => `${year}-${String(month).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
    return (
      <div className="space-y-3">
        <div className="flex items-center gap-2">
          <span className="text-sm font-semibold text-slate-600">園児:</span>
          <select value={cid} onChange={(e) => setSelectedChild(e.target.value)}
            className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm">
            {children.length === 0 && <option value="">(在籍児なし)</option>}
            {children.map((c) => <option key={c.id} value={c.id}>{c.name}（{c.cls ?? "—"}）</option>)}
          </select>
        </div>
        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-left text-xs font-semibold text-slate-500">
                <th className="px-3 py-2">日</th><th className="px-3 py-2">曜</th><th className="px-3 py-2">出欠</th>
                <th className="px-3 py-2">登園</th><th className="px-3 py-2">外出</th><th className="px-3 py-2">戻り</th><th className="px-3 py-2">降園</th>
                <th className="px-3 py-2">備考</th>
              </tr>
            </thead>
            <tbody>
              {Array.from({ length: daysInMonth }, (_, i) => i + 1).map((d) => {
                const r = byDay.get(d);
                const g = new Date(year, month - 1, d).getDay();
                const anoms = anomByKey.get(anomKey(cid, dateStr(d))) ?? [];
                const miss = anoms.length > 0;
                return (
                  <tr key={d} className={`border-b border-slate-100 ${miss ? "bg-red-50" : g === 0 ? "bg-red-50/30" : g === 6 ? "bg-sky-50/40" : ""}`}>
                    <td className="px-3 py-1.5 tabular-nums text-slate-700">{d}</td>
                    <td className={`px-3 py-1.5 ${g === 0 ? "text-red-500" : g === 6 ? "text-sky-500" : "text-slate-400"}`}>{WEEKDAYS[g]}</td>
                    <td className="px-3 py-1.5">
                      {/* 出欠プルダウン(出席/病欠/都合欠)。過去日・未来日とも編集可(欠席理由の登録・修正)。 */}
                      <select value={kindValue(r)} onChange={(ev) => void saveAbsenceKind(cid, dateStr(d), ev.target.value)}
                        className={`rounded border px-1.5 py-0.5 text-xs ${
                          r?.is_absent ? "border-red-300 bg-red-50 text-red-700"
                            : r && (r.in_time || r.depart_time) ? "border-emerald-200 text-emerald-700"
                            : "border-slate-200 text-slate-400"}`}>
                        {kindValue(r) === "" && <option value="">欠席</option>}
                        {ABSENCE_OPTIONS.map((o) => <option key={o.v} value={o.v}>{o.l}</option>)}
                      </select>
                    </td>
                    {/* 要確認の日は時刻セルをクリックすると日別(修正)へ移動して登降園時刻を登録/修正できる。 */}
                    <td onClick={miss ? () => jumpToDayEdit(dateStr(d)) : undefined}
                      className={`px-3 py-1.5 tabular-nums ${miss ? "cursor-pointer text-red-600 font-semibold hover:underline" : ""}`}
                      title={miss ? "クリックで修正" : undefined}>
                      {r ? (hhmm(r.in_time) || (miss ? "要修正" : "")) : ""}
                    </td>
                    <td className="px-3 py-1.5 tabular-nums text-slate-500">{r ? (hhmm(r.out_time) || "") : ""}</td>
                    <td className="px-3 py-1.5 tabular-nums text-slate-500">{r ? (hhmm(r.return_time) || "") : ""}</td>
                    <td onClick={miss ? () => jumpToDayEdit(dateStr(d)) : undefined}
                      className={`px-3 py-1.5 tabular-nums ${miss ? "cursor-pointer text-red-600 font-semibold hover:underline" : ""}`}
                      title={miss ? "クリックで修正" : undefined}>
                      {r ? (hhmm(r.depart_time) || (miss ? "要修正" : "")) : ""}
                    </td>
                    <td className="px-3 py-1.5 text-xs text-slate-600">{r?.note ?? ""}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    );
  }
}

export default function ChildcareAttendancePage() {
  return (
    <Suspense fallback={<div className="p-8 text-sm text-slate-500">読み込み中…</div>}>
      <AttendanceContent />
    </Suspense>
  );
}
