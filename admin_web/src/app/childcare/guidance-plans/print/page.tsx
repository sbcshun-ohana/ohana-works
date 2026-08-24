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

      {d.template.sections.map((sec) => {
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

export default function GuidancePlanPrintPage() {
  return <Suspense fallback={<div style={{ padding: 20 }}>読み込み中…</div>}><PrintContent /></Suspense>;
}
