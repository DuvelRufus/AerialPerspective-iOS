import { createClient } from "npm:@supabase/supabase-js@2";

const authClient = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_ANON_KEY")!,
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface QA {
  domain: string;
  question: string;
  answerLabel: string;
}

interface Payload {
  scores: Record<string, number>;
  questionsWithAnswers: QA[];
  templateName?: string | null;
  domainLabels?: Record<string, string> | null;
}

const ALLOWED_DOMAINS = ["Team", "Process", "Product", "Tech", "Stakeholders", "Culture"];
const ALLOWED_RISK_LEVELS = ["risk", "note", "strong"];



Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
     // Kräver en inloggad, icke-anonym användare. Token verifieras mot
    // Auth-servern, inte bara avkodas, så skyddet hänger inte på
    // plattformens JWT-inställning.
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    const { data: userData, error: userError } = await authClient.auth.getUser(token);
    const user = userData?.user;
    if (userError || !user || user.is_anonymous) {
      console.error("generate-insights: unauthorized");
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      console.error("generate-insights error: ANTHROPIC_API_KEY is not configured");
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY is not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const body = (await req.json()) as Payload;
    const { scores, questionsWithAnswers, templateName, domainLabels } = body;

    if (!scores || !questionsWithAnswers) {
      return new Response(JSON.stringify({ error: "Missing scores or questionsWithAnswers" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const byDomain = new Map<string, QA[]>();
    for (const qa of questionsWithAnswers) {
      const list = byDomain.get(qa.domain) ?? [];
      list.push(qa);
      byDomain.set(qa.domain, list);
    }

    const scoresBlock = Object.entries(scores)
      .map(([d, s]) => `- ${d}: ${s}/100`)
      .join("\n");

    const qaBlock = Array.from(byDomain.entries())
      .map(([domain, list]) => {
        const items = list.map((qa) => `  - ${qa.question} → ${qa.answerLabel}`).join("\n");
        return `${domain}:\n${items}`;
      })
      .join("\n\n");

    // Mallkontext. Utelämnas helt för mjukvaruteam, då blir prompten
    // identisk med den gamla.
    const teamLine = templateName
      ? `Teamets verksamhet: ${templateName}. Anpassa språk och exempel efter den verksamheten, inte efter mjukvaruutveckling.\n`
      : "";
    const labelsLine =
      domainLabels && Object.keys(domainLabels).length > 0
        ? `Domänerna heter så här i den här verksamheten, använd gärna visningsnamnen i texterna:\n${
          Object.entries(domainLabels).map(([k, v]) => `- ${k} = ${v}`).join("\n")
        }\nFältet "domain" i JSON ska ändå vara exakt databasnyckeln.\n`
        : "";
    const contextBlock = teamLine + labelsLine;

    const prompt = `Du är en erfaren Product Owner-coach som analyserar ett projekt utifrån en självskattning.
${contextBlock}
Domän-poäng (0-100):
${scoresBlock}

Frågor och valda svar:
${qaBlock}

Generera 4–6 konkreta insikter ur ett Product Owner-perspektiv på svenska.
Rangordna efter brådska: börja med risker, sedan noteringar, sist styrkor.
Var direkt och rak. Undvik floskler.

Returnera ENDAST en giltig JSON-array, inget annat. Format:
[
  { "title": "Kort titel max 6 ord", "body": "2-3 meningar konkret.", "risk_level": "risk", "domain": "Tech", "suggested_action": "Kort imperativ åtgärd, max 12 ord." }
]

risk_level måste vara exakt en av: "risk", "note", "strong".
domain måste vara exakt en av: "Team", "Process", "Product", "Tech", "Stakeholders", "Culture" — den domän insikten främst gäller.
suggested_action: en kort konkret åtgärd på svenska i imperativ form, max 12 ord.`;

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-5-5",
        max_tokens: 1500,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error("generate-insights: Anthropic API error", res.status, errText);
      return new Response(
        JSON.stringify({ error: `Anthropic API error: ${errText}` }),
        {
          status: res.status === 429 || res.status === 402 ? res.status : 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const data = await res.json();
    console.log("generate-insights: stop_reason =", data?.stop_reason);
    const text: string = data?.content?.[0]?.text ?? "";
    console.log("raw model output:", text.slice(0, 200));

    const cleaned = text
      .replace(/^```json\s*/i, "")
      .replace(/^```\s*/i, "")
      .replace(/\s*```$/i, "")
      .trim();

    const start = cleaned.indexOf("[");
    const end = cleaned.lastIndexOf("]");
    const jsonStr = start !== -1 && end !== -1 ? cleaned.slice(start, end + 1) : cleaned;

    let insights;
    try {
      insights = JSON.parse(jsonStr);
    } catch (_e) {
      console.error("generate-insights: failed to parse model output as JSON:", text.slice(0, 200));
      return new Response(
        JSON.stringify({ error: "Failed to parse Claude response", raw: text }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const normalized = (Array.isArray(insights) ? insights : [insights]).map((item: unknown) => {
      if (typeof item === "string") {
        return { title: "Insikt", body: item, risk_level: "note", domain: null, suggested_action: null };
      }
      const obj = item as Record<string, unknown>;
      return {
        title: typeof obj.title === "string" ? obj.title : "Insikt",
        body: typeof obj.body === "string" ? obj.body : "",
        risk_level: ALLOWED_RISK_LEVELS.includes(obj.risk_level as string) ? obj.risk_level : "note",
        domain: ALLOWED_DOMAINS.includes(obj.domain as string) ? obj.domain : null,
        suggested_action:
          typeof obj.suggested_action === "string" && obj.suggested_action.trim() !== ""
            ? obj.suggested_action
            : null,
      };
    });

    return new Response(JSON.stringify({ insights: normalized }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("generate-insights error:", err instanceof Error ? err.message : String(err));
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});