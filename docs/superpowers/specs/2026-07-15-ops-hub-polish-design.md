# Ops Hub polish — legibility, video rename, realtime calm — design

**Date:** 2026-07-15
**Status:** Awaiting review
**Branch:** `ops-hub-polish` (cut from `main` @ `0e6c0e1`)
**Scope:** `index.html` + `flushit-ops-hub.html` (kept byte-identical)

## Problem

Three pieces of user feedback from Sarosh, 2026-07-15. Investigation showed each
has a different root cause than the symptom suggests.

### 1. Small text is hard to read on the light canvas

Two independent causes compound here.

**The scale is genuinely small.** 247 hardcoded `font-size` declarations, of which
~192 are ≤11px: 79 at 10px, 60 at 9px, 43 at 11px, 9 at 8px, 1 at 7px. macOS
declines to render UI text below 11px; the web body default is 16px.

**The muted token is broken, and this is the bigger cause.** `--td: #B8B2A6`
measures **1.99:1** against `--bg: #FAF8F4`. WCAG AA requires 4.5:1 for normal
text. It is used **77 times**, on real content — `.hs-l` (header stat labels),
`.side-label` (sidebar section headers), `.hdr-date`, `.login-subtitle`. This is
not subtle text; it is barely-rendering text. The v2 Task 4 contrast pass covered
type badges and buttons (all ≥4.5:1) but never audited `--td`.

For reference, the sibling tokens: `--text: #1A1A1A` = 16.41:1 (fine),
`--tm: #6E6A60` = 5.08:1 (fine).

### 2. Videos cannot be renamed once in production

`saveDraftName()` ([index.html:2054](../../../index.html)) already renames any
video and **never checks the `draft` flag** — the logic is fully general. It is
simply not wired into the production view:

- Drafts: `renderPanelBody()` renders an editable `<input>` per video
  ([index.html:1672](../../../index.html)).
- In production: `videoRowHTML()` renders a read-only `<span class="v-name">`
  ([index.html:1789](../../../index.html)).

So a video's name freezes the moment its project reaches stage 6.

### 3. Constant Supabase refresh, and popup noise

`subscribeRealtime()` ([index.html:1055](../../../index.html)) subscribes to
`postgres_changes` on all six tables and, on any event, debounces 400ms then calls
`loadData()` / `loadCommandData()`. Nothing checks whether the change originated
locally.

`loadData()` ([index.html:921](../../../index.html)) does, every time:

```
showLoading(true)     // full-screen loading overlay
refetch ALL projects + ALL videos
showLoading(false)
renderAll()           // kanban, clients, team, efficiency, calendar,
                      // queue, stats, open panel, today, badges
```

Consequence: **the user's own writes echo back and re-render the entire app.**
Every deadline edit, stage advance, or assignment flashes a full-screen loading
overlay and rebuilds every view 400ms later. This is the "constant refresh".

Separately, `toast('● Live')` ([index.html:1085](../../../index.html)) fires on
every channel subscribe, and Supabase realtime channels reconnect on their own —
so the popup recurs indefinitely.

Toast inventory — 46 call sites (excluding the `toast()` definition itself), in
four distinct categories:

| Kind | Count | Example | Fate |
|---|---|---|---|
| Chatty confirmations | 25 | `Deadline updated`, `✓ Sorted`, `Wingos · Ramadan → Edit` | delete |
| Connection status | 1 | `● Live` | delete |
| Async errors | 13 | `⚠ Failed to save — check connection` | keep, **persist** |
| Immediate errors | 7 | `⚠ Client needs a name`, `⚠ Access restricted` | keep, auto-dismiss |

The 13 **async** errors are the only signal that a write silently failed. The app
updates local state first and syncs after, so a silent sync failure renders as
success while the data evaporates. This is not hypothetical: it is how the Oraan
lead was lost during v2 regression testing. These fire long after the user's
action, when attention may have moved elsewhere.

The 7 **immediate** errors are validation and permission responses fired
synchronously from a click — the user is looking straight at the form. They need
no special handling.

## Goals

1. All UI text meets WCAG AA (4.5:1) and no text renders below 11px.
2. Any video can be renamed at any stage, by anyone who can see it.
3. A user's own action never triggers a **second**, echo-driven re-render or a
   loading overlay. (The immediate local `renderAll()` fired by the action handler
   is correct and stays — that is the user seeing their own edit land.)
4. An incoming realtime change never destroys in-progress typing.
5. Zero popups during normal successful operation; failures remain impossible to miss.

**Note on line numbers:** every line reference in this document is against
`index.html` @ `0e6c0e1` and is indicative only. Line numbers shift as soon as
implementation begins — the plan must key edits on surrounding content, not on
these numbers.

## Non-goals

- Surgical per-row DOM patching from realtime payloads (considered as option C;
  requires per-row DOM keying across eight views — a project, not a polish pass).
- Merging `--td` into `--tm` (see Decisions).
- Any change to the unpushed login Edge Function or RLS migration work.
- Any change to `videos`/`projects` schema.

## Design

### A. Type scale — ×1.2 with an 11px floor

Remap all 247 `font-size` declarations (182 inside `<style>`, 65 inline in JS
template strings). Integer values only — no fractional px, which renders blurry
on non-retina displays.

| Current | New | | Current | New |
|---|---|---|---|---|
| 7px | 11px | | 15px | 18px |
| 8px | 11px | | 16px | 19px |
| 9px | 11px | | 17px | 20px |
| 10px | 12px | | 18px | 22px |
| 11px | 13px | | 20px | 24px |
| 12px | 14px | | 22px | 26px |
| 13px | 15px | | 30px | 36px |
| 14px | 17px | | | |

Expected visual impact: `.side-label` (8px→11px) and `.hs-l` (9px→11px) grow
~38%. The sidebar and header stat strip will read noticeably heavier. This is
accepted.

### B. `--td` contrast fix

`--td: #B8B2A6` → `--td: #757270` (1.99:1 → **4.50:1** on `--bg`, 4.78:1 on
`--surface`). One-line token change; all 77 usages inherit it.

### C. Video rename in production

`videoRowHTML()` renders the name as a click-to-edit affordance:

- Click `<span class="v-name">` → swaps in place to an `<input>`, text selected.
- **Enter** or **blur** → commit via `saveVideoName()`.
- **Escape** → revert, no write.
- Empty/whitespace-only input → revert, no write (matches existing
  `if(!v || !name.trim()) return;` guard).
- No role gating; available at every stage including Delivered.

`saveDraftName()` → renamed `saveVideoName()`. Body unchanged. Both call sites
(draft input at [index.html:1672](../../../index.html), new production
click-to-edit) point at it. The draft screen keeps its always-on input — naming
is that screen's purpose.

Click-to-edit rather than an always-live input: a permanent field in every
production row adds visual noise to a dense list, and a permanently-focusable
input is precisely what an incoming re-render stomps.

### D. Realtime — skip self-echoes, silent reloads, defer while interacting

**D1. Skip self-originated echoes.** A module-level `_selfWrites` Set holds keys
of rows we just wrote, added by each `sync*()` and `delete*()` on success and
evicted after 5s.

**The primary key is not `id` on every table.** `meta` is keyed
`key text primary key` ([2026-07-12-command-tables.sql](../sql/2026-07-12-command-tables.sql));
`projects`, `videos`, `tasks`, `notes`, and `leads` are keyed `id`. A uniform
`table:id` scheme would produce `meta:undefined` for every meta write, never match
an echo, and leave weekly-focus edits re-rendering on every keystroke — the exact
bug being fixed, silently surviving. A single `PK_COL` map is the source of truth
for both the writers and the handlers:

```js
const PK_COL = { projects:'id', videos:'id', tasks:'id', notes:'id', leads:'id', meta:'key' };
const rowKey = (table, row) => `${table}:${row?.[PK_COL[table]]}`;
```

Handlers derive the incoming key from `payload.new ?? payload.old` — **DELETE
events carry only `payload.old`**, so reading `payload.new` alone would throw on
every delete. If the key is in `_selfWrites`, drop the event without reloading;
local state is already correct.

If `rowKey()` yields `undefined` for the PK, fall back to reloading — never drop
an event you cannot identify. Reloading is the current behavior, so the fallback
is strictly no worse than today.

This fallback is load-bearing, not decorative. Only `tasks`, `notes`, `leads`, and
`meta` have a committed `replica identity full` migration.
`projects` and `videos` predate that file and were added to the
`supabase_realtime` publication by hand in the dashboard — their replica identity
is **unverified**. Under the Postgres default (primary key only), a DELETE still
yields the PK column on `payload.old`, which is all `rowKey()` reads, so it works
either way. Implementation must not assume any column beyond the PK is present on
`payload.old`.

The 5s TTL is a deliberate over-estimate of round-trip echo latency. Worst case
on eviction race: a redundant silent reload, which is the current behavior minus
the overlay. There is no correctness risk, only a missed optimization.

**D2. Silent realtime reloads.** `loadData(opts = {})` and
`loadCommandData(opts = {})` accept `{silent: true}`. When silent, they skip
`showLoading()` entirely. Initial page load (`onSignedIn`) stays loud; every
realtime-triggered reload is silent.

**D3. Defer while interacting.** Before a realtime-triggered reload runs, check:

```
document.activeElement matches input, select, textarea, [contenteditable]
  OR currentPanelId is non-null
```

If either holds, stash the pending reload in `_deferredReload` and return.

Flushing is **not** simply "on the next `focusout`". `focusout` fires when tabbing
between two fields, which would flush mid-edit and re-introduce the exact stomp
being fixed. The flush handler must re-run the same guard and only proceed when
the user has genuinely stopped interacting:

```
on document 'focusout':
  queueMicrotask(() => {          // let activeElement settle to the NEW target
    if (stillInteracting()) return;   // tabbed to another field, or panel open
    flushDeferredReload();
  })
on panel close:
  if (!stillInteracting()) flushDeferredReload();
```

`stillInteracting()` is the single shared predicate used by both the defer check
and the flush check. This closes chip `task_4473160f` (realtime re-render stomps
focused inputs).

Only realtime-triggered reloads defer. Explicit user-initiated reloads run
immediately.

### E. Toasts

- Delete the 25 chatty confirmation calls (lines 1433, 1447, 1457, 1468, 1831,
  1863, 1867, 1910, 1922, 1934, 1956, 1971, 1989, 2004, 2051, 2068, 2097, 2115,
  2130, 2743, 3015, 3156, 3176, 3250, 3270) and the 1 `● Live` status call
  (line 1085).
- Keep all 20 error calls, unchanged in wording.
- `toast(msg, persist = false)`: when `persist`, skip the 2800ms auto-dismiss and
  render a dismiss control; the toast stays until clicked.
- Pass `persist = true` at the **13 async** sites only (929, 956, 968, 982, 1018,
  1023, 1030, 1034, 1041, 1045, 1050, 1086, 2739).
- The **7 immediate** sites (1410, 1443, 2732, 2749, 2751, 3066, 3264) keep
  auto-dismiss. Making a validation message sticky while the user stares at the
  form it describes is noise, not safety.
- `⚠ Live sync offline` (1086) is async and therefore persists — correct, since a
  dead channel means the user is looking at stale data without knowing it.
- Line 2732 (`Please fill in client and project name`) is a validation error
  despite lacking a `⚠` prefix; it is classed immediate, not chatty.

## Data flow after the change

```
User edits a deadline
  └─ local state updated (optimistic)
  └─ renderAll() called directly by the action handler  ← unchanged, immediate
  └─ syncProject() writes to Supabase
       └─ on success: _selfWrites.add('projects:42')
       └─ on failure: toast('⚠ Failed to save…', true)  ← persists

Supabase echoes the change back 200-600ms later
  └─ handler sees 'projects:42' in _selfWrites → DROPPED. No reload, no overlay.

Ayesha edits a different project
  └─ handler sees 'projects:57', not in _selfWrites
  └─ is Sarosh typing, or is a panel open?
       ├─ yes → stash in _deferredReload, flush on focusout/panel close
       └─ no  → loadData({silent: true}) → renderAll(). No overlay.
```

## Error handling

- Sync failure: unchanged path, now a persistent toast. Local state stays
  optimistic (pre-existing behavior; not in scope to change).
- Load failure: `⚠ Failed to load data` persists.
- Channel error/timeout: `⚠ Live sync offline` persists.
- `_selfWrites` eviction race: redundant silent reload. Benign.
- `_deferredReload` never flushing (user leaves a panel open indefinitely): data
  goes stale until they close it. Accepted — the alternative is stomping their
  work, which is the bug being fixed.

## Testing

No test runner exists in this project. Verification, matching the v2 convention:

1. `node --check` on the extracted `<script>` body.
2. `diff index.html flushit-ops-hub.html` → identical.
3. Grep assertions:
   - No text below 11px: every match of `font-size:([0-9]+)px` has capture ≥ 11.
   - No fractional sizes: zero matches for `font-size:[0-9]+\.[0-9]+px`.
   - `--td:#B8B2A6` gone; `--td:#757270` present exactly once.
   - 20 `toast(` call sites remain (21 lines including the definition); 13 pass
     `true` as the second argument.
   - Zero `saveDraftName` references; `saveVideoName` present at 2 call sites
     plus its definition.
4. Browser verification (Playwright + code login, served from a scratchpad copy
   on :4173 due to Desktop TCC):
   - Contrast: computed style of `.hs-l` is `#757270`; no text below 11px.
   - Rename: click a production video name, edit, Enter → persists across reload;
     Escape reverts; empty input reverts.
   - Self-echo: change a deadline → **no** loading overlay, no visible re-render.
   - Cross-client: two sessions; Ayesha's change appears in Sarosh's view without
     an overlay.
   - Defer: type into a panel field while a second session writes → text survives,
     reload lands on blur.
   - Failure: kill the network, edit → persistent error toast that does not
     self-dismiss.
   - Regression: pipeline advance, video assign/QC/delete, capture/inbox,
     won-lead tag propagation, editor gating.

## Decisions

**`--td` and `--tm` converge, and that is accepted.** At 4.50:1 vs 5.08:1 the two
tokens are visually near-identical, collapsing the three-tier text hierarchy to
two. This is unavoidable — there is not enough room between "passes AA" and
"black" for three steps. `--td` was never doing hierarchy work; it was invisible,
and invisible reads as hierarchy only until you try to read it. Hierarchy should
come from size, weight, and casing instead. A `--td`→`--tm` merge is a follow-up.

**Click-to-edit over always-on input** for production rename — see C.

**Errors keep popups; confirmations lose them.** The stated ask was to remove all
popups. Removing the error toasts would make silent data loss undetectable, which
has already cost real data once. Since errors fire only on genuine failure, a
normal session shows zero popups either way — the ask is satisfied without the
risk.

**Option B over C** for realtime. C (surgical patching) is the better end state
but requires per-row DOM keying across eight views. B is ~30 lines and fixes both
the felt problem and the known data-loss chip. C remains available later.

## Deployment note

This branch sits on top of **10 unpushed commits** on `main` (`be354b3..0e6c0e1`
— the v2 My Week rebuild, `--pink` saturation, `--fg` token fix, plus the staged
login Edge Function and RLS SQL). The live site is still serving `be354b3`.
Merging and pushing this work will also deploy all of that. The HTML changes are
safe to ship — the Edge Function is committed but not yet wired into the page —
but `2026-07-15-enable-rls-authenticated.sql` must **not** be run in the Supabase
dashboard until that separate work is finished, or anon access breaks.

## Follow-ups (not this change)

- Merge `--td` into `--tm`; rebuild text hierarchy on size/weight/casing.
- Option C: surgical per-row DOM patching from realtime payloads.
- Optimistic writes still don't roll back on sync failure (the other half of chip
  `task_4473160f`). The persistent toast makes failure *visible*; it does not make
  it *recoverable*.
