// §11 AI連絡帳作成(共通AI基盤の最小版)
//
// クラス活動+園児個別メモから保護者向け連絡帳文章を生成し、同じ入力から
// 職員向け個人日誌(§16)も同時生成する。外部送信データはfetch_ai_allowed_context()
// (allowlist方式)で取得したものに限定する。
//
// 現時点ではANTHROPIC_API_KEY未登録のため、callAI()はモック実装(mockGenerate)を返す。
// 事前準備(実施時): `supabase secrets set ANTHROPIC_API_KEY=<APIキー>`
// 差し替え方法: callAI()内の「ここから下」のTODOをAnthropic Messages APIの実呼び出しに置き換えるだけでよい。

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const VALID_ACTIONS = [
  "generate",
  "shorten",
  "lengthen",
  "soften",
  "add_care",
  "clarify",
  "regenerate",
  "admin_revise",
] as const;
type Action = typeof VALID_ACTIONS[number];

type JournalSections = {
  fact: string;
  support: string;
  reaction: string;
  progress: string;
  consideration: string;
  handover: string;
};

type AIResult = {
  contact_text: string;
  journal_sections: JournalSections | null;
};

// §7.3 AI安全ルール。システムプロンプトの固定部分としてすべての呼び出しに含める。
const SAFETY_RULES = `
- 入力されていない出来事を追加しない
- 過去の出来事を当日の出来事として書かない
- 他の園児との比較をしない
- 病気・発達についての断定的な表現をしない
- 数値・日時・症状等を改変しない
`.trim();

// §11 文章ルール
const STYLE_RULES = `
- 保護者の連絡内容に理解を示す
- 質問・相談には必ず返答する
- 必要事項は明確に伝える
- 気遣いのある言葉を選ぶ
- 明るく丁寧な文体にする
- 攻撃的・否定的な表現は避ける
`.trim();

function buildSystemPrompt(officeToneSettings: Record<string, unknown>): string {
  const toneNote = Object.keys(officeToneSettings ?? {}).length > 0
    ? `\n園の文体設定: ${JSON.stringify(officeToneSettings)}`
    : "";
  return [
    "あなたは保育園の連絡帳作成を支援するアシスタントです。",
    "以下のルールを厳守して、保護者向けの連絡帳本文を作成してください。",
    "【文章ルール】",
    STYLE_RULES,
    "【安全ルール】",
    SAFETY_RULES,
    toneNote,
  ].join("\n");
}

function buildUserPrompt(
  context: Record<string, unknown>,
  action: Action,
  currentText?: string,
  instruction?: string,
): string {
  return JSON.stringify({
    context,
    action,
    current_text: currentText ?? null,
    instruction: instruction ?? null,
  });
}

// --- AIプロバイダ呼び出しの唯一の差し替えポイント ---
// ANTHROPIC_API_KEY登録・実装後は、apiKeyが設定されている分岐の中身を
// 実際のAnthropic Messages API呼び出しに置き換える。
async function callAI(
  systemPrompt: string,
  userPrompt: string,
  action: Action,
  context: Record<string, unknown>,
  currentText?: string,
): Promise<AIResult> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return mockGenerate(action, context, currentText);
  }
  // TODO: ANTHROPIC_API_KEY登録後に実装する。
  // 例: https://api.anthropic.com/v1/messages へ systemPrompt/userPrompt を渡し、
  // contact_text/journal_sectionsを組み立てて返す。
  throw new Error("Anthropic API呼び出しは未実装です(現時点ではモックのみサポート)");
}

function mockGenerate(
  action: Action,
  context: Record<string, unknown>,
  currentText?: string,
): AIResult {
  const todayInput = (context.today_input ?? {}) as Record<string, unknown>;
  const classActivity = (todayInput.class_activity ?? {}) as Record<string, unknown>;
  const childContact = (todayInput.child_contact ?? {}) as Record<string, unknown>;
  const displayName = String(context.display_name ?? "");
  const honorific = String(context.honorific_suffix ?? "");
  const nameLabel = `${displayName}${honorific}`;

  if (action === "generate" || action === "regenerate") {
    const parts = [
      `${nameLabel}は今日、${classActivity.activity_content ?? "元気に過ごしました"}。`,
      childContact.child_today_notes
        ? `${String(childContact.child_today_notes)}とのことでした。`
        : "",
      childContact.guardian_message ? "ご連絡いただいた内容、承知いたしました。" : "",
      "また明日もよろしくお願いいたします。",
    ].filter(Boolean);

    return {
      contact_text: `【AI生成(モック)】${parts.join("")}`,
      journal_sections: {
        fact: String(classActivity.activity_content ?? ""),
        support: "適宜声かけ・見守りを行った。",
        reaction: String(childContact.child_today_notes ?? ""),
        progress: "特記事項なし。",
        consideration: "体調面に配慮しながら対応した。",
        handover: "特になし。",
      },
    };
  }

  const base = currentText ?? "";
  switch (action) {
    case "shorten":
      return {
        contact_text: `【AI修正(モック・短く)】${base.slice(0, Math.ceil(base.length / 2))}`,
        journal_sections: null,
      };
    case "lengthen":
      return {
        contact_text: `【AI修正(モック・詳しく)】${base} また、日中も落ち着いて過ごすことができました。`,
        journal_sections: null,
      };
    case "soften":
      return { contact_text: `【AI修正(モック・やわらかく)】${base}`, journal_sections: null };
    case "add_care":
      return {
        contact_text: `【AI修正(モック・気遣い追加)】${base} 季節の変わり目ですので、どうぞご自愛ください。`,
        journal_sections: null,
      };
    case "clarify":
      return { contact_text: `【AI修正(モック・重要事項明確化)】${base}`, journal_sections: null };
    case "admin_revise":
      return { contact_text: `【AI修正(モック・管理者指示反映)】${base}`, journal_sections: null };
    default:
      return { contact_text: base, journal_sections: null };
  }
}

Deno.serve(async (req) => {
  const headers = corsHeaders(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response("ok", { headers });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "認証情報がありません" }), {
        status: 401,
        headers,
      });
    }

    const body = await req.json();
    const childId = body.child_id as string | undefined;
    const businessDate = body.business_date as string | undefined;
    const action = body.action as Action | undefined;
    const currentText = body.current_text as string | undefined;
    const instruction = body.instruction as string | undefined;

    if (!childId || !businessDate || !action) {
      return new Response(
        JSON.stringify({ error: "child_id/business_date/actionが必要です" }),
        { status: 400, headers },
      );
    }
    if (!VALID_ACTIONS.includes(action)) {
      return new Response(JSON.stringify({ error: "不正なactionです" }), {
        status: 400,
        headers,
      });
    }
    if (action !== "generate" && action !== "regenerate" && !currentText) {
      return new Response(
        JSON.stringify({ error: "このactionにはcurrent_textが必要です" }),
        { status: 400, headers },
      );
    }
    if (action === "admin_revise" && !instruction) {
      return new Response(
        JSON.stringify({ error: "admin_reviseにはinstructionが必要です" }),
        { status: 400, headers },
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // fetch_ai_allowed_context()はSECURITY DEFINERで内部的にhas_childcare_office_access()を
    // チェックするため、呼び出し元のJWTをそのまま転送して権限判定させる(service roleは使わない)。
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userError } = await callerClient.auth.getUser();
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "認証に失敗しました" }), {
        status: 401,
        headers,
      });
    }

    const { data: context, error: contextError } = await callerClient.rpc(
      "fetch_ai_allowed_context",
      { p_child_id: childId, p_business_date: businessDate },
    );
    if (contextError) {
      return new Response(JSON.stringify({ error: contextError.message }), {
        status: 403,
        headers,
      });
    }

    const systemPrompt = buildSystemPrompt(
      (context?.office_tone_settings ?? {}) as Record<string, unknown>,
    );
    const userPrompt = buildUserPrompt(context, action, currentText, instruction);

    const result = await callAI(
      systemPrompt,
      userPrompt,
      action,
      context as Record<string, unknown>,
      currentText,
    );

    return new Response(
      JSON.stringify({
        contact_text: result.contact_text,
        journal_sections: result.journal_sections,
        context_used: context,
        mock: !Deno.env.get("ANTHROPIC_API_KEY"),
      }),
      { headers: { ...headers, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "連絡帳のAI生成に失敗しました" }),
      { status: 500, headers },
    );
  }
});
