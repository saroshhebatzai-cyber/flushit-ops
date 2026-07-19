// content-agent — Supabase Edge Function
// Generates content ideas per client with Claude and writes them to content_ideas.
// Actions:
//   POST {action:"drop"}                              — all clients with a brief (cron, idempotent per PKT day)
//   POST {action:"generate", client, pillar?, seed?}  — one client, on demand (hub Generate button)
// Auth: verify_jwt (anon key as Bearer) + x-agent-token matching the AGENT_TOKEN secret.
// Secrets to set: ANTHROPIC_API_KEY, AGENT_TOKEN. SUPABASE_* env is auto-provided.

import Anthropic from "npm:@anthropic-ai/sdk";
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-agent-token",
};

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });

const IDEA_SCHEMA = {
  type: "object",
  properties: {
    ideas: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string", description: "The hook — how the post opens or what it is, in the client's voice" },
          angle: { type: "string", description: "1-2 sentences: the specific take, moment, or structure that makes it work" },
          pillar: { type: "string", description: "Which of the client's pillars this belongs to" },
          format: { type: "string", description: "e.g. talking-head reel, carousel, phone vlog, photo dump, text post" },
          scheduled_for: {
            anyOf: [{ type: "string", format: "date" }, { type: "null" }],
            description: "YYYY-MM-DD to propose a calendar slot, or null for an undated idea",
          },
        },
        required: ["title", "angle", "pillar", "format", "scheduled_for"],
        additionalProperties: false,
      },
    },
  },
  required: ["ideas"],
  additionalProperties: false,
};

// Karachi is UTC+5 year-round.
function karachiToday(): string {
  return new Date(Date.now() + 5 * 3600_000).toISOString().slice(0, 10);
}

async function generateForClient(client: string, opts: { pillar?: string; seed?: string } = {}) {
  const { data: brief } = await db.from("content_briefs").select("*").eq("client", client).single();
  if (!brief) throw new Error(`no brief for ${client}`);

  const { data: history } = await db
    .from("content_ideas")
    .select("title,pillar,status")
    .eq("client", client)
    .order("created_at", { ascending: false })
    .limit(30);

  const today = karachiToday();
  const horizon = new Date(Date.now() + 19 * 24 * 3600_000).toISOString().slice(0, 10);
  const { data: calendar } = await db
    .from("content_ideas")
    .select("title,scheduled_for,status")
    .eq("client", client)
    .in("status", ["scheduled", "proposed"])
    .gte("scheduled_for", today)
    .lte("scheduled_for", horizon)
    .order("scheduled_for");

  const kept = (history ?? []).filter((i) => i.status !== "killed").map((i) => `- ${i.title} [${i.pillar}] (${i.status})`);
  const killed = (history ?? []).filter((i) => i.status === "killed").map((i) => `- ${i.title} [${i.pillar}]`);
  const slots = (calendar ?? []).map((i) => `- ${i.scheduled_for}: ${i.title} (${i.status})`);

  const response = await anthropic.messages.create({
    model: "claude-opus-4-8",
    max_tokens: 4096,
    output_config: { format: { type: "json_schema", schema: IDEA_SCHEMA } },
    system:
      "You are the content strategist for a video-production founder's clients. " +
      "Generate specific, shootable content ideas — concrete moments and hooks, not themes. " +
      "Match the client's brief and voice exactly. Learn from the history: lean toward what was " +
      "kept or scheduled, away from what was killed. Never repeat or closely rehash a previous idea.",
    messages: [
      {
        role: "user",
        content: `Client: ${client}
Positioning: ${brief.positioning || "(none)"}
Audience: ${brief.audience || "(none)"}
Pillars: ${JSON.stringify(brief.pillars)}
Tone: ${brief.tone || "(none)"}
Cadence: ${brief.cadence} posts/week
Notes: ${brief.notes || "(none)"}

Today (client timezone): ${today}
Calendar, next 3 weeks:
${slots.join("\n") || "(empty)"}

Recent ideas (kept/scheduled/banked):
${kept.join("\n") || "(none)"}

Killed ideas (avoid anything like these):
${killed.join("\n") || "(none)"}

${opts.pillar ? `Focus on the "${opts.pillar}" pillar.` : ""}
${opts.seed ? `Build around this seed from the founder: "${opts.seed}"` : ""}

Generate 5 new ideas. Given the ${brief.cadence}/week cadence, set scheduled_for on just enough
of them to fill empty days over the next 7 days (skip days that already have a slot); leave the
rest with scheduled_for null.`,
      },
    ],
  });

  const text = response.content.find((b) => b.type === "text");
  if (!text || response.stop_reason === "refusal") throw new Error(`generation failed (${response.stop_reason})`);
  const ideas = JSON.parse(text.text).ideas as Array<{
    title: string; angle: string; pillar: string; format: string; scheduled_for: string | null;
  }>;

  const rows = ideas.map((i) => ({
    id: `ci_${crypto.randomUUID().slice(0, 13)}`,
    client,
    title: i.title,
    angle: i.angle,
    pillar: i.pillar,
    format: i.format,
    status: "proposed",
    scheduled_for: i.scheduled_for,
    source: "agent",
  }));
  const { error } = await db.from("content_ideas").insert(rows);
  if (error) throw new Error(`insert failed: ${error.message}`);
  return rows;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.headers.get("x-agent-token") !== Deno.env.get("AGENT_TOKEN")) {
    return new Response(JSON.stringify({ error: "bad token" }), { status: 401, headers: CORS });
  }

  try {
    const body = await req.json();

    if (body.action === "generate") {
      const rows = await generateForClient(body.client, { pillar: body.pillar, seed: body.seed });
      return new Response(JSON.stringify({ ok: true, ideas: rows }), {
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    if (body.action === "drop") {
      const { data: briefs } = await db.from("content_briefs").select("client");
      const results: Record<string, string> = {};
      const todayStartUtc = new Date(`${karachiToday()}T00:00:00+05:00`).toISOString();
      for (const b of briefs ?? []) {
        const { count } = await db
          .from("content_ideas")
          .select("id", { count: "exact", head: true })
          .eq("client", b.client)
          .eq("source", "agent")
          .gte("created_at", todayStartUtc);
        if ((count ?? 0) > 0) { results[b.client] = "skipped (already dropped today)"; continue; }
        try {
          const rows = await generateForClient(b.client);
          results[b.client] = `${rows.length} ideas`;
        } catch (e) {
          results[b.client] = `error: ${(e as Error).message}`;
        }
      }
      return new Response(JSON.stringify({ ok: true, results }), {
        headers: { ...CORS, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "unknown action" }), { status: 400, headers: CORS });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { status: 500, headers: CORS });
  }
});
