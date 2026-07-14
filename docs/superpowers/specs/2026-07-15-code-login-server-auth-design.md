# Server-enforced code login + RLS — design

**Date:** 2026-07-15
**Status:** Awaiting review
**Prereq for:** public hosting (deferred until this lands)

## Problem

The app gates access with per-person codes checked entirely in the browser
(`TEAM.find(t => t.code === code)`, [flushit-ops-hub.html:3527](../../../flushit-ops-hub.html)).
To make that work, RLS was **disabled** on every table
([2026-07-13-code-login-rls.sql](../sql/2026-07-13-code-login-rls.sql)), so all
data is reachable with the public anon key. The codes and the anon key both live
in the page source.

Consequence: once the page is served on a public URL, anyone can read it, extract
the anon key, and call the Supabase REST API directly to read/update/delete
`projects`, `videos`, `tasks`, `notes`, `leads`, and `meta` — bypassing the login
completely. The code screen is cosmetic. This blocks hosting.

## Goals

1. The database refuses all unauthenticated access. A visitor without a valid
   code gets **zero** rows, even hitting the REST API directly with the anon key.
2. Keep the login UX identical: one field, type your code, you're in.
3. Codes and any auth password are **not** present in the client source.
4. Sessions persist across reloads; real sign-out.

## Non-goals

- **Per-user / per-role database permissions.** Everyone on the team sees and
  edits everything today; RLS will be blanket "any authenticated session = full
  access." Role gating (`isAdmin`, editor views) stays a client-side UX concern,
  exactly as now. Intra-team privilege enforcement is explicitly out of scope.
- **Rate limiting.** Decided against for v1 (memorable codes, obscure endpoint).
  Noted as an accepted risk and an easy follow-on.
- **Migrating off the shared account to per-person auth users.** Future option.

## Architecture

Three pieces:

### 1. RLS on, authenticated-only

New migration `docs/superpowers/sql/2026-07-15-enable-rls-authenticated.sql`
(supersedes the disable migration):

- `alter table … enable row level security;` for all six tables.
- One policy per table: `for all to authenticated using (true) with check (true)`.
- No policy for `anon` → the anon role is blocked from every table.

Result: the anon key alone returns nothing. Only a request carrying a valid
authenticated JWT gets data.

### 2. One shared auth user

A single Supabase Auth user (e.g. `app@flushit.internal`) with a strong random
password. This is the identity every code maps to. Its password lives **only** in
the Edge Function's secrets, never in the client. (One shared user is sufficient
because RLS is blanket-authenticated; we don't need distinct DB identities.)

### 3. `login` Edge Function — the only holder of the codes

Repo path: `supabase/functions/login/index.ts`. The function file contains **no
secrets**; codes and the shared password come from env secrets, so the file is
safe to keep in the repo.

**Secrets (set in Supabase, not in the file):**
- `CODE_MAP` — JSON string mapping code → member id, e.g. `{"bebatzai":1,"ayesha":3,...}`
- `APP_EMAIL`, `APP_PASSWORD` — the shared auth user's credentials
- `SUPABASE_URL`, `SUPABASE_ANON_KEY` — for the server-side sign-in call

**Contract:**
- `POST /login` with JSON `{ "code": "<typed code>" }`
- Valid code → `200 { "session": <supabase session>, "memberId": <int> }`
  - session obtained by the function calling
    `supabase.auth.signInWithPassword(APP_EMAIL, APP_PASSWORD)` with the anon key
- Invalid/missing code → `401 { "error": "Code not recognised." }`
- CORS enabled for the app origin (and `*` while on localhost).

### Client changes ([flushit-ops-hub.html](../../../flushit-ops-hub.html))

- Remove the `code:` field from every `TEAM[]` entry (codes leave the source).
- `LOGIN_FN_URL` constant = `${SUPABASE_URL}/functions/v1/login`.
- `doLogin()`:
  1. POST `{code}` to `LOGIN_FN_URL`.
  2. On `401` → show "Code not recognised." (unchanged UX).
  3. On `200` → `await db.auth.setSession(session)`, store `memberId` in
     `localStorage` (key `flushit-member-id`), then `onSignedIn(member)`.
- `doLogout()` → `await db.auth.signOut()` + remove `flushit-member-id`.
- `init()` (session resume): `const { data:{ session } } = await db.auth.getSession()`.
  If a valid session exists **and** a stored `memberId` resolves to a TEAM
  member → `onSignedIn(member)`. supabase-js auto-refreshes the token; if refresh
  fails, fall through to the login screen. Remove the old
  `CODE_STORAGE_KEY`/`flushit-access-code` path.
- `onSignedIn()` is unchanged except it receives the member resolved via id.
  Data loads (`loadData`, `loadCommandData`) and `subscribeRealtime()` run only
  after `setSession`, so every request carries the JWT and passes RLS.

## Data flow

**Login:** type code → `POST /login` → function verifies against `CODE_MAP` →
signs in shared user → returns `{session, memberId}` → client `setSession` +
store id → load data (JWT attached) → RLS allows.

**Resume:** reload → `getSession()` returns persisted session → resolve stored
`memberId` → load data. Token auto-refreshes; expired/absent → login screen.

**Public attacker:** no code → can't get a session → anon key returns nothing
from every table. Extracting the anon key from the page yields no data access.

## Security model & accepted risks

- **Closed:** unauthenticated/public access to all data. This is the goal.
- **Accepted (v1):**
  - *No rate limiting* — the `/login` endpoint is public; memorable codes are
    low-entropy and guessable by a determined scripted attacker. Mitigation is
    endpoint obscurity only. Easy to add later (per-IP throttle / lockout).
  - *Blanket-authenticated RLS* — any valid code grants full data access; no
    DB-level separation between team members (matches today's model).
  - *Shared client-side identity* — `memberId` is chosen client-side, so role
    UX is not tamper-proof. No privilege boundary exists in the DB anyway
    (same as today).

## Manual (Supabase) vs code (me)

**I do (in the repo):**
- Write `2026-07-15-enable-rls-authenticated.sql`.
- Write `supabase/functions/login/index.ts`.
- Rewrite the client auth (`doLogin`/`doLogout`/`init`, remove codes from TEAM).
- Keep `index.html` byte-identical (cp + cmp), commit both.

**You do (in Supabase dashboard, with my exact steps):**
- Run the RLS SQL in the SQL editor.
- Create the shared auth user (Authentication → Users) and note its password.
- Deploy the function (Supabase CLI `supabase functions deploy login`, or paste
  into the dashboard function editor) and set the secrets listed above.

## Verification

1. **Anon is blocked:** with only the anon key (no session),
   `curl "$SUPABASE_URL/rest/v1/leads?select=*" -H "apikey: $ANON"` returns `[]`
   / permission error — not data.
2. **Bad code:** `POST /login {code:"nope"}` → 401; app shows the error.
3. **Good code:** login succeeds, all tabs load, realtime "Live" works, reload
   keeps you signed in, sign-out returns to the code screen.
4. **Direct API after login:** the same REST call with the session JWT returns
   data (confirms authenticated policy works).

## Rollout & rollback

- Order: deploy function + create user + **set secrets first**, then ship the
  client change, then run the RLS SQL last (so data access flips to enforced
  only once login can mint sessions). Test on localhost against live Supabase.
- Rollback: re-run the disable-RLS migration (instantly restores old behavior)
  and revert the client commit.

## Follow-ons (out of scope here)

- Public hosting (the original request) — proceed once this is verified.
- Optional: rate limiting on `/login`; stronger codes; per-user auth accounts.
