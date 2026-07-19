# Content Agent — Design Spec (2026-07-19)

Approved by Sarosh in-session 2026-07-19. Replaces the Leads + Research tabs with a
single **Content** section: per-client content calendars + an AI agent (Claude) that
drops fresh ideas every morning and generates on demand. Brings Bebatzai's content
system (pillars, 4:1 guide, Thinker) from the old Flush It OS into the hub.

## Decisions (from brainstorm)
- **Agent UX:** scheduled morning drop + on-demand per-client Generate (mix).
- **Calendar:** hub-native, team-visible. Agent proposes dated slots; Sarosh approves;
  Ayesha sees the approved calendar. Cpc sheet retires eventually.
- **Agent inputs:** per-client brief (positioning/audience/pillars/tone/cadence) +
  hub data (idea history incl. killed = taste signal, current calendar).
- **Leads/Research:** Research notes fold into per-client idea bank (one-time SQL
  migration; `notes` table left in DB, unused). Leads UI removed; `leads` table kept
  invisible. Capture "file under…" now banks into the client's idea bank.
- **Architecture:** Supabase Edge Function `content-agent` holds the Anthropic key
  (secret); pg_cron daily drop at 06:00 PKT (01:00 UTC); hub calls it for Generate.
- **Model:** `claude-opus-4-8`, structured outputs (JSON schema). ~5 ideas/client/drop.
  Est. cost ≈ $0.30/day for ~6 clients.

## Data model (new tables; SQL in `2026-07-19-content-tables.sql`)
- `content_briefs`: client text PK, positioning, audience, pillars jsonb, tone,
  cadence int (posts/week), notes, updated_at.
- `content_ideas`: id text PK, client, title, angle, pillar, format,
  status ('proposed'|'banked'|'scheduled'|'killed'), scheduled_for date null,
  source ('agent'|'capture'|'research'|'manual'), created_at, updated_at.
- Both: realtime publication + REPLICA IDENTITY FULL + RLS disabled (app convention).
- Killed ideas kept as rows (agent feedback), hidden from UI.
- Migration in same SQL: `notes` rows → banked content_ideas (source 'research').

## Idea lifecycle
proposed (agent, undated = fresh drop; dated = proposed slot) → schedule (pick date)
| bank | kill. Scheduled ideas render on the calendar strip. Approving a dated
proposal sets status scheduled. All transitions sync via existing optimistic-write +
markSelfWrite pattern (`content_briefs` PK col = `client`).

## Hub UI
- Nav: GROWTH group → CONTENT, single item "Content" (badge = proposed count, admins).
  `tab-leads`/`tab-research` + all their render/CRUD code removed.
- Content view: client chips (Bebatzai first) →
  1. Generate row: pillar pills (from brief) + seed input + Generate (calls function).
  2. Calendar: next-14-day strip; approved solid, proposed dashed (✓ / date / ×).
  3. Fresh drop: undated proposed ideas as cards (title, pillar, format, angle;
     Schedule/Bank/Kill).
  4. Idea bank: banked ideas, same actions.
  5. Brief (collapsible, editable). Bebatzai brief also shows static 4:1 guide card
     ported from old OS; old pillars pre-fill via SQL seed.
- Non-admins: Content visible, calendar section only.
- Today: hero counts swap "N meetings" (leads) → "N ideas waiting"; needs-you gains
  amber "✦ N fresh ideas — review" card → Content. `allClientNames()` repointed to
  briefs + projects.
- Graceful degradation: content tables missing (SQL not yet run) → Content tab shows
  a setup notice; rest of app unaffected (content load failures caught per-table).

## Edge function `content-agent` (Deno/TS, official Anthropic SDK via npm:)
- POST {action:'drop'} — every client with a brief; idempotent per Asia/Karachi day
  (skips client if agent-sourced ideas already created today). Inserts ~5 proposed
  ideas; dates some onto empty cadence days as proposed slots.
- POST {action:'generate', client, pillar?, seed?} — one client, returns ideas.
- Context per call: brief + last 30 ideas w/ status + next 14 days of calendar.
- Auth: caller sends Authorization: Bearer <anon key> (verify_jwt) + x-agent-token
  matching AGENT_TOKEN secret (token-burn gate; consistent with app threat model).
- Uses auto-provided SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY env for DB writes.
- Failure: hub Generate shows persistent error toast; missed cron = no drop, hub
  unaffected; logs in Supabase dashboard.

## One-time activation (Sarosh, dashboard)
1. Run `docs/superpowers/specs/../../../2026-07-19-content-tables.sql` in SQL editor
   (tables + seed briefs + notes migration + cron job).
2. Create edge function `content-agent`, paste `supabase/functions/content-agent/index.ts`.
3. Set secrets: ANTHROPIC_API_KEY (new key from console.anthropic.com), AGENT_TOKEN
   (value baked into the SQL cron + hub source).

## Out of scope / follow-ups
- Old OS Content Bank data (GAS sheet) port — later session with Sarosh.
- Ayesha's Cpc sheet retirement — after team adopts hub calendar.
- Task 11 (retire old OS) — unblocked once Bebatzai lives here.

## Plan (executed in-session, single implementer with full context)
1. SQL migration file + edge function source, committed.
2. Hub: nav/tab swap + remove Leads/Research code.
3. Hub: content data layer (load/sync/realtime, graceful missing-table catch).
4. Hub: Content view render + actions + gating.
5. Hub: capture file-under → bank; hero/needs-you integration.
6. node --check + browser verification (graceful path pre-SQL), deploy to Pages.
