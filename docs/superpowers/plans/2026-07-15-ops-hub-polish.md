# Ops Hub Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all Ops Hub text legible, allow renaming videos already in production, and stop the app re-rendering itself after every action.

**Architecture:** Four independent changes to a single-file HTML app. Typography is a mechanical remap of 247 `font-size` declarations plus one token fix. Rename wires an existing, already-general function into a second view. Realtime gains self-echo suppression, silent reloads, and an interaction guard. Toasts lose 26 chatty calls and gain a persist flag for the 13 asynchronous error sites.

**Tech Stack:** Vanilla JS, single HTML file, Supabase JS v2 (realtime + REST). No build step. No test runner — verification is a static assertion script (`node --check` + greps) plus Playwright-driven browser checks.

**Spec:** [`docs/superpowers/specs/2026-07-15-ops-hub-polish-design.md`](../specs/2026-07-15-ops-hub-polish-design.md)

---

## Critical conventions — read before Task 1

**`flushit-ops-hub.html` is the source. `index.html` is the deploy copy.**
Every edit goes into `flushit-ops-hub.html`, then `cp flushit-ops-hub.html index.html`
before committing. The two files must be byte-identical in every commit. They are
identical right now, so all line numbers below apply to both.

**Line numbers are indicative only.** They are against `0e6c0e1`. They shift the
moment Task 2 runs. Always locate edits by the quoted source text, never by
line number alone.

**Task order matters.** Task 2 (type scale) rewrites every `font-size` in the
file. Any CSS added in Tasks 3–5 must therefore be written with **final** sizes
(≥11px), not pre-remap sizes. Do not run Task 2 after Tasks 3–5.

**Preserve `textContent` in `toast()`.** The current implementation assigns
`el.textContent = msg`, which is what makes it XSS-safe. Never switch to
`innerHTML`.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `flushit-ops-hub.html` | The entire app. Source of truth. | Modified in Tasks 2–5 |
| `index.html` | Byte-identical deploy copy for GitHub Pages. | `cp` after every task |
| `docs/superpowers/scripts/verify-polish.sh` | Static invariants for this change. | Created in Task 1 |

---

## Task 1: Verification harness

Builds the failing test first. Every later task turns one section of this script green.

**Files:**
- Create: `docs/superpowers/scripts/verify-polish.sh`

- [ ] **Step 1: Write the failing check script**

Create `docs/superpowers/scripts/verify-polish.sh`:

```bash
#!/usr/bin/env bash
# Static invariants for the ops-hub-polish change.
# Usage: bash docs/superpowers/scripts/verify-polish.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

SRC=flushit-ops-hub.html
DEPLOY=index.html
FAIL=0
ok()  { printf "  \033[32m✓\033[0m %s\n" "$1"; }
bad() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAIL=1; }

echo "── A. Type scale ──"
SMALL=$(grep -o 'font-size:[0-9]\+px' "$SRC" | grep -o '[0-9]\+' | awk '$1<11' | wc -l | tr -d ' ')
[ "$SMALL" = "0" ] && ok "no font-size below 11px" || bad "$SMALL declarations still below 11px"
FRAC=$(grep -c 'font-size:[0-9]\+\.[0-9]\+px' "$SRC" || true)
[ "$FRAC" = "0" ] && ok "no fractional font-size" || bad "$FRAC fractional font-size declarations"

echo "── B. Contrast token ──"
grep -q -- '--td:#757270' "$SRC" && ok "--td is #757270" || bad "--td is not #757270"
grep -q -- '--td:#B8B2A6' "$SRC" && bad "old --td #B8B2A6 still present" || ok "old --td gone"

echo "── C. Video rename ──"
grep -q 'saveDraftName' "$SRC" && bad "saveDraftName still referenced" || ok "saveDraftName gone"
SVN=$(grep -c 'saveVideoName' "$SRC" || true)
[ "$SVN" -ge 3 ] && ok "saveVideoName present ($SVN refs: 1 def + 2 call sites)" || bad "saveVideoName has $SVN refs, expected >=3"

echo "── D. Realtime ──"
grep -q 'PK_COL' "$SRC" && ok "PK_COL map present" || bad "PK_COL map missing"
grep -q '_selfWrites' "$SRC" && ok "_selfWrites present" || bad "_selfWrites missing"
grep -q 'stillInteracting' "$SRC" && ok "stillInteracting present" || bad "stillInteracting missing"

echo "── E. Toasts ──"
CALLS=$(grep -c 'toast(' "$SRC" || true)
[ "$CALLS" = "21" ] && ok "21 toast lines (20 call sites + 1 definition)" || bad "$CALLS toast lines, expected 21"
PERSIST=$(grep -c 'toast(.*, *true)' "$SRC" || true)
[ "$PERSIST" = "13" ] && ok "13 persisting error toasts" || bad "$PERSIST persisting toasts, expected 13"
grep -q "toast('● Live')" "$SRC" && bad "'● Live' toast still present" || ok "'● Live' toast gone"

echo "── F. Integrity ──"
diff -q "$SRC" "$DEPLOY" >/dev/null 2>&1 && ok "index.html identical to source" || bad "index.html differs from source"
S=$(grep -n '<script>' "$SRC" | tail -1 | cut -d: -f1)
E=$(grep -n '</script>' "$SRC" | tail -1 | cut -d: -f1)
TMP=$(mktemp /tmp/opshub-XXXXXX.js)
awk -v s="$S" -v e="$E" 'NR>s && NR<e' "$SRC" > "$TMP"
node --check "$TMP" 2>/dev/null && ok "node --check passes" || bad "node --check FAILS"
rm -f "$TMP"

echo ""
[ "$FAIL" = "0" ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $FAIL
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bash docs/superpowers/scripts/verify-polish.sh
```

Expected: `SOME CHECKS FAILED`, exit 1. Sections A–E fail. Section F (`index.html identical`, `node --check passes`) should already **pass** — those are baseline invariants that must never break.

If section F fails at this point, stop. The working tree is not clean; fix that before proceeding.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/scripts/verify-polish.sh
git commit -m "test: static verification harness for ops-hub-polish

Asserts type scale floor, --td contrast token, rename wiring, realtime
self-echo machinery, toast counts, and source/deploy-copy integrity.
Fails on all sections except F until the implementation lands."
```

---

## Task 2: Type scale remap and `--td` contrast fix

Turns section A and B green.

**Files:**
- Modify: `flushit-ops-hub.html` (247 `font-size` declarations, 1 token)
- Modify: `index.html` (via `cp`)

- [ ] **Step 1: Confirm the input assumptions still hold**

```bash
grep -o 'font-size:[^;"'"'"'}]*' flushit-ops-hub.html | sed 's/font-size://' | grep -v '^[0-9]\+px$' | sort -u
```

Expected: **empty output.** Every `font-size` is `font-size:<integer>px` with no space, no `clamp()`, no `em`/`rem`/`%`, no `var()`. If this prints anything, stop and report — the remap script below will miss those cases.

- [ ] **Step 2: Run the remap**

```bash
node - <<'EOF'
const fs = require('fs');
const MAP = {7:11, 8:11, 9:11, 10:12, 11:13, 12:14, 13:15, 14:17,
             15:18, 16:19, 17:20, 18:22, 20:24, 22:26, 30:36};
const f = 'flushit-ops-hub.html';
const src = fs.readFileSync(f, 'utf8');
const unmapped = new Set();
let count = 0;
const out = src.replace(/font-size:(\d+)px/g, (m, n) => {
  const v = MAP[+n];
  if (v === undefined) { unmapped.add(n); return m; }
  count++;
  return 'font-size:' + v + 'px';
});
if (unmapped.size) {
  console.error('UNMAPPED SIZES, aborting:', [...unmapped].join(', '));
  process.exit(1);
}
fs.writeFileSync(f, out);
console.log('remapped', count, 'declarations');
EOF
```

Expected: `remapped 247 declarations`

This is a **single pass** with a callback — that is deliberate. A sequence of
`sed` substitutions would double-apply (10→12, then the 12 rule catches it again
and makes it 14).

- [ ] **Step 3: Fix the `--td` token**

```bash
sed -i '' 's/--td:#B8B2A6/--td:#757270/' flushit-ops-hub.html
grep -o -- '--td:#[0-9A-F]*' flushit-ops-hub.html
```

Expected: `--td:#757270`

- [ ] **Step 4: Sync the deploy copy and verify**

```bash
cp flushit-ops-hub.html index.html
bash docs/superpowers/scripts/verify-polish.sh
```

Expected: sections **A**, **B**, and **F** now pass. C, D, E still fail.

- [ ] **Step 5: Commit**

```bash
git add flushit-ops-hub.html index.html
git commit -m "style: x1.2 type scale with an 11px floor, fix --td contrast

247 font-size declarations remapped (7/8/9 -> 11, 10 -> 12, 11 -> 13,
12 -> 14, 13 -> 15, 14 -> 17, 15 -> 18, 16 -> 19, 17 -> 20, 18 -> 22,
20 -> 24, 22 -> 26, 30 -> 36). Integers only — fractional px renders
blurry on non-retina.

--td #B8B2A6 -> #757270. The old value measured 1.99:1 against --bg
(#FAF8F4) while being used 77 times on real content: header stat labels,
sidebar section headers, the header date, the login subtitle. WCAG AA
requires 4.5:1; the new value is 4.50:1.

--td and --tm (5.08:1) now read near-identically. That is accepted and
documented in the spec: there is no room for three distinct steps between
'passes AA' and black. Hierarchy moves to size/weight/casing."
```

---

## Task 3: Toasts — delete the chatty ones, persist the async errors

Turns section E green.

**Files:**
- Modify: `flushit-ops-hub.html`
- Modify: `index.html` (via `cp`)

- [ ] **Step 1: Rewrite `toast()` with a persist flag**

Find (note: `font-size` is already remapped by Task 2, so the CSS rule reads `13px` now, not `11px`):

```javascript
function toast(msg){
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  setTimeout(() => el.classList.remove('show'), 2800);
}
```

Replace with:

```javascript
let _toastTimer;
function toast(msg, persist = false){
  const el = document.getElementById('toast');
  clearTimeout(_toastTimer);
  el.textContent = msg;
  if(persist){
    const x = document.createElement('button');
    x.type = 'button';
    x.className = 'toast-x';
    x.setAttribute('aria-label', 'Dismiss');
    x.textContent = '×';
    x.onclick = () => el.classList.remove('show');
    el.appendChild(x);
  }
  el.classList.toggle('persist', persist);
  el.classList.add('show');
  if(!persist) _toastTimer = setTimeout(() => el.classList.remove('show'), 2800);
}
```

`el.textContent = msg` stays as the first write — it both clears any previous
dismiss button and escapes the message. Do not replace it with `innerHTML`.

- [ ] **Step 2: Add the dismiss-button CSS**

Find:

```css
.toast.show{opacity:1;transform:translateY(0)}
```

Add immediately after it:

```css
.toast.persist{pointer-events:auto;padding-right:11px}
.toast-x{background:none;border:none;color:#FAF8F4;font-size:15px;line-height:1;cursor:pointer;padding:0 2px;margin-left:11px;opacity:.65}
.toast-x:hover{opacity:1}
```

The base `.toast` rule sets `pointer-events:none`; `.toast.persist` must undo it
or the dismiss button will not be clickable. Sizes here are already final —
Task 2 has run.

- [ ] **Step 3: Pass `true` at the 13 async error sites**

Add `, true` as the second argument at each of these exact calls. All 13 are
inside `catch`/`if(error)` branches following an `await` on Supabase.

| Function | Current call |
|---|---|
| `loadData` | `toast('⚠ Failed to load data')` |
| `syncProject` | `toast('⚠ Failed to save — check connection')` |
| `syncVideo` | `toast('⚠ Failed to save — check connection')` |
| `loadCommandData` | `toast('⚠ Failed to load command data')` |
| `syncTask` | `toast('⚠ Failed to save — check connection')` |
| `deleteTask` | `toast('⚠ Failed to delete — check connection')` |
| `syncNote` | `toast('⚠ Failed to save — check connection')` |
| `deleteNoteRow` | `toast('⚠ Failed to delete — check connection')` |
| `syncLead` | `toast('⚠ Failed to save — check connection')` |
| `deleteLeadRow` | `toast('⚠ Failed to delete — check connection')` |
| `syncMeta` | `toast('⚠ Failed to save — check connection')` |
| `subscribeRealtime` | `toast('⚠ Live sync offline')` |
| `createProject` | `toast('⚠ Error creating project')` |

Each becomes e.g. `toast('⚠ Failed to save — check connection', true)`.

The message strings repeat across functions, so edit **inside each named
function**, not by global find-and-replace on the string.

- [ ] **Step 4: Leave the 7 immediate error sites alone**

Do **not** add `true` to these. They fire synchronously from a click while the
user is looking at the form, so a sticky toast would be noise:

`⚠ You don't have permission to advance this stage` · `⚠ Only VP or Sarosh can move stages back` · `Please fill in client and project name` · `⚠ Access restricted` (×2) · `⚠ Client needs a name` · `⚠ Check the date`

- [ ] **Step 5: Delete the 22 standalone chatty calls**

Delete each of these lines entirely:

```javascript
toast(`${p.client} · ${p.name} → ${STAGES[p.stage].label}`);
toast(`${p.client} · ${p.name} ← ${STAGES[p.stage].label}`);
toast(`Removed: ${p.client} · ${p.name}`);
toast(editorId ? `${v.name} → ${getTeam(parseInt(editorId)).name}` : `${v.name} unassigned`);
toast(`🎉 ${p.client} · ${p.name} — all videos delivered!`);
toast(`${v.name} → ${VIDEO_STAGES[v.stage]}`);
toast(`↩ ${v.name} — client revision, back to Edit`);
toast(`Removed: ${v.name}`);
toast(`Added ${count}× ${EDIT_TYPES[type].label}`);
toast(`Plan: ${count}× ${EDIT_TYPES[type].label} added`);
toast(`Sarosh Review ${p.saroshReview?'enabled':'disabled'} for ${p.name}`);
toast(`${label} updated to "${val.trim()}"`);
toast(`Video tasks synced from plan`);
toast(editorId ? `${v.name} pre-assigned to ${getTeam(parseInt(editorId)).name}` : `${v.name} unassigned`);
toast(`Shoot date ${val ? 'set to ' + new Date(val).toLocaleDateString('en-GB',{day:'numeric',month:'short'}) : 'cleared'}`);
toast(`⏱ Timer started: ${v.name}`);
toast(`${cfg.label} saved`);
toast(`✓ Created: ${client} · ${name}`);
toast('✓ Focus saved');
toast(`→ Research · ${client}`);
toast('● Live');
if(stage === 'won') toast(`🎉 ${l.name} is now a client — available as a tag everywhere`);
```

The last one is safe to delete whole — the `if` guards nothing but the toast.

- [ ] **Step 6: Surgically edit the 3 embedded chatty calls — DO NOT delete these lines**

These three have the toast tangled up with real logic. Deleting the line deletes
the behaviour.

**6a. Project deadline.** Find:

```javascript
if(input.value){ p.deadline = input.value; toast(`Deadline updated`); syncProject(p); }
```

Replace with:

```javascript
if(input.value){ p.deadline = input.value; syncProject(p); }
```

**6b. Video deadline.** Find:

```javascript
if(input.value){ v.deadline = input.value; toast(`${v.name} deadline updated`); syncVideo(v, projId); }
```

Replace with:

```javascript
if(input.value){ v.deadline = input.value; syncVideo(v, projId); }
```

**6c. Capture — the dangerous one.** Find:

```javascript
  if(await syncTask(t)) toast('✓ Captured');
```

Replace with:

```javascript
  await syncTask(t);
```

**Deleting this line outright would remove the `syncTask` call**, because the
sync is the `if` condition. Every capture would then be lost on reload. The
`await` must survive.

**6d. Inbox sort.** Find:

```javascript
  const ok = await syncTask(t);
  renderCommand();
  if(ok) toast('✓ Sorted');
```

Replace with:

```javascript
  await syncTask(t);
  renderCommand();
```

Same hazard as 6c in a different shape: the sync must stay, and `ok` becomes
unused so its binding goes too.

- [ ] **Step 7: Verify**

```bash
cp flushit-ops-hub.html index.html
bash docs/superpowers/scripts/verify-polish.sh
```

Expected: sections **A, B, E, F** pass. C and D still fail.

If E reports a count other than 21 toast lines, one of the deletions in Step 5
was missed or one in Step 6 was deleted rather than edited. Re-check Step 6
first — that is the failure mode that loses data silently.

- [ ] **Step 8: Confirm no sync calls were lost**

```bash
grep -c 'await syncTask(t)' flushit-ops-hub.html
```

Expected: `2` (the capture path from 6c, the sort path from 6d).

- [ ] **Step 9: Commit**

```bash
git add flushit-ops-hub.html index.html
git commit -m "feat: silence 26 chatty toasts, persist the 13 async error toasts

Removes 25 confirmation toasts and the '● Live' status toast, which fired
on every channel (re)subscribe and therefore recurred forever.

Keeps all 20 error toasts. The 13 asynchronous ones (sync/load/delete
failures, channel offline) now persist until dismissed instead of vanishing
after 2800ms — they are the only signal that an optimistic write silently
failed, and a 2.8s window is easy to miss. The 7 immediate validation and
permission errors keep auto-dismiss; they fire while the user is looking
straight at the form.

Three chatty calls were embedded in load-bearing expressions and were
edited rather than deleted — notably 'if(await syncTask(t)) toast(...)',
where deleting the line would have deleted the sync."
```

---

## Task 4: Realtime — self-echo suppression, silent reloads, interaction guard

Turns section D green. This is the task that fixes the reported problem.

**Files:**
- Modify: `flushit-ops-hub.html`
- Modify: `index.html` (via `cp`)

- [ ] **Step 1: Add the PK map, self-write tracking, and interaction guard**

Insert immediately **above** `function subscribeRealtime(){`:

```javascript
// ─── REALTIME ECHO SUPPRESSION ───────────────────────────────────────────────
// meta is keyed by `key`, every other table by `id`. A uniform 'table:id' key
// would yield 'meta:undefined', never match, and leave weekly-focus edits
// re-rendering on every keystroke.
const PK_COL = { projects:'id', videos:'id', tasks:'id', notes:'id', leads:'id', meta:'key' };
const rowKey = (table, row) => `${table}:${row?.[PK_COL[table]]}`;

// Debounce timers, keyed by name. This must be a plain object, NOT `window[...]`:
// the existing `let _realtimeDebounce;` is a top-level `let`, which does not
// create a window property, so `window._realtimeDebounce` would be a separate
// always-undefined value — clearTimeout would no-op and the debounce would never
// debounce.
const _debounce = {};

const _selfWrites = new Set();
function markSelfWrite(table, row){
  const k = rowKey(table, row);
  if(k.endsWith(':undefined')) return;
  _selfWrites.add(k);
  setTimeout(() => _selfWrites.delete(k), 5000);
}

// True while the user is mid-interaction and a re-render would destroy their work.
function stillInteracting(){
  const a = document.activeElement;
  if(a && a.matches('input, select, textarea, [contenteditable="true"]')) return true;
  return currentPanelId !== null;
}

let _deferredReload = null;
function flushDeferredReload(){
  if(!_deferredReload || stillInteracting()) return;
  const fn = _deferredReload;
  _deferredReload = null;
  fn();
}
document.addEventListener('focusout', () => {
  // Let activeElement settle to the NEW target before testing it — on focusout
  // it is still transiently <body>, so an immediate check would report "not
  // interacting" while tabbing between two fields and stomp the user mid-edit.
  queueMicrotask(flushDeferredReload);
});

// Runs a realtime-triggered reload, or defers it until the user is idle.
function realtimeReload(fn){
  if(stillInteracting()){ _deferredReload = fn; return; }
  fn();
}
```

`currentPanelId` is declared later in the file with `let`, which would be a
temporal-dead-zone error if `stillInteracting()` ran before that declaration
was evaluated. It cannot: `stillInteracting()` is only ever called from a
realtime event or a `focusout`, both of which occur long after initial script
evaluation. Do not move this block below `subscribeRealtime`.

- [ ] **Step 2: Replace `subscribeRealtime` wholesale**

Find the entire existing `function subscribeRealtime(){ ... }` and replace with:

```javascript
function subscribeRealtime(){
  const channelName = 'db-changes-' + Math.random().toString(36).slice(2);
  console.log('[Realtime] subscribing on channel:', channelName);

  const handler = (table, reload, debounceRef) => (payload) => {
    const row = payload.new ?? payload.old;
    const k = rowKey(table, row);
    // Never drop an event we cannot identify — fall through to a reload.
    if(!k.endsWith(':undefined') && _selfWrites.has(k)){
      _selfWrites.delete(k);
      return;
    }
    clearTimeout(_debounce[debounceRef]);
    _debounce[debounceRef] = setTimeout(() => realtimeReload(reload), 400);
  };

  const pipeline = () => loadData({silent: true});
  const command  = () => loadCommandData({silent: true});

  db.channel(channelName)
    .on('postgres_changes', {event:'*', schema:'public', table:'projects'}, handler('projects', pipeline, '_realtimeDebounce'))
    .on('postgres_changes', {event:'*', schema:'public', table:'videos'},   handler('videos',   pipeline, '_realtimeDebounce'))
    .on('postgres_changes', {event:'*', schema:'public', table:'tasks'},    handler('tasks',    command,  '_cmdRealtimeDebounce'))
    .on('postgres_changes', {event:'*', schema:'public', table:'notes'},    handler('notes',    command,  '_cmdRealtimeDebounce'))
    .on('postgres_changes', {event:'*', schema:'public', table:'leads'},    handler('leads',    command,  '_cmdRealtimeDebounce'))
    .on('postgres_changes', {event:'*', schema:'public', table:'meta'},     handler('meta',     command,  '_cmdRealtimeDebounce'))
    .subscribe((status, err) => {
      console.log('[Realtime]', status, err || '');
      if(status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') toast('⚠ Live sync offline', true);
    });
}
```

The `toast('● Live')` line is gone (deleted in Task 3). The offline toast keeps
the `, true` added in Task 3.

- [ ] **Step 2b: Delete the now-dead debounce declarations**

The two timers now live in the `_debounce` object. Find and delete these two
lines, which sit just above `subscribeRealtime`:

```javascript
let _realtimeDebounce;
let _cmdRealtimeDebounce;
```

Confirm nothing else referenced them:

```bash
grep -c '_realtimeDebounce\|_cmdRealtimeDebounce' flushit-ops-hub.html
```

Expected: `2` — the two string literals `'_realtimeDebounce'` and
`'_cmdRealtimeDebounce'` passed to `handler()`. If this returns more, something
still reads the old bindings; do not proceed.

- [ ] **Step 3: Add the `silent` option to both loaders**

In `loadData`, find:

```javascript
async function loadData(){
  if(_loadDataInFlight) return;
  _loadDataInFlight = true;
  showLoading(true);
```

Replace with:

```javascript
async function loadData(opts = {}){
  if(_loadDataInFlight) return;
  _loadDataInFlight = true;
  if(!opts.silent) showLoading(true);
```

`showLoading(false)` on the exit paths can stay unconditional — hiding an overlay
that was never shown is a no-op, and leaving those calls alone avoids missing one
of the early-return branches.

Apply the identical treatment to `loadCommandData`: change its signature to
`async function loadCommandData(opts = {})` and guard its `showLoading(true)`
call with `if(!opts.silent)`.

- [ ] **Step 4: Mark self-writes in all 9 sync/delete functions**

Add a `markSelfWrite` call on the success path of each. The pattern for an upsert:

```javascript
async function syncProject(p){
  const { error } = await db.from('projects').upsert({
    /* ...existing fields, unchanged... */
  });
  if(error){ console.error('syncProject:', error); toast('⚠ Failed to save — check connection', true); return; }
  markSelfWrite('projects', p);
}
```

Note the added `return` in the error branch — without it, a failed write would
still mark a self-write and suppress a legitimate correcting echo.

Apply to each function with these exact arguments:

| Function | Call to add on success |
|---|---|
| `syncProject(p)` | `markSelfWrite('projects', p);` |
| `syncVideo(v, projId)` | `markSelfWrite('videos', v);` |
| `syncTask(t)` | `markSelfWrite('tasks', t);` |
| `deleteTask(id)` | `markSelfWrite('tasks', {id});` |
| `syncNote(n)` | `markSelfWrite('notes', n);` |
| `deleteNoteRow(id)` | `markSelfWrite('notes', {id});` |
| `syncLead(l)` | `markSelfWrite('leads', l);` |
| `deleteLeadRow(id)` | `markSelfWrite('leads', {id});` |
| `syncMeta(key, value)` | `markSelfWrite('meta', {key});` |

`syncMeta` takes `(key, value)` — not a row object — so construct `{key}`.
Likewise the three delete functions take a bare `id`.

`syncTask` returns a boolean and already has `return false` in its error branch;
keep that, and add `markSelfWrite('tasks', t);` before its existing
`return true`.

- [ ] **Step 5: Flush the deferred reload when a panel closes**

Find:

```javascript
function closePanel(){
  document.getElementById('panel').classList.remove('open');
  document.getElementById('panel-backdrop').classList.remove('open');
  currentPanelId = null;
}
```

Replace with:

```javascript
function closePanel(){
  document.getElementById('panel').classList.remove('open');
  document.getElementById('panel-backdrop').classList.remove('open');
  currentPanelId = null;
  flushDeferredReload();
}
```

`currentPanelId = null` must come **before** `flushDeferredReload()`, or
`stillInteracting()` still sees the panel as open and the reload never runs.

- [ ] **Step 6: Verify**

```bash
cp flushit-ops-hub.html index.html
bash docs/superpowers/scripts/verify-polish.sh
```

Expected: sections **A, B, D, E, F** pass. Only C fails.

- [ ] **Step 7: Confirm the self-write wiring is complete**

```bash
grep -c 'markSelfWrite(' flushit-ops-hub.html
```

Expected: `10` — one definition plus the 9 sync/delete call sites.

- [ ] **Step 8: Commit**

```bash
git add flushit-ops-hub.html index.html
git commit -m "fix: stop the app re-rendering itself after every action

Supabase realtime echoed the user's own writes back, and every echo ran
loadData(): a full-screen loading overlay, a complete refetch of projects
and videos, and renderAll() across all eight views — 400ms after every
deadline edit, stage advance, or assignment. Nothing checked whether the
change originated locally. This was the reported 'constant refresh'.

Three changes:
- Self-echo suppression. sync*/delete* record a PK-keyed row token; the
  handler drops echoes matching one. PK_COL maps meta to `key` and the rest
  to `id`. Unidentifiable events fall through to a reload rather than being
  dropped.
- Realtime-triggered reloads are silent. The loading overlay is now reserved
  for the initial page load.
- Re-renders defer while the user is typing or has a panel open, flushing on
  focusout (after activeElement settles, so tabbing between fields does not
  flush) or on panel close.

Closes chip task_4473160f — realtime re-render stomping focused inputs."
```

---

## Task 5: Rename videos in production

Turns section C green.

**Files:**
- Modify: `flushit-ops-hub.html`
- Modify: `index.html` (via `cp`)

- [ ] **Step 1: Rename the function**

Find:

```javascript
async function saveDraftName(projId, vidId, name){
```

Replace with:

```javascript
async function saveVideoName(projId, vidId, name){
```

The body is unchanged. It never checked the `draft` flag — it was always general;
it was simply only ever called from the draft view.

- [ ] **Step 2: Update the existing draft call site**

Find (inside `renderPanelBody`):

```javascript
                    onchange="saveDraftName(${p.id},'${v.id}',this.value)"
                    onblur="saveDraftName(${p.id},'${v.id}',this.value)">
```

Replace with:

```javascript
                    onchange="saveVideoName(${p.id},'${v.id}',this.value)"
                    onblur="saveVideoName(${p.id},'${v.id}',this.value)">
```

- [ ] **Step 3: Add the click-to-edit handler**

Insert immediately **below** the `saveVideoName` function:

```javascript
function beginRenameVideo(el, projId, vidId){
  if(el.querySelector('input')) return;
  const current = el.textContent;
  const input = document.createElement('input');
  input.className = 'v-name-edit';
  input.value = current;
  let done = false;
  const finish = (commit) => {
    if(done) return;
    done = true;
    const next = input.value.trim();
    el.textContent = (commit && next) ? next : current;
    if(commit && next && next !== current) saveVideoName(projId, vidId, next);
  };
  input.onkeydown = (e) => {
    if(e.key === 'Enter'){ e.preventDefault(); finish(true); }
    if(e.key === 'Escape'){ e.preventDefault(); finish(false); }
  };
  input.onblur = () => finish(true);
  el.textContent = '';
  el.appendChild(input);
  input.focus();
  input.select();
}
```

The `done` latch matters: pressing Enter calls `finish(true)` and then the
resulting blur fires `finish(true)` again. Without the latch the second call
would read an already-cleared input and revert the name that was just committed.

Reverting to `current` on an empty value mirrors the existing
`if(!v || !name.trim()) return;` guard in `saveVideoName`, so an empty commit is
a visual no-op rather than a silent divergence between the DOM and the database.

- [ ] **Step 4: Make the production video name clickable**

In `videoRowHTML(p, v)`, find:

```javascript
      <span class="v-name">${v.name}</span>
```

Replace with:

```javascript
      <span class="v-name editable" title="Click to rename" onclick="beginRenameVideo(this,${p.id},'${v.id}')">${v.name}</span>
```

- [ ] **Step 5: Add the styles**

Find:

```css
.v-name{font-size:13px;font-weight:500;color:var(--text);flex:1}
```

(`13px` — Task 2 remapped this from `11px`.)

Add immediately after it:

```css
.v-name.editable{cursor:text;border-radius:3px;padding:1px 3px;margin:-1px -3px}
.v-name.editable:hover{background:var(--s2)}
.v-name-edit{width:100%;font-family:inherit;font-size:13px;font-weight:500;color:var(--text);background:var(--surface);border:1px solid var(--purple);border-radius:3px;padding:0 2px;outline:none}
```

- [ ] **Step 6: Verify**

```bash
cp flushit-ops-hub.html index.html
bash docs/superpowers/scripts/verify-polish.sh
```

Expected: **ALL CHECKS PASSED**, exit 0.

- [ ] **Step 7: Commit**

```bash
git add flushit-ops-hub.html index.html
git commit -m "feat: rename videos that are already in production

saveDraftName() already renamed any video and never checked the draft flag
— it was simply never wired into videoRowHTML(), so a video's name froze
the moment its project reached production. Renamed to saveVideoName() to
match what it always did.

Production rows get click-to-edit: click the name, Enter or blur commits,
Escape reverts, empty reverts. No role gating; available at every stage.
Click-to-edit rather than an always-live input keeps the dense list quiet,
and avoids a permanently-focusable field for realtime to stomp."
```

---

## Task 6: Browser verification

Static checks cannot see a loading overlay flash or a stomped input. This task is
the one that actually proves the reported problems are fixed.

**Files:** none modified (verification only)

- [ ] **Step 1: Serve a copy from the scratchpad**

Desktop TCC restrictions block serving from `~/Desktop` directly.

```bash
SP=/private/tmp/claude-501/-Users-saroshahmed/16786b9a-eeae-47ad-a50a-3f61bd65d344/scratchpad
mkdir -p "$SP/serve" && cp index.html "$SP/serve/index.html"
cd "$SP/serve" && python3 -m http.server 8899 &
```

Note: a stale `node serve.mjs` may already hold port 4173 from a previous
session. Use 8899 to avoid it.

- [ ] **Step 2: Log in**

Navigate to `http://localhost:8899/index.html`. Log in with code `bebatzai`
(Sarosh, admin).

Playwright's `.press('Enter')` does not fire the login `onkeydown` handler — call
`doLogin()` directly via `browser_evaluate` instead. `doLogout()` clears the
stored code.

- [ ] **Step 3: Verify legibility**

```javascript
getComputedStyle(document.querySelector('.hs-l')).color
```

Expected: `rgb(117, 114, 112)` (`#757270`).

```javascript
[...document.querySelectorAll('*')]
  .map(e => parseFloat(getComputedStyle(e).fontSize))
  .filter(s => s > 0 && s < 11).length
```

Expected: `0`.

- [ ] **Step 4: Verify the self-echo fix — the headline check**

Open a project panel, change a video deadline, and watch `#loading-ov`.

```javascript
window.__ovShown = 0;
new MutationObserver(() => {
  if(!document.getElementById('loading-ov').classList.contains('hidden')) window.__ovShown++;
}).observe(document.getElementById('loading-ov'), {attributes:true, attributeFilter:['class']});
```

Change a deadline, wait 2s, then read `window.__ovShown`.

Expected: `0`. Before this change it would be ≥1 on every single edit.

- [ ] **Step 5: Verify the interaction guard**

Open two browser sessions. In session A, focus a text field in an open project
panel and type without blurring. In session B, change a different project.

Expected: session A's typed text survives and the field keeps focus. On blurring
in session A, session B's change appears.

- [ ] **Step 6: Verify rename round-trip**

Click a production video's name, type a new one, press Enter. Reload the page.

Expected: the new name persists. Then confirm Escape reverts, and that committing
an empty value reverts rather than blanking the name.

Also confirm the rename propagates: with a second session open, a rename in one
appears in the other without a loading overlay.

- [ ] **Step 7: Verify failure is visible**

With DevTools set to offline, edit a deadline.

Expected: `⚠ Failed to save — check connection` appears and **stays** — still
present after 5s, dismissable by clicking `×`. Then go online and confirm a
validation error (submit the new-project form with an empty name) still
auto-dismisses after ~2.8s.

- [ ] **Step 8: Regression suite**

These all passed on v2 and must still pass:

- Pipeline: advance a project through stages; move one back as Sarosh.
- Videos: assign an editor, submit for QC, mark a client revision, delete.
- Capture: press `c`, capture a note, confirm it survives a reload (this is the
  path Task 3 Step 6c could have broken).
- Inbox: sort a capture to a client, confirm it files to Research and survives a
  reload (the path Step 6d could have broken).
- Won lead: mark a lead won with `&` and `'` in the name; confirm client tags and
  the Research round-trip.
- Weekly focus: edit it, confirm it saves and does **not** re-render per keystroke
  (this is the `meta`/`PK_COL` fix — the bug that a uniform `table:id` key would
  have left in place).
- Editor gating: log out, log in as `tanzeel`, confirm non-admins land on Projects.

- [ ] **Step 9: Stop the server and commit any fixes**

```bash
pkill -f "http.server 8899"
```

If any check failed, fix it, re-run `verify-polish.sh`, and commit with a message
naming the specific failure. If everything passed, there is nothing to commit —
report the results.

---

## Self-review notes

**Spec coverage.** Section A → Task 2. Section B → Task 2. Section C → Task 5.
Section D (D1/D2/D3) → Task 4 Steps 1–5. Section E → Task 3. Testing section →
Task 1 (static) + Task 6 (browser). Deployment note → not a task; it constrains
the merge, see below.

**Deliberately not done.** Option C (surgical per-row DOM patching), the
`--td`/`--tm` merge, and optimistic-write rollback are all follow-ups recorded in
the spec, not tasks here.

**Not covered by any task, by design:** the spec's deployment note. This branch
sits on 10 unpushed commits on `main` (`be354b3..0e6c0e1`). Merging and pushing
deploys those too. `2026-07-15-enable-rls-authenticated.sql` must **not** be run
in the Supabase dashboard until the separate code-login work is finished. Raise
this with Sarosh at merge time rather than deciding it inside a task.
