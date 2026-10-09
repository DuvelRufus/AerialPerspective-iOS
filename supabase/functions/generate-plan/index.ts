
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

interface CurrentAction {
  key: string;
  phase: string;
  text: string;
  domain?: string | null;
}

interface Payload {
  scores: Record<string, number>;
  questionsWithAnswers: QA[];
  durationValue?: number | null;
  durationUnit?: "weeks" | "months" | "years" | null;
  currentActions?: CurrentAction[] | null;
  templateName?: string | null;
  domainLabels?: Record<string, string> | null;
}



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
      console.error("generate-plan: unauthorized");
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY is not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const body = (await req.json()) as Payload;
    const {
      scores,
      questionsWithAnswers,
      durationValue,
      durationUnit,
      currentActions,
      templateName,
      domainLabels,
    } = body;

    if (!scores || !questionsWithAnswers) {
      return new Response(
        JSON.stringify({ error: "Missing scores or questionsWithAnswers" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
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

    const unitSv =
      durationUnit === "weeks" ? "veckor" :
      durationUnit === "months" ? "månader" :
      durationUnit === "years" ? "år" : null;

    const durationLine =
      durationValue && unitSv
        ? `\nProjektets tidsram: ${durationValue} ${unitSv}. Strukturera planen efter detta.\n`
        : "";

    // Mallkontext. Utelämnas helt för mjukvaruteam, då blir prompten
    // identisk med den gamla.
    const teamLine = templateName
      ? `\nTeamets verksamhet: ${templateName}. Anpassa språk och exempel efter den verksamheten, inte efter mjukvaruutveckling.\n`
      : "";
    const labelsLine =
      domainLabels && Object.keys(domainLabels).length > 0
        ? `\nDomänerna heter så här i den här verksamheten, använd gärna visningsnamnen i texterna:\n${
          Object.entries(domainLabels).map(([k, v]) => `- ${k} = ${v}`).join("\n")
        }\nFältet "domain" i JSON ska ändå vara exakt databasnyckeln.\n`
        : "";
    const contextBlock = teamLine + labelsLine;

    const hasCurrent = Array.isArray(currentActions) && currentActions.length > 0;

    const currentBlock = hasCurrent
      ? `\nNUVARANDE PLAN (för kontinuitet):\n${currentActions!
          .map((a) => `  - [${a.key}] (${a.phase}) ${a.text}`)
          .join("\n")}\n`
      : "";

    const refInstruction = hasCurrent
      ? `
KONTINUITET MED NUVARANDE PLAN:
- Ovan listas den nuvarande planens handlingar, var och en med en nyckel som [a1].
- För varje handling du returnerar som i praktiken är SAMMA sak som en befintlig (även om du omformulerar den eller flyttar den till annan fas), sätt fältet "ref" till den befintliga nyckeln, t.ex. "ref": "a1".
- För helt nya handlingar: utelämna "ref" helt.
- Återanvänd varje nyckel högst en gång.
- Behåll det som fortfarande är relevant, byt bara ut det som självskattningen visar inte längre behövs.`
      : "";

    const actionShape = hasCurrent
      ? `{ "text": "...", "domain": "process", "ref": "a1" }  (ref bara på behållna, domain på alla)`
      : `{ "text": "...", "domain": "process" }`;

    const prompt = `Du är en erfaren Product Owner och Project Manager-coach. Baserat på en självskattning av ett projekt ska du ta fram en personlig 30-60-90-plan för en ny PO eller PL som tar över projektet.
${durationLine}${contextBlock}
Domän-poäng (0-100):
${scoresBlock}

Frågor och valda svar:
${qaBlock}
${currentBlock}
Instruktioner:
- Språk: svenska
- Ton: direkt, konkret, ur PO eller PL-perspektiv. Undvik floskler.
- Varje fas ska ha en fokus-rubrik (max 6 ord) och exakt 3 specifika handlingar.
- Håll varje handling koncis: max 2-3 meningar. Var konkret, inte utsvävande.
- Handlingarna måste vara grundade i de faktiska svaren ovan.
- Varje handling måste ha ett "domain"-fält satt till den domän den hör till (samma domännamn som i poängen ovan, t.ex. "process", "tech", "product").
- Lågt poängsatta domäner dominerar dag 1–30.
- Medelpoängsatta domäner hör hemma i dag 31–60.
- Styrkor erkänns i dag 61–90.
${refInstruction}

Returnera ENDAST ett giltigt JSON-objekt, ingen markdown. Format:
{
  "summary": "2-3 meningar om projektets nuläge",
  "day1_30": { "focus": "rubrik", "actions": [${actionShape}, ...] },
  "day31_60": { "focus": "rubrik", "actions": [...] },
  "day61_90": { "focus": "rubrik", "actions": [...] }
}`;

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-5-5",
        max_tokens: 4096,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!res.ok) {
      const text = await res.text();
      return new Response(
        JSON.stringify({ error: `Anthropic API error: ${text}` }),
        {
          status: res.status === 429 || res.status === 402 ? res.status : 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const data = await res.json();
    const text: string = data?.content?.[0]?.text ?? "";

    const cleaned = text
      .replace(/^```json\s*/i, "")
      .replace(/^```\s*/i, "")
      .replace(/\s*```$/i, "")
      .trim();

    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    const jsonStr = start !== -1 && end !== -1 ? cleaned.slice(start, end + 1) : cleaned;

    let plan;
    try {
      plan = JSON.parse(jsonStr);
    } catch (_e) {
      return new Response(
        JSON.stringify({ error: "Failed to parse Claude response", raw: text }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Normalize actions to objects with text (+ optional domain, ref).
    // No id minting here — the database generates plan_actions ids.
    for (const phaseKey of ["day1_30", "day31_60", "day61_90"]) {
      const phase = plan?.[phaseKey];
      if (phase && Array.isArray(phase.actions)) {
        phase.actions = phase.actions.map((a: unknown) =>
          typeof a === "string"
            ? { text: a }
            : (a as Record<string, unknown>),
        );
      }
    }

    return new Response(JSON.stringify({ plan }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});