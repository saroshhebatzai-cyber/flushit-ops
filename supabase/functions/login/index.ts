// supabase/functions/login/index.ts
// Trades a per-person access code for a real Supabase session.
// Codes + the shared auth password come from env secrets, never the client.
// SUPABASE_URL and SUPABASE_ANON_KEY are auto-injected by the platform.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let code = "";
  try {
    const body = await req.json();
    code = (body?.code ?? "").toString().trim().toLowerCase();
  } catch {
    code = "";
  }

  const codeMap = JSON.parse(Deno.env.get("CODE_MAP") ?? "{}");
  const memberId = codeMap[code];
  if (!memberId) return json({ error: "Code not recognised." }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
  );
  const { data, error } = await supabase.auth.signInWithPassword({
    email: Deno.env.get("APP_EMAIL")!,
    password: Deno.env.get("APP_PASSWORD")!,
  });
  if (error || !data.session) return json({ error: "Auth backend error." }, 500);

  return json({ session: data.session, memberId }, 200);
});
