"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

// 指導計画の印刷/PDFビュー(紙提出用)。余白最小・行を詰めたコンパクトなレイアウト。
// ブラウザの「印刷 → PDFに保存」でPDF化。app shell(ヘッダー/ナビ)は出さない。

type Field = { key: string; label: string; required?: boolean; subject?: string };
type Section = { key: string; label: string; fields: Field[] };
type Detail = {
  plan: { office_id: string; class_id: string | null; plan_type: string; fiscal_year: number; month: number | null; week_start_date: string | null; content: Record<string, string>; evaluation: Record<string, string>; status: string };
  template: { title: string; sections: Section[] };
  individual: { child_id: string; child_name: string; content: Record<string, string> }[];
};
const isReflection = (s: string, f: string) => s === "reflection" || f === "reflection";
// 教育系(3視点/5領域): fields が ねらい/内容/内容の取り扱い の並びなら横テーブルにまとめる。
const EDU_SUB = ["aim", "content"];

function PrintContent() {
  const sp = useSearchParams();
  const id = sp.get("id");
  const [d, setD] = useState<Detail | null>(null);
  const [officeName, setOfficeName] = useState("");
  const [className, setClassName] = useState("");
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!id) return;
    void (async () => {
      const s = createClient();
      const { data, error } = await s.rpc("fetch_guidance_plan", { p_id: id });
      if (error) { setErr(error.message); return; }
      const det = data as Detail;
      det.plan.content = det.plan.content ?? {};
      det.plan.evaluation = det.plan.evaluation ?? {};
      setD(det);
      const [{ data: offs }, { data: cls }] = await Promise.all([
        s.rpc("fetch_my_childcare_offices"),
        s.rpc("fetch_childcare_classes", { p_office_id: det.plan.office_id }),
      ]);
      setOfficeName((offs ?? []).find((o: Record<string, unknown>) => o.office_id === det.plan.office_id)?.office_name as string ?? "");
      if (det.plan.class_id) setClassName((cls ?? []).find((c: Record<string, unknown>) => c.class_id === det.plan.class_id)?.class_name as string ?? "");
    })();
  }, [id]);

  if (err) return <div style={{ padding: 20, color: "red" }}>{err}</div>;
  if (!d) return <div style={{ padding: 20 }}>読み込み中…</div>;

  const period = d.plan.month ? `${d.plan.month}月` : d.plan.week_start_date ? `${d.plan.week_start_date}の週` : "";
  const val = (sk: string, f: Field) => (isReflection(sk, f.key) ? d.plan.evaluation[f.key] : d.plan.content[f.key]) ?? "";
  const isEduSection = (sec: Section) => sec.fields.length >= 2 && sec.fields.every((f) => f.key.includes("*")) && EDU_SUB.some((v) => sec.fields.some((f) => f.key.endsWith("*" + v)));
  // 保育安全計画(こども家庭庁様式)は専用レイアウトで出力(重要事項説明書添付・保育室掲示に耐える体裁)。
  const isSafety = d.plan.plan_type === "safety";
  const c = (k: string) => d.plan.content[k] ?? "";

  return (
    <div className="sheet">
      <style>{`
        * { box-sizing: border-box; }
        body { margin: 0; }
        .sheet { font-family: "Hiragino Kaku Gothic ProN","Noto Sans JP",sans-serif; color:#111; font-size:11px; line-height:1.35; padding:10px 12px; }
        .toolbar { margin-bottom:8px; }
        .btn { font:inherit; font-size:12px; padding:5px 12px; border:1px solid #2f8f7a; background:#2f8f7a; color:#fff; border-radius:6px; cursor:pointer; }
        h1 { font-size:15px; margin:0 0 4px; }
        .head { display:flex; flex-wrap:wrap; gap:2px 16px; font-size:11px; margin-bottom:6px; border-bottom:1px solid #333; padding-bottom:4px; }
        .head b { font-weight:700; }
        table { border-collapse:collapse; width:100%; margin-bottom:6px; }
        th,td { border:1px solid #999; padding:2px 5px; vertical-align:top; text-align:left; }
        th { background:#eef2f0; font-weight:700; white-space:nowrap; }
        .sec-title { background:#e3efeb; font-weight:700; padding:3px 5px; border:1px solid #999; border-bottom:none; }
        .val { white-space:pre-wrap; min-height:1.2em; }
        .lbl { width:120px; background:#f6f8f7; font-weight:600; white-space:nowrap; }
        @media print {
          @page { size: A4; margin: 8mm; }
          .toolbar { display:none; }
          .sheet { padding:0; font-size:10px; }
          table, tr, td, th { page-break-inside: avoid; }
        }
      `}</style>
      <div className="toolbar">
        <button className="btn" onClick={() => window.print()}>印刷 / PDFに保存</button>
      </div>
      <h1>{d.template.title}</h1>
      <div className="head">
        <span><b>施設:</b> {officeName || "—"}</span>
        {className && <span><b>クラス:</b> {className}</span>}
        <span><b>年度:</b> {d.plan.fiscal_year}年度</span>
        {period && <span><b>{period}</b></span>}
        <span><b>担当</b>　<b>主任</b>　<b>園長</b></span>
      </div>

      {isSafety && <SafetyLayout c={c} />}

      {!isSafety && d.template.sections.map((sec) => {
        if (isEduSection(sec)) {
          // 教育系: 領域名を左、ねらい/内容/内容の取り扱いを列に。
          const subs = ["aim", "content", "$内容の取り扱い$", "envicomp", "expected", "aid"].filter((v) => sec.fields.some((f) => f.key.endsWith("*" + v)));
          const subLabel = (v: string) => sec.fields.find((f) => f.key.endsWith("*" + v))?.label ?? v;
          return (
            <table key={sec.key}>
              <thead><tr><th style={{ width: 110 }}>{sec.label}</th>{subs.map((v) => <th key={v}>{subLabel(v)}</th>)}</tr></thead>
              <tbody><tr>
                <td style={{ background: "#f6f8f7", fontWeight: 600 }}></td>
                {subs.map((v) => { const f = sec.fields.find((x) => x.key.endsWith("*" + v))!; return <td key={v} className="val">{val(sec.key, f)}</td>; })}
              </tr></tbody>
            </table>
          );
        }
        return (
          <div key={sec.key}>
            <div className="sec-title">{sec.label}</div>
            <table style={{ marginTop: 0 }}>
              <tbody>
                {sec.fields.map((f) => (
                  <tr key={f.key}><td className="lbl">{f.label}</td><td className="val">{val(sec.key, f)}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        );
      })}

      {d.individual.length > 0 && (
        <>
          <div className="sec-title">個人案</div>
          <table style={{ marginTop: 0 }}>
            <thead><tr><th style={{ width: 90 }}>園児</th><th>子どもの姿</th><th>ねらい</th><th>配慮・環境構成</th><th>評価・反省</th></tr></thead>
            <tbody>
              {d.individual.map((e) => (
                <tr key={e.child_id}>
                  <td style={{ fontWeight: 600 }}>{e.child_name}</td>
                  <td className="val">{e.content.kidsstate ?? ""}</td>
                  <td className="val">{e.content.aim ?? ""}</td>
                  <td className="val">{e.content.consideration ?? ""}</td>
                  <td className="val">{e.content.reflection ?? ""}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </div>
  );
}

// 保育安全計画の様式準拠レイアウト(こども家庭庁様式)。content を key で読み出して各表に配置。
const H1 = [4, 5, 6, 7, 8, 9];
const H2 = [10, 11, 12, 1, 2, 3];
const MANUAL_ROWS: { label: string; k: string; sub?: boolean }[] = [
  { label: "重大事故防止マニュアル", k: "daijiko" },
  { label: "　└ 午睡", k: "m_nap", sub: true },
  { label: "　└ 食事", k: "m_meal", sub: true },
  { label: "　└ プール・水遊び", k: "m_pool", sub: true },
  { label: "　└ 園外活動", k: "m_outdoor", sub: true },
  { label: "　└ バス送迎(実施時)", k: "m_bus", sub: true },
  { label: "　└ 降雪(必要時)", k: "m_snow", sub: true },
  { label: "災害時マニュアル", k: "saigai" },
  { label: "119番対応時マニュアル", k: "t119" },
  { label: "救急対応時マニュアル", k: "kyukyu" },
  { label: "不審者対応時マニュアル", k: "fushinsha" },
];
const TERMS: { k: string; label: string }[] = [
  { k: "term1", label: "4〜6月" }, { k: "term2", label: "7〜9月" }, { k: "term3", label: "10〜12月" }, { k: "term4", label: "1〜3月" },
];

function SafetyLayout({ c }: { c: (k: string) => string }) {
  const monthGrid = (prefix: string, months: number[]) => (
    <table>
      <thead><tr><th style={{ width: 90 }}>月</th>{months.map((m) => <th key={m} style={{ textAlign: "center" }}>{m}月</th>)}</tr></thead>
      <tbody><tr>
        <td className="lbl">重点点検箇所</td>
        {months.map((m) => <td key={m} className="val">{c(`${prefix}${m}`)}</td>)}
      </tr></tbody>
    </table>
  );
  const drillGrid = (months: number[]) => (
    <table>
      <thead><tr><th style={{ width: 90 }}>月</th>{months.map((m) => <th key={m} style={{ textAlign: "center" }}>{m}月</th>)}</tr></thead>
      <tbody>
        <tr><td className="lbl">避難訓練等</td>{months.map((m) => <td key={m} className="val">{c(`hinan_m${m}`)}</td>)}</tr>
        <tr><td className="lbl">その他</td>{months.map((m) => <td key={m} className="val">{c(`other_m${m}`)}</td>)}</tr>
      </tbody>
    </table>
  );
  return (
    <>
      <div className="sec-title">◎安全点検</div>
      <div style={{ fontWeight: 700, margin: "4px 0 2px" }}>(1) 施設・設備・園外環境(散歩コースや緊急避難先等)の安全点検</div>
      {monthGrid("inspect_m", H1)}
      {monthGrid("inspect_m", H2)}
      <div style={{ fontWeight: 700, margin: "6px 0 2px" }}>(2) マニュアルの策定・共有</div>
      <table>
        <thead><tr><th style={{ width: 200 }}>分野</th><th>策定時期</th><th>見直し(再点検)予定時期</th><th>掲示・管理場所</th></tr></thead>
        <tbody>
          {MANUAL_ROWS.map((r) => (
            <tr key={r.k}>
              <td className={r.sub ? "val" : "lbl"} style={{ whiteSpace: "nowrap" }}>
                {r.label}{r.sub && c(`${r.k}_check`) ? `（${c(`${r.k}_check`)}）` : ""}
              </td>
              <td className="val">{c(`${r.k}_estab`)}</td>
              <td className="val">{c(`${r.k}_review`)}</td>
              <td className="val">{c(`${r.k}_place`)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="sec-title">◎児童・保護者に対する安全指導等</div>
      <div style={{ fontWeight: 700, margin: "4px 0 2px" }}>(1) 児童への安全指導(生活における安全・災害/事故発生時の対応・交通安全等)</div>
      <table>
        <thead><tr><th style={{ width: 160 }}></th>{TERMS.map((t) => <th key={t.k}>{t.label}</th>)}</tr></thead>
        <tbody>
          <tr><td className="lbl">乳児・1歳以上3歳未満児</td>{TERMS.map((t) => <td key={t.k} className="val">{c(`infant_${t.k}`)}</td>)}</tr>
          <tr><td className="lbl">3歳以上児</td>{TERMS.map((t) => <td key={t.k} className="val">{c(`over3_${t.k}`)}</td>)}</tr>
        </tbody>
      </table>
      <div style={{ fontWeight: 700, margin: "6px 0 2px" }}>(2) 保護者への説明・共有</div>
      <table>
        <thead><tr>{TERMS.map((t) => <th key={t.k}>{t.label}</th>)}</tr></thead>
        <tbody><tr>{TERMS.map((t) => <td key={t.k} className="val">{c(`guardian_${t.k}`)}</td>)}</tr></tbody>
      </table>

      <div className="sec-title">◎訓練・研修</div>
      <div style={{ fontWeight: 700, margin: "4px 0 2px" }}>(1) 訓練のテーマ・取組</div>
      {drillGrid(H1)}
      {drillGrid(H2)}
      <div style={{ fontSize: 9, color: "#555", margin: "2px 0 4px" }}>
        ※避難訓練等=毎月1回以上の避難・消火訓練 / その他=119番通報・救急対応・不審者対応・送迎バス見落とし等
      </div>
      <div style={{ fontWeight: 700, margin: "6px 0 2px" }}>(2) 訓練の参加予定者(全員参加を除く)</div>
      <table>
        <thead><tr><th>訓練内容</th><th style={{ width: "45%" }}>参加予定者</th></tr></thead>
        <tbody>
          {[1, 2, 3, 4, 5].map((i) => (
            <tr key={i}><td className="val">{c(`drill${i}_content`)}</td><td className="val">{c(`drill${i}_who`)}</td></tr>
          ))}
        </tbody>
      </table>
      <div style={{ fontWeight: 700, margin: "6px 0 2px" }}>(3) 職員への研修・講習(園内実施・外部実施を明記)</div>
      <table>
        <thead><tr>{TERMS.map((t) => <th key={t.k}>{t.label}</th>)}</tr></thead>
        <tbody><tr>{TERMS.map((t) => <td key={t.k} className="val">{c(`staff_${t.k}`)}</td>)}</tr></tbody>
      </table>
      <div style={{ fontWeight: 700, margin: "6px 0 2px" }}>(4) 行政等が実施する訓練・講習スケジュール</div>
      <table><tbody><tr><td className="val" style={{ minHeight: "3em" }}>{c("admin_schedule")}</td></tr></tbody></table>

      <div className="sec-title">◎再発防止策の徹底(ヒヤリ・ハット事例の収集・分析及び対策とその共有)</div>
      <table><tbody><tr><td className="val" style={{ minHeight: "4em" }}>{c("prevention")}</td></tr></tbody></table>

      <div className="sec-title">◎その他の安全確保に向けた取組(地域連携・登降園管理システムの活用等)</div>
      <table><tbody><tr><td className="val" style={{ minHeight: "4em" }}>{c("other")}</td></tr></tbody></table>
    </>
  );
}

export default function GuidancePlanPrintPage() {
  return <Suspense fallback={<div style={{ padding: 20 }}>読み込み中…</div>}><PrintContent /></Suspense>;
}
