# Flush It Command Center — Design Spec

**Date:** 2026-07-12
**Status:** Approved by Sarosh (brainstorming session)
**Base app:** `flushit-ops` (`~/Desktop/flushit/flushit-ops-hub.html` → `index.html`, GitHub Pages)

## Problem

Sarosh runs the agency across five disconnected tools:

1. **Flush It OS** (`~/Downloads/flushit-os`) — "My Week" personal planner + abandoned "Brands" tab. localStorage + Google Apps Script; unreliable sync.
2. **Edit Tracker** (`~/Downloads/Flush It/Flush it OPS htmls/FlushIt Edit Tracker - Claude.html`) — editor task tracking. localStorage only, single browser.
3. **Flush It Ops Hub** — team pipeline/queue (Supabase, works, team uses it). Its PM layer fell out of use.
4. **"Cpc" Google Sheet** — Ayesha's social calendars (she chose this after abandoning the Brands tab).
5. **Apple Notes** — ad-hoc task capture ("ivs, shoot prep, actors locking…").
6. Per-client research scattered across separate docs.

Past adoption failures were caused by **access friction** (multiple URLs/logins) and **broken sync trust** (localStorage/GAS data loss; early Supabase race bugs, since fixed).

## Decisions Made

| Question | Decision |
|---|---|
| Audience | Sarosh first, designed so team phase reuses the same structures |
| Organizing spine of the landing view | Open loops: **people cards** (Ayesha, Tanzeel, Osama, Arsal) + **stream cards** (edits, leads, inbox) |
| Absorb vs link | Absorb: capture, My Week, editor loops, client research. Link: Ayesha's Cpc Sheet (revisit at team phase) |
| Capture device | Desktop-first (laptop browser) |
| Where to build | **Extend the Ops Hub** (option 1) — one URL, one login, Supabase backend, editor data read live from existing `videos` table |
| Today layout | **Two-column (option B)**: people + expanded loops left; needs-you / leads / inbox right |
| Rejected | New separate app (recreates fragmentation); consolidating into Flush It OS (unreliable storage, no auth, can't see pipeline) |

## Architecture

One app, same single-HTML-file convention, same Supabase project, same deploy flow (`cp flushit-ops-hub.html index.html && git commit && git push`).

**New "Command" nav section** — rendered only for `isAdmin` users (Sarosh now; VP inherits when hired):

| View | Replaces |
|---|---|
| **Today** (Sarosh's landing page) | — (new) |
| **My Week** | Flush It OS My Week (port the design, not the code/data) |
| **Research** | Scattered per-client docs |
| **Leads** | WhatsApp + memory |

**Capture** is global, not a view: input pinned in the header, keyboard shortcut `c`, writes to Inbox. Replaces Apple Notes for work capture.

Team's existing six tabs (Projects, Clients, Team, Queue, Calendar, Efficiency) are untouched.

## Today View (two-column)

Header: date greeting + always-visible capture box.

**Left column — PEOPLE.** One card per active team member, loops written out (no click-to-expand):

- **Ayesha:** open loops with asked-at timestamps + link to Cpc Google Sheet. Deliverable-level statuses only (detail stays in the Sheet).
- **Tanzeel / Osama:** live edit status read from existing `videos` table (video name, stage, overdue flag) + any manual loops. **No manual edit tracking — pipeline is the source of truth.**
- **Arsal:** next shoot date (from `projects.shoot_date`) + loops/ideas.

**Right column — NEEDS YOU / STREAMS:**

- **Needs you** (computed, never stored): videos in Sarosh Review + projects at Sarosh Approval + tasks assigned to Sarosh + lead meetings today.
- **Leads** summary card (stage counts, next meeting).
- **Inbox** — captured items awaiting sorting.

Every item clicks through to its underlying task/video/lead.

## Data Model (new Supabase tables)

### `tasks` — one table for capture, loops, week items, personal to-dos

| Column | Notes |
|---|---|
| `id` uuid | |
| `title` text | |
| `notes` text | optional detail/feedback |
| `owner_id` int | creator (Sarosh = 1); team-phase ready |
| `assignee_id` int nullable | null = personal; set = loop on that person's card |
| `client` text nullable | account tag (ZeroCash, IVS, …) |
| `status` text | `open` / `in_progress` / `done` / `cancelled` |
| `scheduled_for` date nullable | set = appears in My Week that day |
| `created_at`, `completed_at` | asked-at timestamps come from `created_at` |

Placement logic: **which fields are filled decides where an item appears.** Empty everything = Inbox. `assignee_id` = person card. `scheduled_for` = My Week. Sorting an inbox item = filling fields, never re-typing.

### `notes` — research

`id`, `client`, `title`, `body` (markdown), `pinned` (bool), `created_at`, `updated_at`. Research view groups by client.

### `leads`

`id`, `name`, `contact`, `source`, `stage` (`new` → `discovery_scheduled` → `research` → `proposal` → `won` / `lost`), `meeting_at`, `notes`, `created_at`. Won leads convert to a client. Lead research lives in `notes` linked by client name.

All three tables join the existing `supabase_realtime` publication with `REPLICA IDENTITY FULL`, reusing the hub's per-session channel subscription pattern.

## Reliability Rules (lessons from the sync-bug era)

- Every Supabase write is `await`ed — no fire-and-forget.
- Every failed write shows an error toast.
- New code lives in new functions/views; zero modification to pipeline, queue, or latency logic.
- Pre-deploy check with a second (editor) login: Command section hidden, existing tabs behave identically.

## Migration & Retirement

- **Edit Tracker:** not migrated (redundant with `videos` + loops). File kept as archive. Retired.
- **Flush It OS My Week data:** not migrated (weekly/ephemeral); current week re-entered once. Design ported.
- **Research docs:** progressive migration — paste each client's research into Notes on first touch. No bulk import.
- **Flush It OS app:** after Today + My Week ship, add a redirect banner pointing to the hub, then archive the `flushit-os` repo.
- **Apple Notes:** replaced by capture for work items (behavioral, no migration).
- **Cpc Sheet:** stays; linked from Ayesha's card. Revisit at team phase.

## Build Order (each slice independently useful)

1. **Capture + Inbox + `tasks` table** — replaces Apple Notes immediately
2. **Today view** — two-column layout, people cards (live `videos` reads), needs-you, streams
3. **My Week** — ported design on `tasks.scheduled_for`
4. **Research + Leads views**
5. **Retire Flush It OS + Edit Tracker** (banner, archive)

## Team Phase (later, designed-for now)

- Each member gets a "My Tasks" view: `tasks` where `assignee_id` = them, with status updates from their existing login.
- People-card machinery becomes per-member personal views.
- Ayesha's calendar migration reconsidered only if/when the tool has earned trust.

## Testing

Manual checklist per slice: capture→inbox→sort round-trip; loop assign→appears on card→status change syncs across two browser sessions; needs-you reflects a video moved to Sarosh Review; editor login sees no Command section and unchanged tabs; error toast on network failure (offline test).
