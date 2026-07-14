# Server-Enforced Code Login + RLS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the open-database hole so the app can be hosted publicly — keep the single-field code login, but enforce it server-side with a Supabase Edge Function that mints real sessions, and re-enable RLS as authenticated-only.

**Architecture:** RLS is turned back on for all six tables with one policy: authenticated sessions get full access, anon gets nothing. A `login` Edge Function is the sole holder of the codes; the browser POSTs the typed code, the function signs in one shared auth user and returns the session. The client `setSession()`s it, so every DB/realtime request carries a JWT and passes RLS. Codes and the shared password never appear in the page source.

**Tech Stack:** Supabase (Postgres RLS, Auth, Edge Functions on Deno), vanilla JS single-file client (`@supabase/supabase-js@2` via CDN), no build step.

**No test framework exists** (single-file HTML). Verification is done with `curl` against live Supabase and the browser preview. Several tasks are **⚠️ MANUAL** — they run in the Supabase dashboard/CLI and must be done by the operator, not a subagent.

**Reference spec:** `docs/superpowers/specs/2026-07-15-code-login-server-auth-design.md`

---

## Environment values (fill once, reused below)

From `flushit-ops-hub.html`:
- `SUPABASE_URL` = `https://kdfwrjjbpfoweokofjdq.supabase.co`
- `SUPABASE_ANON_KEY` = the `SUPABASE_KEY` constant at [flushit-ops-hub.html:801](../../../flushit-ops-hub.html)

Code → member id map (from the current `TEAM[]` `code:` fields):
```json
{"bebatzai":1,"ayesha":3,"tanzeel":4,"osama":5,"arsal":7}
```

For the curl commands below, export these in your shell first:
```bash
export SB_URL="https://kdfwrjjbpfoweokofjdq.supabase.co"
export SB_ANON="<paste the SUPABASE_KEY value from flushit-ops-hub.html:801>"
```

---

## File Structure

- **Create** `docs/superpowers/sql/2026-07-15-enable-rls-authenticated.sql` — RLS migration (rerunnable). Supersedes `2026-07-13-code-login-rls.sql`.
- **Create** `supabase/functions/login/index.ts` — the Edge Function (no secrets inside; reads codes + shared password from env).
- **Modify** `flushit-ops-hub.html`:
  - `TEAM[]` lines 841–845 — remove the `code:` field from each entry.
  - Auth block ~3520–3577 — new constants, rewritten `doLogin`, `doLogout`, `init`.
- **Mirror** `index.html` — byte-identical copy of `flushit-ops-hub.html` (deploy mirror; `cp` + `cmp` before every commit that touches the HTML).

---

## Task 1: RLS migration SQL

**Files:**
- Create: `docs/superpowers/sql/2026-07-15-enable-rls-authenticated.sql`

- [ ] **Step 1: Write the migration file**

```sql
-- 2026-07-15-enable-rls-authenticated.sql
-- Re-enable Row Level Security on every app table. A single policy grants full
-- access to any authenticated session; the anon role gets no policy and is
-- therefore blocked from all rows. Supersedes 2026-07-13-code-login-rls.sql.
-- Rerunnable: drops the policy by name before recreating it.
-- Run in the Supabase dashboard SQL editor.

alter table projects enable row level security;
alter table videos   enable row level security;
alter table tasks    enable row level security;
alter table notes    enable row level security;
alter table leads    enable row level security;
alter table meta     enable row level security;

do $$
declare t text;
begin
  foreach t in array array['projects','videos','tasks','notes','leads','meta'] loop
    execute format('drop policy if exists "authenticated full access" on public.%I;', t);
    execute format('create policy "authenticated full access" on public.%I for all to authenticated using (true) with check (true);', t);
  end loop;
end $$;
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/sql/2026-07-15-enable-rls-authenticated.sql
git commit -m "feat(sql): RLS migration — authenticated-only access on all tables"
```

Note: this file is **not applied** until Task 7 (deliberately last, so nobody is locked out before logins can mint sessions).

---

## Task 2: The `login` Edge Function

**Files:**
- Create: `supabase/functions/login/index.ts`

- [ ] **Step 1: Write the function**

```ts
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
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/login/index.ts
git commit -m "feat(fn): login Edge Function — code -> Supabase session"
```

---

## Task 3: ⚠️ MANUAL — Supabase setup (operator, in dashboard/CLI)

No code. Do these in Supabase; they must exist before the client change is tested. **Do NOT run the RLS SQL yet** (that's Task 7).

- [ ] **Step 1: Create the shared auth user**

Dashboard → Authentication → Users → Add user → Create new user:
- Email: `app@flushit.internal`
- Password: generate a strong random string (e.g. `openssl rand -base64 24`) and save it.
- Tick "Auto Confirm User" so no email confirmation is needed.

- [ ] **Step 2: Deploy the function**

Option A — Supabase CLI (from repo root):
```bash
# one-time: npm i -g supabase   (or: brew install supabase/tap/supabase)
supabase login
supabase link --project-ref kdfwrjjbpfoweokofjdq
supabase functions deploy login
```
Option B — Dashboard → Edge Functions → Create a function named `login`, paste
`supabase/functions/login/index.ts`, Deploy.

- [ ] **Step 3: Set the function secrets**

CLI:
```bash
supabase secrets set \
  CODE_MAP='{"bebatzai":1,"ayesha":3,"tanzeel":4,"osama":5,"arsal":7}' \
  APP_EMAIL='app@flushit.internal' \
  APP_PASSWORD='<the password from Step 1>'
```
(Or Dashboard → Edge Functions → login → Secrets. Do **not** set `SUPABASE_URL`
or `SUPABASE_ANON_KEY` — the platform injects those and rejects the prefix.)

- [ ] **Step 4: Verify the function end-to-end (still pre-RLS)**

Bad code → 401:
```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$SB_URL/functions/v1/login" \
  -H "Content-Type: application/json" -H "apikey: $SB_ANON" -H "Authorization: Bearer $SB_ANON" \
  -d '{"code":"definitely-wrong"}'
```
Expected: `401`

Good code → 200 with a session:
```bash
curl -s -X POST "$SB_URL/functions/v1/login" \
  -H "Content-Type: application/json" -H "apikey: $SB_ANON" -H "Authorization: Bearer $SB_ANON" \
  -d '{"code":"bebatzai"}' | python3 -c "import sys,json;d=json.load(sys.stdin);print('memberId',d.get('memberId'),'| has access_token:', bool(d.get('session',{}).get('access_token')))"
```
Expected: `memberId 1 | has access_token: True`

Do not proceed to Task 7 until both pass.

---

## Task 4: Client — remove codes from TEAM

**Files:**
- Modify: `flushit-ops-hub.html:841-845`

- [ ] **Step 1: Delete the `code:` field from each of the 5 TEAM entries**

For each line 841–845, remove the `, isAdmin:…, code:'…'` code portion, keeping
`isAdmin`. Concretely, each entry ends `…isAdmin:true,  code:'bebatzai'}` →
becomes `…isAdmin:true}`. Do this for all five (`bebatzai`, `ayesha`, `tanzeel`,
`osama`, `arsal`). Codes now live only in the Edge Function.

- [ ] **Step 2: Verify no codes remain in the client**

Run:
```bash
grep -n "code:'" flushit-ops-hub.html || echo "no codes in client ✓"
```
Expected: `no codes in client ✓`

- [ ] **Step 3: Do NOT commit yet** — commit lands in Task 6 with the mirror.

---

## Task 5: Client — rewrite auth (constants, doLogin, doLogout, init)

**Files:**
- Modify: `flushit-ops-hub.html` auth block (currently ~3520–3577)

- [ ] **Step 1: Replace the storage-key constant and add login-URL + member-key**

Find:
```js
const CODE_STORAGE_KEY = 'flushit-access-code';
```
Replace with:
```js
const LOGIN_FN_URL = SUPABASE_URL + '/functions/v1/login';
const MEMBER_STORAGE_KEY = 'flushit-member-id';
```

- [ ] **Step 2: Rewrite `doLogin`**

Replace the whole `async function doLogin(){ … }` with:
```js
async function doLogin(){
  const code = document.getElementById('login-code').value.trim().toLowerCase();
  const errEl = document.getElementById('login-error');
  errEl.textContent = '';
  if(!code){ errEl.textContent = 'Please enter your access code.'; return; }
  let res;
  try {
    res = await fetch(LOGIN_FN_URL, {
      method: 'POST',
      headers: { 'Content-Type':'application/json', 'apikey': SUPABASE_KEY, 'Authorization': 'Bearer ' + SUPABASE_KEY },
      body: JSON.stringify({ code })
    });
  } catch(e){ errEl.textContent = 'Network error. Please try again.'; return; }
  if(res.status === 401){ errEl.textContent = 'Code not recognised. Contact ops.'; return; }
  if(!res.ok){ errEl.textContent = 'Login failed. Please try again.'; return; }
  const { session, memberId } = await res.json();
  const { error } = await db.auth.setSession({ access_token: session.access_token, refresh_token: session.refresh_token });
  if(error){ errEl.textContent = 'Session error. Please try again.'; return; }
  const member = TEAM.find(t => t.id === memberId);
  if(!member){ errEl.textContent = 'Unknown member. Contact ops.'; return; }
  localStorage.setItem(MEMBER_STORAGE_KEY, String(memberId));
  await onSignedIn(member);
}
```

- [ ] **Step 3: Rewrite `doLogout`**

Replace the whole `async function doLogout(){ … }` with:
```js
async function doLogout(){
  try { await db.auth.signOut(); } catch(e){ /* ignore */ }
  localStorage.removeItem(MEMBER_STORAGE_KEY);
  currentUser = null;
  document.getElementById('login-screen').classList.remove('hidden');
  document.getElementById('login-code').value = '';
  document.getElementById('login-error').textContent = '';
}
```

- [ ] **Step 4: Rewrite the session-resume block in `init`**

In `async function init(){ … }`, replace:
```js
  // check for a remembered access code
  const saved = (localStorage.getItem(CODE_STORAGE_KEY) || '').toLowerCase();
  const member = TEAM.find(t => t.code === saved);
  if(member){
    await onSignedIn(member);
  }
  // else login screen stays visible
```
with:
```js
  // resume a persisted Supabase session if present
  const { data:{ session } } = await db.auth.getSession();
  const savedId = parseInt(localStorage.getItem(MEMBER_STORAGE_KEY) || '', 10);
  const member = TEAM.find(t => t.id === savedId);
  if(session && member){
    await onSignedIn(member);
  }
  // else login screen stays visible
```

- [ ] **Step 5: Verify no stale references remain**

Run:
```bash
grep -n "CODE_STORAGE_KEY\|t.code\|m.code" flushit-ops-hub.html || echo "no stale code refs ✓"
```
Expected: `no stale code refs ✓`

- [ ] **Step 6: Do NOT commit yet** — commit lands in Task 6 with the mirror.

---

## Task 6: Mirror to index.html and commit the client change

**Files:**
- Mirror: `index.html`

- [ ] **Step 1: Copy and verify byte-identical**

```bash
cd /Users/saroshahmed/Desktop/flushit
cp flushit-ops-hub.html index.html
cmp flushit-ops-hub.html index.html && echo "identical ✓"
```
Expected: `identical ✓`

- [ ] **Step 2: Commit both**

```bash
git add flushit-ops-hub.html index.html
git commit -m "feat(v2): server-enforced code login — real Supabase sessions

Codes removed from client; login now posts to the login Edge Function,
setSession()s the returned session, and persists member id. Session resume
via db.auth.getSession(); real sign-out. Mirror index.html kept identical."
```

Note: at this point the client expects sessions but RLS is **not yet enabled**,
so the app still works against the (still-open) DB — this lets you test login
before flipping enforcement.

- [ ] **Step 3: Verify login works against live Supabase (pre-RLS)**

Serve the repo root locally and open it:
```bash
cd /Users/saroshahmed/Desktop/flushit
npx --yes serve -l 4173 .    # then open http://localhost:4173
```
In the browser: enter `bebatzai`, confirm you reach Today, reload the page and
confirm you stay signed in, then sign out and confirm you return to the code
screen. (If using the Claude preview tool, drive it there instead.)

---

## Task 7: ⚠️ MANUAL — Apply RLS, then verify enforcement

Now flip enforcement on. This is last so the client can already mint sessions.

- [ ] **Step 1: Run the RLS migration**

Dashboard → SQL editor → paste and run
`docs/superpowers/sql/2026-07-15-enable-rls-authenticated.sql`.

- [ ] **Step 2: Verify the anon key alone is now blocked**

```bash
curl -s "$SB_URL/rest/v1/leads?select=*&limit=1" \
  -H "apikey: $SB_ANON" -H "Authorization: Bearer $SB_ANON"
```
Expected: `[]` (empty — RLS filters all rows for anon). Before Task 7 this
returned lead rows; now it returns nothing. This is the proof the hole is closed.

- [ ] **Step 3: Verify an authenticated session still gets data**

Get a token from the function, then query with it:
```bash
TOKEN=$(curl -s -X POST "$SB_URL/functions/v1/login" \
  -H "Content-Type: application/json" -H "apikey: $SB_ANON" -H "Authorization: Bearer $SB_ANON" \
  -d '{"code":"bebatzai"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['session']['access_token'])")
curl -s "$SB_URL/rest/v1/leads?select=id&limit=1" \
  -H "apikey: $SB_ANON" -H "Authorization: Bearer $TOKEN"
```
Expected: a JSON array with data (e.g. `[{"id":...}]`) — authenticated policy works.

- [ ] **Step 4: Verify the live app end-to-end**

In the browser: hard-reload the app. Sign in with `bebatzai`. Confirm every tab
loads data, the "Live" realtime indicator connects, creating/editing a task
persists, reload keeps you signed in, and sign-out returns to the code screen.
If realtime does not connect, confirm `subscribeRealtime()` runs after
`setSession` (it does, via `onSignedIn`) and that Realtime is enabled for the
tables in the Supabase dashboard.

---

## Rollback

If anything breaks after Task 7:
```sql
alter table projects disable row level security;
alter table videos   disable row level security;
alter table tasks    disable row level security;
alter table notes    disable row level security;
alter table leads    disable row level security;
alter table meta     disable row level security;
```
and `git revert` the Task 6 commit. This instantly restores the prior behavior.

---

## After this plan

The database is closed to the public and the app can be hosted. Resume the
hosting step (Netlify/Vercel/Cloudflare — repo already prepped with
`netlify.toml`). Optional future hardening: rate-limit `/login`, stronger codes,
per-person auth users.
