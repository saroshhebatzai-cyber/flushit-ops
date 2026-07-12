# Flush It Command Center Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an admin-only "Command" section (Capture+Inbox, Today, My Week, Research, Leads) to the existing Ops Hub, replacing Flush It OS, the Edit Tracker, and Apple Notes work-capture.

**Architecture:** All code goes into the existing single file `flushit-ops-hub.html` (~2,828 lines), following its established conventions: plain JS, camelCase state objects mapped to snake_case Supabase columns, `await`ed upserts with error toasts, per-session realtime channel, role gating via `isAdmin()`. Four new Supabase tables (`tasks`, `notes`, `leads`, `meta`). New views render only for admins; team-facing tabs untouched.

**Tech Stack:** Single HTML file, vanilla JS, Supabase JS v2 (CDN), Supabase Postgres + Realtime, GitHub Pages deploy.

**Spec:** `docs/superpowers/specs/2026-07-12-command-center-design.md`

**Branch:** Work on branch `command-center` (repo main deploys to the live team tool via `index.html`). Merge to main + deploy per slice only after its verification steps pass.

**Testing note:** This project is a zero-dependency single HTML file with no test runner; the established verification pattern is manual browser checks. Every task therefore ends with exact manual verification steps (expected DOM/console/Supabase results) instead of unit tests. The cross-cutting reliability tests (two-session sync, editor-login gating, offline toast) are in Task 10.

**Reference line numbers** are against the file as of commit `a4d785d`. They will drift as tasks land — every edit is anchored to a named function or section comment, which is authoritative.

---

### Task 1: Create Supabase tables

**Files:**
- Create: `docs/superpowers/sql/2026-07-12-command-tables.sql` (kept for the record; executed by hand)

- [ ] **Step 1: Write the migration SQL**

```sql
-- Command Center tables. Matches conventions of existing projects/videos tables:
-- text ids generated client-side, RLS not enabled (anon key, app-level gating),
-- tables added to the supabase_realtime publication with REPLICA IDENTITY FULL.

create table if not exists tasks (
  id            text primary key,
  title         text not null,
  notes         text,
  owner_id      int  not null default 1,
  assignee_id   int,
  client        text,
  status        text not null default 'open',   -- open | in_progress | done | cancelled
  scheduled_for date,
  created_at    timestamptz not null default now(),
  completed_at  timestamptz
);

create table if not exists notes (
  id         text primary key,
  client     text not null,
  title      text not null default '',
  body       text not null default '',
  pinned     boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists leads (
  id         text primary key,
  name       text not null,
  contact    text,
  source     text,
  stage      text not null default 'new',  -- new | discovery_scheduled | research | proposal | won | lost
  meeting_at timestamptz,
  notes      text,
  created_at timestamptz not null default now()
);

create table if not exists meta (
  key   text primary key,
  value jsonb
);

alter table tasks  replica identity full;
alter table notes  replica identity full;
alter table leads  replica identity full;
alter table meta   replica identity full;

alter publication supabase_realtime add table tasks;
alter publication supabase_realtime add table notes;
alter publication supabase_realtime add table leads;
alter publication supabase_realtime add table meta;
```

- [ ] **Step 2: Run it**

Open https://supabase.com/dashboard → project `kdfwrjjbpfoweokofjdq` → SQL Editor → paste → Run.
Expected: `Success. No rows returned`.

- [ ] **Step 3: Verify tables + realtime**

In SQL Editor run:

```sql
select tablename from pg_publication_tables where pubname = 'supabase_realtime' order by 1;
```

Expected: list contains `leads, meta, notes, projects, tasks, videos`.

- [ ] **Step 4: Commit the SQL file**

```bash
git checkout -b command-center
git add docs/superpowers/sql/2026-07-12-command-tables.sql
git commit -m "feat: add Command Center tables (tasks, notes, leads, meta)"
```

---

### Task 2: Command nav, empty views, role gating, CSS

**Files:**
- Modify: `flushit-ops-hub.html` — nav block (~line 489), `.main` tab divs (~line 510), `applyRoleGating()` (~line 2800), `switchTab()` (~line 2445), end of `<style>` block

- [ ] **Step 1: Add Command CSS at the end of the `<style>` block** (just before `</style>`)

```css
/* ─── COMMAND CENTER ─── */
.cmd-sep{width:1px;height:18px;background:var(--border);margin:0 4px}
.cmd-two-col{display:grid;grid-template-columns:1.25fr 1fr;gap:16px;align-items:start}
.cmd-col-hdr{font-family:var(--mono);font-size:10px;letter-spacing:.12em;color:var(--td);text-transform:uppercase;margin-bottom:8px}
.person-card{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);padding:12px 14px;margin-bottom:10px}
.person-card-hdr{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}
.person-card-name{font-weight:700;font-size:13px}
.person-card-meta{font-family:var(--mono);font-size:10px;color:var(--tm)}
.loop-row{display:flex;align-items:center;gap:8px;padding:5px 0;border-top:1px dashed var(--border);font-size:12px}
.loop-status{font-family:var(--mono);font-size:9px;padding:2px 7px;border-radius:9px;cursor:pointer;border:1px solid var(--border);background:var(--s2);color:var(--tm);white-space:nowrap}
.loop-status.inprog{color:var(--yellow);border-color:var(--yellow)}
.loop-title{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.loop-client{font-family:var(--mono);font-size:9px;color:var(--cyan)}
.loop-age{font-family:var(--mono);font-size:9px;color:var(--td);white-space:nowrap}
.loop-del{background:none;border:none;color:var(--td);cursor:pointer;font-size:12px;padding:0 2px}
.loop-del:hover{color:var(--red)}
.pipe-row{display:flex;align-items:center;gap:8px;padding:4px 0;font-size:11px;color:var(--tm);border-top:1px dashed var(--border)}
.pipe-row .ov{color:var(--red)}
.cmd-add-row{display:flex;gap:6px;margin-top:8px}
.cmd-add-input{flex:1;font-family:var(--mono);font-size:11px;padding:6px 9px;background:var(--s2);border:1px solid var(--border);border-radius:var(--rs);color:var(--text)}
.cmd-add-btn{font-family:var(--mono);font-size:11px;padding:6px 10px;background:var(--adim);color:var(--accent);border:1px solid var(--accent);border-radius:var(--rs);cursor:pointer}
.needs-card{background:var(--rdim);border:1px solid var(--red);border-radius:var(--r);padding:12px 14px;margin-bottom:10px}
.needs-row{display:flex;gap:8px;align-items:center;font-size:12px;padding:5px 0;cursor:pointer}
.needs-row:hover{color:var(--accent)}
.stream-card{background:var(--surface);border:1px dashed var(--b2);border-radius:var(--r);padding:12px 14px;margin-bottom:10px}
.inbox-row{display:flex;gap:6px;align-items:center;padding:5px 0;border-top:1px dashed var(--border);font-size:12px;flex-wrap:wrap}
.inbox-sel{font-family:var(--mono);font-size:10px;padding:3px 6px;background:var(--s2);border:1px solid var(--border);border-radius:var(--rs);color:var(--tm)}
#capture-input{font-family:var(--mono);font-size:11px;padding:6px 10px;width:210px;background:var(--s2);border:1px solid var(--border);border-radius:var(--rs);color:var(--text)}
#capture-input:focus{border-color:var(--accent);outline:none}
.week-day{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);padding:10px 14px;margin-bottom:8px}
.week-day.today-hl{border-color:var(--accent)}
.week-day-hdr{display:flex;justify-content:space-between;font-family:var(--mono);font-size:10px;color:var(--tm);margin-bottom:4px}
.week-focus{background:var(--s2);border:1px solid var(--border);border-radius:var(--r);padding:12px 16px;margin-bottom:14px}
.week-focus-label{font-family:var(--mono);font-size:9px;letter-spacing:.12em;color:var(--td);text-transform:uppercase}
.week-focus-text{font-size:14px;font-weight:600;margin-top:4px;outline:none;min-height:20px}
.note-card{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);padding:12px 14px;margin-bottom:10px}
.note-title{width:100%;background:transparent;border:none;color:var(--text);font-weight:700;font-size:13px;outline:none;margin-bottom:6px}
.note-body{width:100%;background:transparent;border:none;color:var(--tm);font-size:12px;line-height:1.5;outline:none;resize:vertical;min-height:60px;font-family:inherit}
.client-subtab{font-family:var(--mono);font-size:11px;padding:5px 12px;background:var(--s2);border:1px solid var(--border);border-radius:14px;color:var(--tm);cursor:pointer;margin:0 6px 6px 0}
.client-subtab.active{background:var(--adim);color:var(--accent);border-color:var(--accent)}
.lead-card{background:var(--surface);border:1px solid var(--border);border-radius:var(--r);padding:12px 14px;margin-bottom:10px;display:grid;grid-template-columns:2fr 1.5fr 1.2fr 1fr auto;gap:10px;align-items:center;font-size:12px}
@media(max-width:900px){.cmd-two-col{grid-template-columns:1fr}.lead-card{grid-template-columns:1fr 1fr}}
```

- [ ] **Step 2: Add Command nav buttons** — in the `<nav class="nav">` block (~line 489), after the Queue button:

```html
    <span class="cmd-sep" id="cmd-sep" style="display:none"></span>
    <button class="nav-btn cmd-nav" id="nav-today" style="display:none" onclick="switchTab('today',this)">Today</button>
    <button class="nav-btn cmd-nav" id="nav-week" style="display:none" onclick="switchTab('week',this)">My Week</button>
    <button class="nav-btn cmd-nav" id="nav-research" style="display:none" onclick="switchTab('research',this)">Research</button>
    <button class="nav-btn cmd-nav" id="nav-leads" style="display:none" onclick="switchTab('leads',this)">Leads</button>
```

- [ ] **Step 3: Add capture input to the header** — immediately after the `</nav>` closing tag, before the `btn-new-project` button:

```html
  <input id="capture-input" style="display:none" placeholder="＋ capture… (c)"
         onkeydown="if(event.key==='Enter')captureTask()" />
```

- [ ] **Step 4: Add the four empty tab divs** — inside `<div class="main">`, after the `tab-efficiency` div's closing tag:

```html
  <div class="tab" id="tab-today">
    <div class="sec-hdr"><div class="sec-title" id="today-title">Today</div></div>
    <div class="cmd-two-col">
      <div><div class="cmd-col-hdr">People</div><div id="today-people"></div></div>
      <div>
        <div class="cmd-col-hdr">Needs You</div><div id="today-needs"></div>
        <div class="cmd-col-hdr" style="margin-top:14px">Streams</div><div id="today-streams"></div>
        <div class="cmd-col-hdr" style="margin-top:14px">Inbox</div><div id="today-inbox"></div>
      </div>
    </div>
  </div>
  <div class="tab" id="tab-week">
    <div class="sec-hdr">
      <div class="sec-title">My Week</div>
      <div class="cal-nav">
        <button class="cal-nav-btn" onclick="weekPrev()">←</button>
        <div class="cal-month-label" id="week-label"></div>
        <button class="cal-nav-btn" onclick="weekNext()">→</button>
      </div>
    </div>
    <div class="week-focus">
      <div class="week-focus-label">This week</div>
      <div class="week-focus-text" id="week-focus-text" contenteditable="true" spellcheck="false"
           onblur="saveWeekFocus()">Click to set your weekly focus…</div>
    </div>
    <div id="week-days"></div>
    <div class="sec-hdr" style="margin-top:18px"><div class="sec-title" style="font-size:13px">Parking Lot</div>
      <div style="font-size:10px;color:var(--td)">Tasks without a day — same list as the Today inbox</div></div>
    <div id="week-parking"></div>
  </div>
  <div class="tab" id="tab-research">
    <div class="sec-hdr"><div class="sec-title">Research</div>
      <button class="cmd-add-btn" onclick="addNote()">+ New Note</button></div>
    <div id="research-subtabs"></div>
    <div id="research-notes"></div>
  </div>
  <div class="tab" id="tab-leads">
    <div class="sec-hdr"><div class="sec-title">Leads</div>
      <button class="cmd-add-btn" onclick="addLead()">+ New Lead</button></div>
    <div id="leads-list"></div>
  </div>
```

- [ ] **Step 5: Gate it all by admin** — replace the body of `applyRoleGating()` (~line 2800):

```js
function applyRoleGating(){
  const admin = isAdmin();
  // Efficiency tab — admins only
  document.getElementById('nav-efficiency').style.display = admin ? '' : 'none';
  // New Project button — admins only
  document.getElementById('btn-new-project').style.display = admin ? '' : 'none';
  // Command section — admins only
  document.getElementById('cmd-sep').style.display = admin ? '' : 'none';
  document.getElementById('capture-input').style.display = admin ? '' : 'none';
  document.querySelectorAll('.cmd-nav').forEach(b => b.style.display = admin ? '' : 'none');
}
```

- [ ] **Step 6: Guard and route in `switchTab()`** (~line 2445) — add after the efficiency guard line:

```js
  const CMD_TABS = ['today','week','research','leads'];
  if(CMD_TABS.includes(name) && !isAdmin()){ toast('⚠ Access restricted'); return; }
```

and at the end of the function (after the existing `if(name === 'queue')` line):

```js
  if(name === 'today') renderToday();
  if(name === 'week') renderWeek();
  if(name === 'research') renderResearch();
  if(name === 'leads') renderLeads();
```

- [ ] **Step 7: Add temporary stub renderers** so the file runs before Tasks 4–9 land. Add a new section after the `// ─── NAV ───` section:

```js
// ─── COMMAND CENTER ──────────────────────────────────────────────────────────
function renderToday(){}
function renderWeek(){}
function renderResearch(){}
function renderLeads(){}
function captureTask(){}
function weekPrev(){}
function weekNext(){}
function saveWeekFocus(){}
function addNote(){}
function addLead(){}
```

- [ ] **Step 8: Verify in browser**

Open `flushit-ops-hub.html` directly (file://), log in as `sarosh.hebatzai@gmail.com`.
Expected: nav shows `Projects Clients Team Efficiency Calendar Queue │ Today My Week Research Leads`, capture box visible in header, clicking each new tab shows its (empty) section headers, zero console errors, existing tabs unchanged.

- [ ] **Step 9: Commit**

```bash
git add flushit-ops-hub.html
git commit -m "feat: Command nav, empty views, capture input, admin gating"
```

---

### Task 3: Command data layer (state, load, sync, realtime)

**Files:**
- Modify: `flushit-ops-hub.html` — state block (~line 719), after `syncVideo()` (~line 781), `subscribeRealtime()` (~line 784), `onSignedIn()` (~line 2783)

- [ ] **Step 1: Add state + id helper** — below `let currentUser = null;`:

```js
let tasks = [];   // Command Center
let notes = [];
let leads = [];
let metaKV = {};  // key → value (jsonb)
function newCmdId(prefix){ return prefix + Date.now() + '_' + Math.random().toString(36).slice(2,7); }
```

- [ ] **Step 2: Add load + sync functions** — after `syncVideo()`:

```js
// ─── COMMAND DATA LAYER ───────────────────────────────────────────────────────
async function loadCommandData(){
  if(!isAdmin()) return;
  const [t, n, l, m] = await Promise.all([
    db.from('tasks').select('*').order('created_at'),
    db.from('notes').select('*').order('updated_at', {ascending:false}),
    db.from('leads').select('*').order('created_at'),
    db.from('meta').select('*'),
  ]);
  if(t.error || n.error || l.error || m.error){
    console.error(t.error||n.error||l.error||m.error);
    toast('⚠ Failed to load command data'); return;
  }
  tasks = (t.data||[]).map(r => ({
    id:r.id, title:r.title, notes:r.notes||'', ownerId:r.owner_id,
    assigneeId:r.assignee_id, client:r.client, status:r.status,
    scheduledFor:r.scheduled_for, createdAt:r.created_at, completedAt:r.completed_at
  }));
  notes = (n.data||[]).map(r => ({
    id:r.id, client:r.client, title:r.title, body:r.body,
    pinned:r.pinned, createdAt:r.created_at, updatedAt:r.updated_at
  }));
  leads = (l.data||[]).map(r => ({
    id:r.id, name:r.name, contact:r.contact||'', source:r.source||'',
    stage:r.stage, meetingAt:r.meeting_at, notes:r.notes||'', createdAt:r.created_at
  }));
  metaKV = {};
  (m.data||[]).forEach(r => metaKV[r.key] = r.value);
  renderCommand();
}

function renderCommand(){
  const active = document.querySelector('.tab.active')?.id;
  if(active === 'tab-today') renderToday();
  if(active === 'tab-week') renderWeek();
  if(active === 'tab-research') renderResearch();
  if(active === 'tab-leads') renderLeads();
}

async function syncTask(t){
  const { error } = await db.from('tasks').upsert({
    id:t.id, title:t.title, notes:t.notes||null, owner_id:t.ownerId,
    assignee_id:t.assigneeId, client:t.client, status:t.status,
    scheduled_for:t.scheduledFor, created_at:t.createdAt, completed_at:t.completedAt
  });
  if(error){ console.error('syncTask:', error); toast('⚠ Failed to save — check connection'); }
}
async function deleteTask(id){
  const { error } = await db.from('tasks').delete().eq('id', id);
  if(error){ console.error('deleteTask:', error); toast('⚠ Failed to delete — check connection'); }
}
async function syncNote(n){
  const { error } = await db.from('notes').upsert({
    id:n.id, client:n.client, title:n.title, body:n.body,
    pinned:n.pinned, created_at:n.createdAt, updated_at:new Date().toISOString()
  });
  if(error){ console.error('syncNote:', error); toast('⚠ Failed to save — check connection'); }
}
async function deleteNoteRow(id){
  const { error } = await db.from('notes').delete().eq('id', id);
  if(error){ console.error('deleteNoteRow:', error); toast('⚠ Failed to delete — check connection'); }
}
async function syncLead(l){
  const { error } = await db.from('leads').upsert({
    id:l.id, name:l.name, contact:l.contact||null, source:l.source||null,
    stage:l.stage, meeting_at:l.meetingAt, notes:l.notes||null, created_at:l.createdAt
  });
  if(error){ console.error('syncLead:', error); toast('⚠ Failed to save — check connection'); }
}
async function deleteLeadRow(id){
  const { error } = await db.from('leads').delete().eq('id', id);
  if(error){ console.error('deleteLeadRow:', error); toast('⚠ Failed to delete — check connection'); }
}
async function syncMeta(key, value){
  metaKV[key] = value;
  const { error } = await db.from('meta').upsert({ key, value });
  if(error){ console.error('syncMeta:', error); toast('⚠ Failed to save — check connection'); }
}
```

- [ ] **Step 3: Extend realtime** — inside `subscribeRealtime()`, after the existing `videos` `.on(...)` block, add (same debounce pattern; one shared handler):

```js
    .on('postgres_changes', {event:'*', schema:'public', table:'tasks'}, () => {
      clearTimeout(_cmdRealtimeDebounce);
      _cmdRealtimeDebounce = setTimeout(loadCommandData, 400);
    })
    .on('postgres_changes', {event:'*', schema:'public', table:'notes'}, () => {
      clearTimeout(_cmdRealtimeDebounce);
      _cmdRealtimeDebounce = setTimeout(loadCommandData, 400);
    })
    .on('postgres_changes', {event:'*', schema:'public', table:'leads'}, () => {
      clearTimeout(_cmdRealtimeDebounce);
      _cmdRealtimeDebounce = setTimeout(loadCommandData, 400);
    })
    .on('postgres_changes', {event:'*', schema:'public', table:'meta'}, () => {
      clearTimeout(_cmdRealtimeDebounce);
      _cmdRealtimeDebounce = setTimeout(loadCommandData, 400);
    })
```

and declare `let _cmdRealtimeDebounce;` next to the existing `let _realtimeDebounce;`.

- [ ] **Step 4: Load on sign-in** — in `onSignedIn()`, after `await loadData();` add:

```js
  await loadCommandData();
```

- [ ] **Step 5: Verify in browser**

Log in as Sarosh. In DevTools console run:

```js
await syncTask({id:newCmdId('t'), title:'smoke test', ownerId:1, assigneeId:null, client:null, status:'open', scheduledFor:null, createdAt:new Date().toISOString(), completedAt:null});
await loadCommandData(); tasks.length
```

Expected: no error toast, `tasks.length` ≥ 1. In Supabase Table Editor, row visible in `tasks`. Then clean up: `await deleteTask(tasks[0].id)`.

- [ ] **Step 6: Commit**

```bash
git add flushit-ops-hub.html
git commit -m "feat: Command data layer — tasks/notes/leads/meta load, sync, realtime"
```

---

### Task 4: Capture + Inbox (Slice 1 — replaces Apple Notes)

**Files:**
- Modify: `flushit-ops-hub.html` — replace `captureTask()` stub and add inbox rendering + `c` shortcut in the `// ─── COMMAND CENTER ───` section

- [ ] **Step 1: Implement capture + shortcut** — replace the `captureTask(){}` stub:

```js
async function captureTask(){
  const input = document.getElementById('capture-input');
  const title = input.value.trim();
  if(!title) return;
  const t = { id:newCmdId('t'), title, notes:'', ownerId:currentUser.id, assigneeId:null,
              client:null, status:'open', scheduledFor:null,
              createdAt:new Date().toISOString(), completedAt:null };
  tasks.push(t);
  input.value = '';
  await syncTask(t);
  toast('✓ Captured');
  renderCommand();
}

document.addEventListener('keydown', e => {
  if(e.key !== 'c' || e.metaKey || e.ctrlKey || e.altKey) return;
  if(!isAdmin()) return;
  const tag = document.activeElement?.tagName;
  if(tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || document.activeElement?.isContentEditable) return;
  e.preventDefault();
  document.getElementById('capture-input').focus();
});
```

- [ ] **Step 2: Add inbox helpers + renderer** (same section):

```js
const inboxTasks = () => tasks.filter(t => t.status !== 'done' && t.status !== 'cancelled'
  && !t.assigneeId && !t.scheduledFor && !t.client);
const openLoops = id => tasks.filter(t => t.assigneeId === id && t.status !== 'done' && t.status !== 'cancelled');

function allClientNames(){
  const fromProjects = projects.map(p => p.client);
  const fromLeads = leads.filter(l => l.stage === 'won').map(l => l.name);
  return [...new Set([...fromProjects, ...fromLeads])].sort();
}

function relAge(iso){
  const mins = Math.round((Date.now() - new Date(iso)) / 60000);
  if(mins < 60) return mins + 'm';
  if(mins < 1440) return Math.round(mins/60) + 'h';
  return Math.round(mins/1440) + 'd';
}

function inboxRowHtml(t){
  const clientOpts = allClientNames().map(c => `<option ${t.client===c?'selected':''}>${c}</option>`).join('');
  const teamOpts = TEAM.filter(m => m.id !== currentUser.id)
    .map(m => `<option value="${m.id}">${m.name}</option>`).join('');
  return `<div class="inbox-row">
    <span class="loop-title">${escHtml(t.title)}</span>
    <span class="loop-age">${relAge(t.createdAt)}</span>
    <select class="inbox-sel" onchange="sortInbox('${t.id}','client',this.value)">
      <option value="">client…</option>${clientOpts}</select>
    <select class="inbox-sel" onchange="sortInbox('${t.id}','assignee',this.value)">
      <option value="">assign…</option>${teamOpts}</select>
    <input type="date" class="inbox-sel" onchange="sortInbox('${t.id}','schedule',this.value)">
    <button class="loop-del" title="Done" onclick="setTaskStatus('${t.id}','done')">✓</button>
    <button class="loop-del" title="Delete" onclick="removeTask('${t.id}')">×</button>
  </div>`;
}

function escHtml(s){ return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;'); }

async function sortInbox(id, field, value){
  const t = tasks.find(x => x.id === id); if(!t || !value) return;
  if(field === 'client') t.client = value;
  if(field === 'assignee') t.assigneeId = parseInt(value);
  if(field === 'schedule') t.scheduledFor = value;
  await syncTask(t);
  renderCommand();
  toast('✓ Sorted');
}

async function setTaskStatus(id, status){
  const t = tasks.find(x => x.id === id); if(!t) return;
  t.status = status;
  t.completedAt = (status === 'done') ? new Date().toISOString() : null;
  await syncTask(t);
  renderCommand();
}

async function removeTask(id){
  tasks = tasks.filter(x => x.id !== id);
  await deleteTask(id);
  renderCommand();
}
```

- [ ] **Step 3: Minimal `renderToday()`** — replace the stub (full version comes in Task 5; this makes Slice 1 usable):

```js
function renderToday(){
  document.getElementById('today-title').textContent =
    '☀️ ' + today.toLocaleDateString('en-GB',{weekday:'long',day:'numeric',month:'short'});
  const inbox = inboxTasks();
  document.getElementById('today-inbox').innerHTML = `<div class="stream-card">
    ${inbox.length ? inbox.map(inboxRowHtml).join('') : '<div style="font-size:11px;color:var(--td)">Inbox zero ✓</div>'}
  </div>`;
}
```

- [ ] **Step 4: Verify in browser**

Log in as Sarosh → press `c` (focus jumps to capture box) → type `ivs shoot prep` → Enter.
Expected: "✓ Captured" toast. Open Today tab: row shows title + age + client/assign/date controls. Pick a client → row leaves inbox ("✓ Sorted"). Refresh page → state persists (Supabase, not localStorage). `✓` completes, `×` deletes.

- [ ] **Step 5: Commit**

```bash
git add flushit-ops-hub.html
git commit -m "feat: capture box, c shortcut, inbox with sort controls (slice 1)"
```

---

### Task 5: Today view — people cards, needs-you, streams (Slice 2)

**Files:**
- Modify: `flushit-ops-hub.html` — extend `renderToday()` and add card builders in the Command section. Add `CPC_SHEET_URL` constant near `VERSION` (~line 699).

- [ ] **Step 1: Add config constant** — next to `const VERSION = 'v1.0';`:

```js
const CPC_SHEET_URL = ''; // Ayesha's Cpc Google Sheet — paste the share URL here
```

(Ask Sarosh for the real URL during implementation; empty string hides the link.)

- [ ] **Step 2: Add card builders** (Command section):

```js
function allVideosFlat(){
  return projects.flatMap(p => p.videos.map(v => ({...v, projClient:p.client, projName:p.name, projId:p.id})));
}

function personCardHtml(m){
  const loops = openLoops(m.id);
  const loopHtml = loops.map(t => `<div class="loop-row">
    <span class="loop-status ${t.status==='in_progress'?'inprog':''}"
      onclick="setTaskStatus('${t.id}','${t.status==='open'?'in_progress':'done'}')">${t.status==='in_progress'?'IN PROG':'OPEN'}</span>
    <span class="loop-title">${escHtml(t.title)}</span>
    ${t.client?`<span class="loop-client">${escHtml(t.client)}</span>`:''}
    <span class="loop-age">asked ${relAge(t.createdAt)} ago</span>
    <button class="loop-del" onclick="removeTask('${t.id}')">×</button>
  </div>`).join('');

  let liveHtml = '';
  if(m.isEditor){
    const vids = allVideosFlat().filter(v => v.assigneeId === m.id && v.stage < 3 && !v.draft);
    liveHtml = vids.map(v => {
      const od = v.deadline && daysFromNow(v.deadline) < 0;
      return `<div class="pipe-row">🎬 <span class="loop-title">${escHtml(v.name)}</span>
        <span class="${od?'ov':''}">${VIDEO_STAGES[v.stage]}${od?' · overdue':''}</span></div>`;
    }).join('') || '<div class="pipe-row" style="color:var(--td)">no active edits</div>';
  }
  if(m.id === 7){ // Arsal — next shoot
    const upcoming = projects.filter(p => p.shootDate && daysFromNow(p.shootDate) >= 0)
      .sort((a,b) => new Date(a.shootDate) - new Date(b.shootDate))[0];
    liveHtml += `<div class="pipe-row">📸 ${upcoming
      ? `Next shoot: ${escHtml(upcoming.client)} — ${new Date(upcoming.shootDate).toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short'})}`
      : 'No shoot scheduled'}</div>`;
  }
  const sheetLink = (m.id === 3 && CPC_SHEET_URL)
    ? `<a href="${CPC_SHEET_URL}" target="_blank" style="font-family:var(--mono);font-size:9px;color:var(--cyan)">📊 Cpc sheet ↗</a>` : '';

  return `<div class="person-card">
    <div class="person-card-hdr">
      <span class="person-card-name">${m.name}</span>
      <span class="person-card-meta">${loops.length} open ${sheetLink}</span>
    </div>
    ${liveHtml}${loopHtml}
    <div class="cmd-add-row">
      <input class="cmd-add-input" id="loop-add-${m.id}" placeholder="Ask ${m.name.split(' ')[0]}…"
        onkeydown="if(event.key==='Enter')addLoop(${m.id})">
      <button class="cmd-add-btn" onclick="addLoop(${m.id})">+</button>
    </div>
  </div>`;
}

async function addLoop(memberId){
  const input = document.getElementById('loop-add-' + memberId);
  const title = input.value.trim(); if(!title) return;
  const t = { id:newCmdId('t'), title, notes:'', ownerId:currentUser.id, assigneeId:memberId,
              client:null, status:'open', scheduledFor:null,
              createdAt:new Date().toISOString(), completedAt:null };
  tasks.push(t); input.value = '';
  await syncTask(t);
  renderToday();
}

function needsYouHtml(){
  const items = [];
  allVideosFlat().filter(v => v.stage === 2 && !v.draft).forEach(v =>
    items.push({icon:'🔴', label:`${v.projClient} · ${v.name} — your review`, go:"switchTab('queue',document.querySelector('.nav-btn:nth-child(6)'))"}));
  projects.filter(p => p.stage === 4).forEach(p =>
    items.push({icon:'🔴', label:`${p.client} · ${p.name} — approval to shoot`, go:"switchTab('projects',document.querySelector('.nav-btn:nth-child(1)'))"}));
  tasks.filter(t => t.assigneeId === currentUser.id && t.status !== 'done' && t.status !== 'cancelled').forEach(t =>
    items.push({icon:'🟡', label:escHtml(t.title), go:''}));
  const todayStr = new Date().toDateString();
  leads.filter(l => l.meetingAt && new Date(l.meetingAt).toDateString() === todayStr).forEach(l =>
    items.push({icon:'📅', label:`${escHtml(l.name)} — meeting today`, go:"switchTab('leads',document.getElementById('nav-leads'))"}));
  if(!items.length) return '<div class="stream-card" style="font-size:11px;color:var(--td)">Nothing blocked on you ✓</div>';
  return `<div class="needs-card">${items.map(i =>
    `<div class="needs-row" ${i.go?`onclick="${i.go}"`:''}>${i.icon} ${i.label}</div>`).join('')}</div>`;
}

function streamsHtml(){
  const active = allVideosFlat().filter(v => v.stage < 3 && !v.draft);
  const overdue = active.filter(v => v.deadline && daysFromNow(v.deadline) < 0).length;
  const openLeads = leads.filter(l => !['won','lost'].includes(l.stage));
  const nextMeet = leads.filter(l => l.meetingAt && new Date(l.meetingAt) >= new Date())
    .sort((a,b) => new Date(a.meetingAt) - new Date(b.meetingAt))[0];
  return `
  <div class="stream-card" style="cursor:pointer" onclick="switchTab('queue',document.querySelector('.nav-btn:nth-child(6)'))">
    <b>Edits</b> — ${active.length} active${overdue?` · <span style="color:var(--red)">${overdue} overdue</span>`:''}</div>
  <div class="stream-card" style="cursor:pointer" onclick="switchTab('leads',document.getElementById('nav-leads'))">
    <b>Leads</b> — ${openLeads.length} open${nextMeet?` · next: ${escHtml(nextMeet.name)} ${new Date(nextMeet.meetingAt).toLocaleDateString('en-GB',{weekday:'short'})}`:''}</div>`;
}
```

- [ ] **Step 3: Full `renderToday()`** — replace the Task-4 minimal version:

```js
function renderToday(){
  document.getElementById('today-title').textContent =
    '☀️ ' + today.toLocaleDateString('en-GB',{weekday:'long',day:'numeric',month:'short'});
  document.getElementById('today-people').innerHTML =
    TEAM.filter(m => m.id !== currentUser.id).map(personCardHtml).join('');
  document.getElementById('today-needs').innerHTML = needsYouHtml();
  document.getElementById('today-streams').innerHTML = streamsHtml();
  const inbox = inboxTasks();
  document.getElementById('today-inbox').innerHTML = `<div class="stream-card">
    ${inbox.length ? inbox.map(inboxRowHtml).join('') : '<div style="font-size:11px;color:var(--td)">Inbox zero ✓</div>'}
  </div>`;
}
```

- [ ] **Step 4: Keep Today fresh on pipeline changes** — in `renderAll()` (~line 1000), append to the chain:

```js
if(document.querySelector('.tab.active')?.id === 'tab-today') renderToday();
```

- [ ] **Step 5: Verify in browser**

Today tab shows: one card per team member (Ayesha, Tanzeel, Osama, Kabeer, Arsal). Editors' cards list their active edits with correct stage labels from the pipeline (cross-check against Queue tab). Arsal's card shows the next shoot date (cross-check Calendar). Type into "Ask Tanzeel…" → Enter → loop appears with "asked 0m ago" + OPEN pill; click pill → IN PROG; click again → row disappears (done). Move a video to Sarosh Review in the Queue → Needs You shows it. Streams count matches Queue.

- [ ] **Step 6: Commit**

```bash
git add flushit-ops-hub.html
git commit -m "feat: Today view — people cards, needs-you, streams (slice 2)"
```

---

### Task 6: My Week (Slice 3)

**Files:**
- Modify: `flushit-ops-hub.html` — replace `renderWeek()`, `weekPrev()`, `weekNext()`, `saveWeekFocus()` stubs in the Command section

- [ ] **Step 1: Implement**

```js
let weekOffset = 0; // 0 = this week

function weekMonday(offset){
  const d = new Date(); const dow = d.getDay();
  d.setDate(d.getDate() - (dow === 0 ? 6 : dow - 1) + offset*7);
  d.setHours(0,0,0,0); return d;
}
// Local-date ISO (NOT toISOString — that converts to UTC and shifts the day
// backwards before 5am PKT)
function isoDate(d){
  return d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0');
}

function weekPrev(){ weekOffset--; renderWeek(); }
function weekNext(){ weekOffset++; renderWeek(); }

function renderWeek(){
  const mon = weekMonday(weekOffset);
  const sun = new Date(mon); sun.setDate(mon.getDate() + 6);
  const fmt = d => d.toLocaleDateString('en-GB',{day:'numeric',month:'short'});
  document.getElementById('week-label').textContent =
    (weekOffset === 0 ? 'This week · ' : '') + `${fmt(mon)} – ${fmt(sun)}`;

  const focusKey = 'week_focus_' + isoDate(mon);
  const focusEl = document.getElementById('week-focus-text');
  focusEl.textContent = metaKV[focusKey] || 'Click to set your weekly focus…';
  focusEl.dataset.key = focusKey;

  const todayIso = isoDate(new Date());
  let html = '';
  for(let i = 0; i < 7; i++){
    const day = new Date(mon); day.setDate(mon.getDate() + i);
    const iso = isoDate(day);
    const dayTasks = tasks.filter(t => t.scheduledFor === iso && t.status !== 'cancelled');
    html += `<div class="week-day ${iso === todayIso ? 'today-hl' : ''}">
      <div class="week-day-hdr">
        <span>${day.toLocaleDateString('en-GB',{weekday:'long'})}</span><span>${fmt(day)}</span>
      </div>
      ${dayTasks.map(t => `<div class="loop-row">
        <input type="checkbox" ${t.status==='done'?'checked':''}
          onchange="setTaskStatus('${t.id}','${t.status==='done'?'open':'done'}')">
        <span class="loop-title" style="${t.status==='done'?'text-decoration:line-through;color:var(--td)':''}">${escHtml(t.title)}</span>
        ${t.client?`<span class="loop-client">${escHtml(t.client)}</span>`:''}
        <button class="loop-del" onclick="removeTask('${t.id}')">×</button>
      </div>`).join('')}
      <div class="cmd-add-row">
        <input class="cmd-add-input" id="week-add-${iso}" placeholder="Add…"
          onkeydown="if(event.key==='Enter')addWeekTask('${iso}')">
        <button class="cmd-add-btn" onclick="addWeekTask('${iso}')">+</button>
      </div>
    </div>`;
  }
  document.getElementById('week-days').innerHTML = html;
  const parking = inboxTasks();
  document.getElementById('week-parking').innerHTML = `<div class="stream-card">
    ${parking.length ? parking.map(inboxRowHtml).join('') : '<div style="font-size:11px;color:var(--td)">Parking lot empty ✓</div>'}
  </div>`;
}

async function addWeekTask(iso){
  const input = document.getElementById('week-add-' + iso);
  const title = input.value.trim(); if(!title) return;
  const t = { id:newCmdId('t'), title, notes:'', ownerId:currentUser.id, assigneeId:null,
              client:null, status:'open', scheduledFor:iso,
              createdAt:new Date().toISOString(), completedAt:null };
  tasks.push(t); input.value = '';
  await syncTask(t);
  renderWeek();
}

async function saveWeekFocus(){
  const el = document.getElementById('week-focus-text');
  const text = el.textContent.trim();
  if(text === 'Click to set your weekly focus…') return;
  await syncMeta(el.dataset.key, text);
  toast('✓ Focus saved');
}
```

- [ ] **Step 2: Verify in browser**

My Week shows Mon–Sun with today highlighted. Add a task under Tuesday → appears; checkbox strikes it through; Supabase `tasks` row has `scheduled_for` set. Set week focus text, click elsewhere → "✓ Focus saved", survives refresh. ←/→ navigate weeks; each week has its own focus. Parking Lot mirrors the Today inbox; scheduling a parked item from its date input moves it into a day.

- [ ] **Step 3: Commit**

```bash
git add flushit-ops-hub.html
git commit -m "feat: My Week — day planner, week focus, parking lot (slice 3)"
```

---

### Task 7: Research view (Slice 4a)

**Files:**
- Modify: `flushit-ops-hub.html` — replace `renderResearch()` and `addNote()` stubs

- [ ] **Step 1: Implement**

```js
let researchClient = null; // active subtab

function renderResearch(){
  const clients = [...new Set([...allClientNames(), ...notes.map(n => n.client)])].sort();
  if(!researchClient || !clients.includes(researchClient)) researchClient = clients[0] || null;
  document.getElementById('research-subtabs').innerHTML = clients.map(c =>
    `<button class="client-subtab ${c===researchClient?'active':''}"
      onclick="researchClient='${escHtml(c)}';renderResearch()">${escHtml(c)}
      <span style="opacity:.5">${notes.filter(n=>n.client===c).length}</span></button>`).join('')
    || '<div style="font-size:11px;color:var(--td)">No clients yet — add a note to create one.</div>';

  const list = notes.filter(n => n.client === researchClient)
    .sort((a,b) => (b.pinned - a.pinned) || (new Date(b.updatedAt) - new Date(a.updatedAt)));
  document.getElementById('research-notes').innerHTML = list.map(n => `<div class="note-card">
    <div style="display:flex;justify-content:space-between;align-items:center">
      <input class="note-title" value="${escHtml(n.title)}" placeholder="Note title…"
        onblur="updateNote('${n.id}','title',this.value)">
      <span>
        <button class="loop-del" title="Pin" style="${n.pinned?'color:var(--yellow)':''}"
          onclick="togglePin('${n.id}')">📌</button>
        <button class="loop-del" onclick="removeNote('${n.id}')">×</button>
      </span>
    </div>
    <textarea class="note-body" placeholder="Research, links, angles…"
      onblur="updateNote('${n.id}','body',this.value)">${escHtml(n.body)}</textarea>
    <div class="loop-age">updated ${relAge(n.updatedAt)} ago</div>
  </div>`).join('') || (researchClient ? '<div style="font-size:11px;color:var(--td)">No notes yet for this client.</div>' : '');
}

async function addNote(){
  let client = researchClient;
  const typed = prompt('Client for this note:', client || '');
  if(typed === null) return;
  client = typed.trim() || client;
  if(!client){ toast('⚠ Note needs a client'); return; }
  const n = { id:newCmdId('n'), client, title:'', body:'', pinned:false,
              createdAt:new Date().toISOString(), updatedAt:new Date().toISOString() };
  notes.unshift(n); researchClient = client;
  await syncNote(n);
  renderResearch();
}

async function updateNote(id, field, value){
  const n = notes.find(x => x.id === id); if(!n) return;
  if(n[field] === value) return;
  n[field] = value; n.updatedAt = new Date().toISOString();
  await syncNote(n);
}

async function togglePin(id){
  const n = notes.find(x => x.id === id); if(!n) return;
  n.pinned = !n.pinned;
  await syncNote(n);
  renderResearch();
}

async function removeNote(id){
  if(!confirm('Delete this note?')) return;
  notes = notes.filter(x => x.id !== id);
  await deleteNoteRow(id);
  renderResearch();
}
```

- [ ] **Step 2: Verify in browser**

Research tab shows a subtab per known client (from projects) with note counts. + New Note → prompt for client → card with title + body appears; typing then clicking away persists (check Supabase `notes`). Pin moves a note to the top (yellow pin). Delete asks for confirmation. Adding a note for a brand-new client name creates its subtab.

- [ ] **Step 3: Commit**

```bash
git add flushit-ops-hub.html
git commit -m "feat: Research view — per-client notes with pin (slice 4a)"
```

---

### Task 8: Leads view (Slice 4b)

**Files:**
- Modify: `flushit-ops-hub.html` — replace `renderLeads()` and `addLead()` stubs

- [ ] **Step 1: Implement**

```js
// Stored UTC ISO → value string for <input type="datetime-local"> in the
// browser's local timezone (slicing the raw ISO would show UTC time)
function toLocalDT(iso){
  const d = new Date(iso);
  return isoDate(d) + 'T' + String(d.getHours()).padStart(2,'0') + ':' + String(d.getMinutes()).padStart(2,'0');
}

const LEAD_STAGES = [
  {key:'new',                 label:'New'},
  {key:'discovery_scheduled', label:'Discovery Scheduled'},
  {key:'research',            label:'Research'},
  {key:'proposal',            label:'Proposal'},
  {key:'won',                 label:'Won ✓'},
  {key:'lost',                label:'Lost'},
];

function renderLeads(){
  const order = Object.fromEntries(LEAD_STAGES.map((s,i) => [s.key, i]));
  const list = [...leads].sort((a,b) => order[a.stage] - order[b.stage] || new Date(b.createdAt) - new Date(a.createdAt));
  document.getElementById('leads-list').innerHTML = list.map(l => `<div class="lead-card"
      style="${l.stage==='won'?'border-color:var(--accent)':''}${l.stage==='lost'?'opacity:.45':''}">
    <div>
      <input class="note-title" value="${escHtml(l.name)}" onblur="updateLead('${l.id}','name',this.value)">
      <input class="cmd-add-input" style="width:100%" value="${escHtml(l.contact)}" placeholder="contact…"
        onblur="updateLead('${l.id}','contact',this.value)">
    </div>
    <textarea class="note-body" style="min-height:36px" placeholder="notes…"
      onblur="updateLead('${l.id}','notes',this.value)">${escHtml(l.notes)}</textarea>
    <select class="inbox-sel" onchange="setLeadStage('${l.id}',this.value)">
      ${LEAD_STAGES.map(s => `<option value="${s.key}" ${l.stage===s.key?'selected':''}>${s.label}</option>`).join('')}
    </select>
    <input type="datetime-local" class="inbox-sel" value="${l.meetingAt ? toLocalDT(l.meetingAt) : ''}"
      onchange="updateLead('${l.id}','meetingAt',this.value ? new Date(this.value).toISOString() : null)">
    <button class="loop-del" onclick="removeLead('${l.id}')">×</button>
  </div>`).join('') || '<div style="font-size:11px;color:var(--td)">No leads yet. + New Lead when one lands.</div>';
}

async function addLead(){
  const name = prompt('Lead name (person or company):'); if(!name?.trim()) return;
  const l = { id:newCmdId('l'), name:name.trim(), contact:'', source:'', stage:'new',
              meetingAt:null, notes:'', createdAt:new Date().toISOString() };
  leads.unshift(l);
  await syncLead(l);
  renderLeads();
}

async function updateLead(id, field, value){
  const l = leads.find(x => x.id === id); if(!l) return;
  if(l[field] === value) return;
  l[field] = value;
  await syncLead(l);
  if(field === 'meetingAt') renderLeads();
}

async function setLeadStage(id, stage){
  const l = leads.find(x => x.id === id); if(!l) return;
  l.stage = stage;
  await syncLead(l);
  if(stage === 'won') toast(`🎉 ${l.name} is now a client — available as a tag everywhere`);
  renderLeads();
}

async function removeLead(id){
  if(!confirm('Delete this lead?')) return;
  leads = leads.filter(x => x.id !== id);
  await deleteLeadRow(id);
  renderLeads();
}
```

- [ ] **Step 2: Verify in browser**

+ New Lead → prompt → card appears with name/contact/notes/stage/meeting controls, persisted to Supabase. Set stage Won → toast fires, card gets accent border, and the lead's name now appears in: inbox client dropdowns and Research subtabs (that's the `allClientNames()` union doing the conversion). Set a meeting for today → it appears in Today's Needs You and the Leads stream card.

- [ ] **Step 3: Commit**

```bash
git add flushit-ops-hub.html
git commit -m "feat: Leads view — stages, meetings, won→client tag (slice 4b)"
```

---

### Task 9: Land Today as Sarosh's landing tab

**Files:**
- Modify: `flushit-ops-hub.html` — `onSignedIn()` (~line 2783)

- [ ] **Step 1: Route admins to Today after sign-in** — in `onSignedIn()`, after `subscribeRealtime();` add:

```js
  if(isAdmin()) switchTab('today', document.getElementById('nav-today'));
```

- [ ] **Step 2: Verify**

Sign out, sign in as Sarosh → lands on Today. Sign in as an editor (or ask Tanzeel) → lands on Projects as before.

- [ ] **Step 3: Commit**

```bash
git add flushit-ops-hub.html
git commit -m "feat: admins land on Today after sign-in"
```

---

### Task 10: Reliability + gating verification, merge, deploy

**Files:**
- Modify: `index.html` (deploy copy)

- [ ] **Step 1: Two-session sync test**

Open the app in two browser windows (both as Sarosh). In window 1 capture a task.
Expected: within ~1s window 2's inbox shows it (realtime). Complete it in window 2 → disappears in window 1.

- [ ] **Step 2: Editor gating test**

Log in as an editor account in a private window.
Expected: no Command nav buttons, no capture box, no separator. Manually calling `switchTab('today')` in console shows "⚠ Access restricted" toast. Projects/Queue/Team/Calendar behave exactly as production.

- [ ] **Step 3: Offline failure test**

DevTools → Network → Offline. Capture a task.
Expected: "⚠ Failed to save — check connection" toast (no silent loss). Back online → capture again → succeeds.

- [ ] **Step 4: Regression pass on team features**

As Sarosh: create a test project, advance Brief → Ideation, add a video, assign it, move it to QC, then delete the test project. Expected: identical behavior to production, no console errors.

- [ ] **Step 5: Merge and deploy**

```bash
git checkout main
git merge command-center
cp flushit-ops-hub.html index.html
git add flushit-ops-hub.html index.html
git commit -m "release: Command Center (capture, today, my week, research, leads)"
git push origin main
```

Wait ~30s, open https://saroshhebatzai-cyber.github.io/flushit-ops/index.html, sign in, confirm Today loads.

---

### Task 11: Retire Flush It OS

**Files:**
- Modify: `~/Downloads/flushit-os/index.html` (separate repo)

- [ ] **Step 1: Add redirect banner** — in the flushit-os repo, immediately after `<body>`:

```html
<div style="position:fixed;top:0;left:0;right:0;z-index:9999;background:#00FF88;color:#060810;
  font-family:monospace;font-size:13px;font-weight:700;text-align:center;padding:10px">
  Flush It OS has moved into the Ops Hub →
  <a href="https://saroshhebatzai-cyber.github.io/flushit-ops/index.html" style="color:#060810;text-decoration:underline">
    open the new Command Center</a>
</div>
```

- [ ] **Step 2: Commit + push in that repo**

```bash
cd ~/Downloads/flushit-os
git add index.html
git commit -m "chore: redirect banner — OS retired in favor of Ops Hub Command Center"
git push origin main
```

- [ ] **Step 3: Archive**

After a week of the banner (no complaints): GitHub → `flushit-os` → Settings → Archive repository. The Edit Tracker HTML in Downloads needs no action — it simply stops being opened.

---

## Coverage map (spec → tasks)

| Spec requirement | Task |
|---|---|
| tasks/notes/leads tables, realtime | 1, 3 |
| Admin-only Command section | 2, 10 |
| Capture + `c` + Inbox | 4 |
| Today two-column: people cards, live editor data, Arsal shoot, Ayesha sheet link | 5 |
| Needs You (computed) | 5 |
| My Week + week focus + parking lot | 6 (meta table: 1) |
| Research per-client notes | 7 |
| Leads pipeline, won→client tag | 8 |
| Sarosh lands on Today | 9 |
| Reliability rules verification, deploy | 10 |
| Retire Flush It OS / Edit Tracker | 11 |
