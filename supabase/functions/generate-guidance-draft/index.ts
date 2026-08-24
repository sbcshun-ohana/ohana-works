// 指導計画 AI下書き生成: 計画のクラス・期間の「連絡帳(園→保護者)・クラス活動・家庭からの連絡・前回計画」
// を素材に、テンプレの各記入欄の下書き文をAIが生成する。職員が確認→採用/追記/スキップする前提。
//
// ANTHROPIC_API_KEY 未設定時は「サンプル下書き」を返して流れを確認できる(mock:true)。
// キー設定後(`supabase secrets set ANTHROPIC_API_KEY=...`)は Anthropic で実生成する。
//
// 呼び出し: POST { plan_id }  ※呼び出し元のJWTで権限判定(fetch_guidance_ai_source が施設職員を要求)。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

// 生成対象から除外するセクション/フィールド(行事予定・評価反省は日々の記録から生成しない)。
const SKIP_SECTION_KEYS = ["schedule", "reflection", "goal"];
const SKIP_FIELD_KEYS = ["reflection"];

type FieldDef = { key: string; label: string; subject?: string; hint?: string; sectionLabel: string };

// テンプレのセクション配列から、生成対象のフィールド定義を平坦化して取り出す。
function collectTargetFields(sections: unknown): FieldDef[] {
  const out: FieldDef[] = [];
  if (!Array.isArray(sections)) return out;
  for (const s of sections as Array<Record<string, unknown>>) {
    const sKey = String(s.key ?? "");
    if (SKIP_SECTION_KEYS.includes(sKey)) continue;
    const sLabel = String(s.label ?? "");
    const fields = Array.isArray(s.fields) ? (s.fields as Array<Record<string, unknown>>) : [];
    for (const f of fields) {
      const key = String(f.key ?? "");
      if (!key || SKIP_FIELD_KEYS.includes(key)) continue;
      out.push({
        key,
        label: String(f.label ?? ""),
        subject: f.subject ? String(f.subject) : undefined,
        hint: f.hint ? String(f.hint) : undefined,
        sectionLabel: sLabel,
      });
    }
  }
  return out;
}

type SrcRow = { business_date?: string; child?: string; text?: string };

function sourceText(src: Record<string, unknown>): string {
  const contacts = (src.contacts as SrcRow[]) ?? [];
  const activities = (src.activities as SrcRow[]) ?? [];
  const home = (src.home as SrcRow[]) ?? [];
  const lines: string[] = [];
  lines.push(`# 連絡帳(園→保護者・子どもの様子) ${contacts.length}件`);
  for (const r of contacts.slice(0, 200)) lines.push(`- ${r.business_date} ${r.child ?? ""}: ${r.text ?? ""}`);
  lines.push(`\n# クラス活動 ${activities.length}件`);
  for (const r of activities.slice(0, 120)) lines.push(`- ${r.business_date}: ${r.text ?? ""}`);
  lines.push(`\n# 家庭からの連絡 ${home.length}件`);
  for (const r of home.slice(0, 120)) lines.push(`- ${r.business_date} ${r.child ?? ""}: ${r.text ?? ""}`);
  const prev = src.previous_content;
  if (prev && typeof prev === "object") {
    lines.push(`\n# 前回の計画(参考)\n${JSON.stringify(prev).slice(0, 3000)}`);
  }
  return lines.join("\n");
}

// --- サンプル下書き(キー未設定時) ---
function sampleSections(fields: FieldDef[], src: Record<string, unknown>): Record<string, string> {
  const c = ((src.contacts as unknown[]) ?? []).length;
  const a = ((src.activities as unknown[]) ?? []).length;
  const out: Record<string, string> = {};
  for (const f of fields) {
    out[f.key] = `【AIサンプル】連絡帳${c}件・活動${a}件を基にした「${f.sectionLabel}${f.label ? "／" + f.label : ""}」の下書きです(ANTHROPIC_API_KEY設定後に実生成されます)。`;
  }
  return out;
}

// --- Anthropic 実生成(キー設定時) ---
async function generateWithAnthropic(
  apiKey: string,
  src: Record<string, unknown>,
  fields: FieldDef[],
): Promise<Record<string, string>> {
  const fieldList = fields
    .map((f) => `- key="${f.key}" 項目「${f.sectionLabel}${f.label ? " / " + f.label : ""}」${f.subject ? `(主語=${f.subject})` : ""}${f.hint ? ` 補足:${f.hint}` : ""}`)
    .join("\n");
  const system =
    "あなたは経験豊富な保育士の指導計画作成アシスタントです。園の連絡帳・クラス活動・家庭からの連絡など" +
    "実際の記録を根拠に、指導計画(月案・週案)の各記入欄の下書きを日本語で作成します。" +
    "事実を捏造せず、記録に表れた子どもの姿・活動をふまえて具体的に書きます。保育所保育指針の観点(養護と教育)を意識し、" +
    "各欄1〜3文程度、簡潔に。説明文やコードブロックは一切出力せず、JSONのみを返します。";
  const user =
    `対象=${src.class_name} / ${src.period}(${src.start_date}〜${src.end_date})。\n` +
    `次の各欄について、下書き文を作成してください。主語の指定(子ども/保育者)がある欄はそれに合わせます。\n\n` +
    `## 記入する欄(このkeyをそのままJSONのキーに使う)\n${fieldList}\n\n` +
    `## 出力形式(厳守)\n{"sections": {"<key>": "<下書き文>", ...}}\n\n` +
    `## 根拠にする実際の記録\n${sourceText(src)}`;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 4000,
      system,
      messages: [{ role: "user", content: user }],
    }),
  });
  if (!res.ok) throw new Error(`Anthropic API error: ${res.status} ${await res.text()}`);
  const json = await res.json();
  const text = (json.content?.[0]?.text ?? "").trim();
  const cleaned = text.replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
  const parsed = JSON.parse(cleaned);
  const sections = (parsed.sections ?? {}) as Record<string, string>;
  // テンプレに存在するkeyのみ通す。
  const allow = new Set(fields.map((f) => f.key));
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(sections)) if (allow.has(k) && typeof v === "string") out[k] = v;
  return out;
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "認証情報がありません" }), { status: 401, headers });

    const body = await req.json();
    const planId = body.plan_id as string | undefined;
    if (!planId) return new Response(JSON.stringify({ error: "plan_idが必要です" }), { status: 400, headers });

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    // 呼び出し元JWTで権限判定(fetch_guidance_ai_source 内で施設職員をチェック)。
    const client = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });

    const { data: src, error: srcErr } = await client.rpc("fetch_guidance_ai_source", { p_plan_id: planId });
    if (srcErr) return new Response(JSON.stringify({ error: srcErr.message }), { status: 403, headers });
    if (!src) return new Response(JSON.stringify({ error: "計画が見つかりません" }), { status: 404, headers });

    const source = src as Record<string, unknown>;
    const fields = collectTargetFields(source.template_sections);
    if (fields.length === 0) {
      return new Response(JSON.stringify({ error: "この計画には生成対象の欄がありません" }), { status: 400, headers });
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    let sections: Record<string, string>;
    let mock = true;
    if (apiKey) {
      sections = await generateWithAnthropic(apiKey, source, fields);
      mock = false;
    } else {
      sections = sampleSections(fields, source);
    }

    return new Response(
      JSON.stringify({
        mock,
        sections,
        source_counts: {
          contacts: ((source.contacts as unknown[]) ?? []).length,
          activities: ((source.activities as unknown[]) ?? []).length,
          home: ((source.home as unknown[]) ?? []).length,
        },
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e instanceof Error ? e.message : e) }), {
      status: 500,
      headers,
    });
  }
});
