// 献立管理 Phase 1: AI解析(取込ファイル → 構造化献立 menu_days の下書き生成)。
//
// 委託先/業者の献立Excel(またはPDF)を読み取り、日別×食種×区分の menu_days を生成する。
// ANTHROPIC_API_KEY 未設定時は「サンプル下書き(対象月の先頭数営業日)」を生成して流れを確認できる。
// キー設定後(`supabase secrets set ANTHROPIC_API_KEY=...`)は Anthropic で実解析する。
//
// 呼び出し: POST { import_id }  ※呼び出し元のJWTで権限判定(fetch_menu_import/upsert_menu_day が主任以上を要求)。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as XLSX from "https://esm.sh/xlsx@0.18.5";
import { corsHeaders } from "../_shared/cors.ts";

const FOOD_TYPES = ["regular_over3", "regular_under3", "weaning_late", "weaning_final", "allergy_removed"];
const MEAL_SLOTS = ["am_snack", "lunch", "pm_snack"];

type MenuDayDraft = {
  date: string; // YYYY-MM-DD
  food_type: string;
  removal_kind?: string | null;
  meal_slot: string;
  menu_text: string;
};

// --- サンプル下書き(キー未設定時) ---
function sampleDrafts(targetMonth: string): MenuDayDraft[] {
  // targetMonth = YYYY-MM-01。先頭から平日3日分を、以上児/未満児の昼食・おやつでサンプル生成。
  const [y, m] = targetMonth.split("-").map(Number);
  const drafts: MenuDayDraft[] = [];
  let count = 0;
  for (let d = 1; d <= 28 && count < 3; d++) {
    const date = new Date(Date.UTC(y, m - 1, d));
    const dow = date.getUTCDay();
    if (dow === 0 || dow === 6) continue; // 土日は除く
    count++;
    const ds = `${targetMonth.slice(0, 7)}-${String(d).padStart(2, "0")}`;
    for (const ft of ["regular_over3", "regular_under3"]) {
      drafts.push({ date: ds, food_type: ft, meal_slot: "am_snack", menu_text: "【AIサンプル】牛乳・ビスケット" });
      drafts.push({ date: ds, food_type: ft, meal_slot: "lunch", menu_text: "【AIサンプル】ごはん・味噌汁・鶏の照り焼き・お浸し" });
      drafts.push({ date: ds, food_type: ft, meal_slot: "pm_snack", menu_text: "【AIサンプル】麦茶・おにぎり" });
    }
  }
  return drafts;
}

// --- Anthropic 実解析(キー設定時) ---
async function analyzeWithAnthropic(apiKey: string, sheetsCsv: Record<string, string>, targetMonth: string, formatKind: string): Promise<MenuDayDraft[]> {
  const sheetsText = Object.entries(sheetsCsv)
    .map(([name, csv]) => `## シート: ${name}\n${csv.slice(0, 8000)}`)
    .join("\n\n");
  const system =
    "あなたは保育園の献立表を構造化するアシスタントです。委託先/業者のExcelを読み、" +
    "日別×食種×食事区分の献立を厳密なJSONで出力します。説明文は一切出力しないでください。";
  const user =
    `対象月=${targetMonth}。フォーマット種別=${formatKind}。\n` +
    `食種(food_type)は次のいずれか: regular_over3(以上児/通常), regular_under3(未満児/通常), weaning_late(離乳食後期), weaning_final(完了期), allergy_removed(除去食)。\n` +
    `区分(meal_slot)は: am_snack(午前おやつ), lunch(昼食), pm_snack(午後おやつ)。\n` +
    `除去食シートがある場合は food_type=allergy_removed とし removal_kind に卵/そば/ピーナッツ等を入れる。\n` +
    `シート名から食種を推定してください(以上児→regular_over3, 未満児→regular_under3, 離乳食後期→weaning_late, 完了期→weaning_final, ohana/通常→regular_over3+regular_under3)。\n` +
    `出力はJSONオブジェクト {"days": [{"date":"YYYY-MM-DD","food_type":"...","removal_kind":null,"meal_slot":"...","menu_text":"..."}, ...]} のみ。\n\n` +
    `--- 元データ ---\n${sheetsText}`;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 8000,
      system,
      messages: [{ role: "user", content: user }],
    }),
  });
  if (!res.ok) throw new Error(`Anthropic API error: ${res.status} ${await res.text()}`);
  const json = await res.json();
  const text = (json.content?.[0]?.text ?? "").trim();
  const cleaned = text.replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
  const parsed = JSON.parse(cleaned);
  const days = (parsed.days ?? []) as MenuDayDraft[];
  return days.filter((d) => FOOD_TYPES.includes(d.food_type) && MEAL_SLOTS.includes(d.meal_slot) && d.date);
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "認証情報がありません" }), { status: 401, headers });

    const body = await req.json();
    const importId = body.import_id as string | undefined;
    if (!importId) return new Response(JSON.stringify({ error: "import_idが必要です" }), { status: 400, headers });

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    // 呼び出し元JWTで権限判定させる(fetch_menu_import/upsert_menu_day 内で権限チェック)。
    const client = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });

    const { data: imps, error: impErr } = await client.rpc("fetch_menu_import", { p_id: importId });
    if (impErr) return new Response(JSON.stringify({ error: impErr.message }), { status: 403, headers });
    const imp = (imps ?? [])[0];
    if (!imp) return new Response(JSON.stringify({ error: "取込ファイルが見つかりません" }), { status: 404, headers });

    const targetMonth = String(imp.target_month); // YYYY-MM-01
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    let drafts: MenuDayDraft[] = [];
    let mock = true;

    if (apiKey && imp.format === "excel") {
      // 実解析: ファイルをダウンロードしてExcelを抽出 → Anthropic。
      const { data: file, error: dlErr } = await client.storage.from("meal-menus").download(imp.source_path);
      if (dlErr || !file) throw new Error(`ファイル取得に失敗: ${dlErr?.message ?? "unknown"}`);
      const buf = new Uint8Array(await file.arrayBuffer());
      const wb = XLSX.read(buf, { type: "array" });
      const sheetsCsv: Record<string, string> = {};
      for (const name of wb.SheetNames) sheetsCsv[name] = XLSX.utils.sheet_to_csv(wb.Sheets[name]);
      drafts = await analyzeWithAnthropic(apiKey, sheetsCsv, targetMonth, String(imp.format_kind ?? "other"));
      mock = false;
    } else {
      // キー未設定 or 非Excel: サンプル下書き。
      drafts = sampleDrafts(targetMonth);
    }

    // menu_days へ upsert(呼び出し元JWT=主任以上の権限)。
    let saved = 0;
    for (const d of drafts) {
      const { error: upErr } = await client.rpc("upsert_menu_day", {
        p_import_id: importId,
        p_menu_date: d.date,
        p_food_type: d.food_type,
        p_removal_kind: d.removal_kind ?? null,
        p_meal_slot: d.meal_slot,
        p_menu_text: d.menu_text,
        p_ingredients: null,
        p_nutrition: null,
        p_removal_note: null,
      });
      if (!upErr) saved++;
    }

    return new Response(
      JSON.stringify({ mock, saved, total: drafts.length }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "解析に失敗しました" }), {
      status: 500,
      headers,
    });
  }
});
