# Video Queue Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Video Queue tab to the Flush It Ops Hub — a flat cross-project view of all videos grouped by client, with per-video client due dates and ops-set internal deadlines, enabling rolling post-production assignment.

**Architecture:** Single HTML file modification. New `clientDueDate` field added to video data model (Supabase + JS). New Queue tab renders all videos flat, grouped by client. Inline editing of internal deadline and assignee directly in the queue row. No structural changes to existing project/kanban flow.

**Tech Stack:** Vanilla JS, HTML/CSS, Supabase JS v2 (`kdfwrjjbpfoweokofjdq.supabase.co`), single file at `/Users/saroshahmed/Desktop/flushit/flushit-ops-hub.html`

---

## Chunk 1: Data Model

### Task 1: Supabase migration — add `client_due_date` to videos

**Files:**
- No file change — run SQL in Supabase dashboard

- [ ] **Step 1: Run migration in Supabase SQL editor**

```sql
alter table videos add column if not exists client_due_date date default null;
```

- [ ] **Step 2: Verify column exists**

In Supabase Table Editor → videos → confirm `client_due_date` column appears.

---

### Task 2: Wire `clientDueDate` into JS data layer

**Files:**
- Modify: `flushit-ops-hub.html` — `loadData()` at line ~669, `syncVideo()` at line ~694

- [ ] **Step 1: Add `clientDueDate` to video mapping in `loadData()`**

Find this block (line ~671):
```js
stage: v.stage, deadline: v.deadline, revisions: v.revisions, clientRevs: v.client_revisions||0,
```

Add `clientDueDate` after `deadline`:
```js
stage: v.stage, deadline: v.deadline, clientDueDate: v.client_due_date||null, revisions: v.revisions, clientRevs: v.client_revisions||0,
```

- [ ] **Step 2: Add `client_due_date` to `syncVideo()`**

Find (line ~697):
```js
assignee_id: v.assigneeId, stage: v.stage, deadline: v.deadline,
```

Change to:
```js
assignee_id: v.assigneeId, stage: v.stage, deadline: v.deadline, client_due_date: v.clientDueDate||null,
```

- [ ] **Step 3: Add `clientDueDate: null` to new video creation in `createProject()`**

Find where new video objects are created (search for `id:'v'+nextVidId`):
```js
const v = {id:'v'+nextVidId++, name:..., ..., deadline:p.deadline, revisions:0, deliveredAt:null, ...};
```

Add `clientDueDate: null` to the object.

- [ ] **Step 4: Verify — open hub, advance a video, check Supabase videos table that `client_due_date` column is present (null is fine)**

---

## Chunk 2: Video Queue Tab — Structure & CSS

### Task 3: Add Queue tab to nav and HTML

**Files:**
- Modify: `flushit-ops-hub.html` — nav section (~line 458), tab divs (~line 523)

- [ ] **Step 1: Add Queue nav button**

Find the nav buttons block:
```html
<button class="nav-btn" onclick="switchTab('calendar',this)">Calendar</button>
```

Add after it:
```html
<button class="nav-btn" onclick="switchTab('queue',this)">Queue</button>
```

- [ ] **Step 2: Add Queue tab div**

Find the Calendar tab div (`<div class="tab" id="tab-calendar">`). Add a new tab div immediately before it:
```html
<div class="tab" id="tab-queue">
  <div class="sec-hdr">
    <div class="sec-title">Video Queue</div>
    <div style="display:flex;gap:8px;align-items:center">
      <select id="queue-sort" onchange="renderQueue()" style="font-family:var(--mono);font-size:11px;padding:5px 10px;background:var(--s2);border:1px solid var(--border);border-radius:var(--rs);color:var(--tm);cursor:pointer">
        <option value="client-due">Sort: Client Due Date</option>
        <option value="internal">Sort: Internal Deadline</option>
        <option value="stage">Sort: Stage</option>
      </select>
      <select id="queue-filter-client" onchange="renderQueue()" style="font-family:var(--mono);font-size:11px;padding:5px 10px;background:var(--s2);border:1px solid var(--border);border-radius:var(--rs);color:var(--tm);cursor:pointer">
        <option value="">All Clients</option>
      </select>
    </div>
  </div>
  <div id="queue-body"></div>
</div>
```

- [ ] **Step 3: Add Queue CSS**

Add after the existing `/* MY STATS STRIP */` CSS block:

```css
/* VIDEO QUEUE */
.queue-client-group{margin-bottom:28px}
.queue-client-header{display:flex;align-items:center;gap:10px;margin-bottom:10px;padding-bottom:8px;border-bottom:1px solid var(--border)}
.queue-client-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0}
.queue-client-name{font-family:var(--display);font-size:13px;font-weight:700}
.queue-client-count{font-size:10px;color:var(--td)}
.queue-table{width:100%;border-collapse:collapse}
.queue-table th{font-size:9px;color:var(--td);text-transform:uppercase;letter-spacing:1px;padding:6px 10px;text-align:left;border-bottom:1px solid var(--border);white-space:nowrap}
.queue-row{border-bottom:1px solid rgba(28,40,64,.5);transition:background .12s}
.queue-row:hover{background:var(--s2)}
.queue-row.unstarted{opacity:.65}
.queue-row.unstarted:hover{opacity:1}
.queue-cell{padding:8px 10px;vertical-align:middle}
.queue-vid-name{font-size:11px;color:var(--text);font-weight:500}
.queue-vid-project{font-size:9px;color:var(--td);margin-top:1px}
.queue-date-input{background:transparent;border:none;border-bottom:1px dashed var(--border);color:var(--tm);font-family:var(--mono);font-size:11px;padding:2px 4px;cursor:pointer;width:100px;color-scheme:dark}
.queue-date-input:focus{outline:none;border-bottom-color:var(--accent);color:var(--text)}
.queue-date-input.set{color:var(--text);border-bottom-color:transparent}
.queue-date-input.set:hover{border-bottom-color:var(--border)}
.queue-buffer{font-size:10px;padding:2px 7px;border-radius:20px;font-weight:600;white-space:nowrap}
.queue-buffer.g{background:var(--adim);color:var(--accent);border:1px solid rgba(0,255,136,.25)}
.queue-buffer.y{background:var(--ydim);color:var(--yellow);border:1px solid rgba(255,184,0,.25)}
.queue-buffer.r{background:var(--rdim);color:var(--red);border:1px solid rgba(255,77,94,.25)}
.queue-buffer.d{background:var(--s2);color:var(--td);border:1px solid var(--border)}
.queue-assignee-select{background:transparent;border:none;border-bottom:1px dashed var(--border);color:var(--tm);font-family:var(--mono);font-size:11px;padding:2px 4px;cursor:pointer;max-width:110px}
.queue-assignee-select:focus{outline:none;border-bottom-color:var(--accent)}
.queue-assignee-select.set{color:var(--text);border-bottom-color:transparent}
.queue-assignee-select.set:hover{border-bottom-color:var(--border)}
.queue-stage-pill{font-size:9px;padding:2px 8px;border-radius:20px;font-weight:600;white-space:nowrap}
.queue-stage-pill.s0{background:var(--cdim);color:var(--cyan);border:1px solid rgba(0,212,255,.25)}
.queue-stage-pill.s1{background:var(--ydim);color:var(--yellow);border:1px solid rgba(255,184,0,.25)}
.queue-stage-pill.s2{background:var(--adim);color:var(--accent);border:1px solid rgba(0,255,136,.25)}
.queue-stage-pill.s3{background:var(--pdim);color:var(--purple);border:1px solid rgba(155,109,255,.25)}
.queue-stage-pill.unstarted{background:var(--s3);color:var(--td);border:1px solid var(--border)}
.queue-empty{text-align:center;padding:40px;color:var(--td);font-size:11px}
```

- [ ] **Step 4: Wire `renderQueue()` into `switchTab()`**

Find:
```js
if(name === 'calendar') renderCalendar();
```

Add after:
```js
if(name === 'queue') renderQueue();
```

Also add `renderQueue()` call to `renderAll()`:

Find:
```js
function renderAll(){ renderKanban(); renderClients(); renderTeam(); renderEfficiency(); renderCalendar(); updateStats(); }
```

Change to:
```js
function renderAll(){ renderKanban(); renderClients(); renderTeam(); renderEfficiency(); renderCalendar(); renderQueue(); updateStats(); }
```

---

## Chunk 3: Queue Render Logic

### Task 4: `renderQueue()` function

**Files:**
- Modify: `flushit-ops-hub.html` — add function before `// ─── INIT` section

- [ ] **Step 1: Add `renderQueue()` function**

Add the following before the `// ─── AUTH` section:

```js
// ─── VIDEO QUEUE ──────────────────────────────────────────────────────────────

function renderQueue(){
  const body = document.getElementById('queue-body');
  if(!body) return;

  const sortEl = document.getElementById('queue-sort');
  const filterEl = document.getElementById('queue-filter-client');
  const sortBy = sortEl ? sortEl.value : 'client-due';
  const filterClient = filterEl ? filterEl.value : '';

  // Populate client filter dropdown (once)
  const clients = [...new Set(projects.map(p => p.client))].sort();
  if(filterEl && filterEl.options.length <= 1){
    clients.forEach(c => {
      const opt = document.createElement('option');
      opt.value = c; opt.textContent = c;
      filterEl.appendChild(opt);
    });
  }

  // Flatten all non-draft videos across all projects
  let allVids = projects.flatMap(p =>
    p.videos.filter(v => !v.draft).map(v => ({ ...v, projectId: p.id, projectName: p.name, client: p.client }))
  );

  // Apply client filter
  if(filterClient) allVids = allVids.filter(v => v.client === filterClient);

  // Sort
  allVids.sort((a, b) => {
    if(sortBy === 'client-due'){
      if(!a.clientDueDate && !b.clientDueDate) return 0;
      if(!a.clientDueDate) return 1;
      if(!b.clientDueDate) return -1;
      return a.clientDueDate.localeCompare(b.clientDueDate);
    }
    if(sortBy === 'internal'){
      if(!a.deadline && !b.deadline) return 0;
      if(!a.deadline) return 1;
      if(!b.deadline) return -1;
      return a.deadline.localeCompare(b.deadline);
    }
    if(sortBy === 'stage') return a.stage - b.stage;
    return 0;
  });

  // Group by client
  const grouped = {};
  allVids.forEach(v => {
    if(!grouped[v.client]) grouped[v.client] = [];
    grouped[v.client].push(v);
  });

  if(allVids.length === 0){
    body.innerHTML = '<div class="queue-empty">No videos in queue. Create a project and add videos.</div>';
    return;
  }

  body.innerHTML = Object.entries(grouped).map(([client, vids]) => {
    const color = CLIENT_COLORS[client] || CLIENT_COLORS['default'];
    const rows = vids.map(v => renderQueueRow(v)).join('');
    return `<div class="queue-client-group">
      <div class="queue-client-header">
        <div class="queue-client-dot" style="background:${color};box-shadow:0 0 6px ${color}40"></div>
        <div class="queue-client-name">${client}</div>
        <div class="queue-client-count">${vids.length} video${vids.length>1?'s':''}</div>
      </div>
      <table class="queue-table">
        <thead>
          <tr>
            <th>Video</th>
            <th>Type</th>
            <th>Client Due</th>
            <th>Internal Deadline</th>
            <th>Buffer</th>
            <th>Assigned To</th>
            <th>Stage</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
  }).join('');
}

function renderQueueRow(v){
  const isUnstarted = !v.assigneeId && v.stage === 0;
  const stagePill = v.stage === 3
    ? `<span class="queue-stage-pill s3">Delivered</span>`
    : isUnstarted
    ? `<span class="queue-stage-pill unstarted">Unstarted</span>`
    : `<span class="queue-stage-pill s${v.stage}">${VIDEO_STAGES[v.stage]}</span>`;

  // Buffer calculation
  let bufferHtml = '<span class="queue-buffer d">—</span>';
  if(v.clientDueDate && v.deadline){
    const diff = Math.round((new Date(v.clientDueDate) - new Date(v.deadline)) / 86400000);
    const cls = diff >= 5 ? 'g' : diff >= 2 ? 'y' : 'r';
    const label = diff === 0 ? 'Same day' : diff > 0 ? `${diff}d buffer` : `${Math.abs(diff)}d late`;
    bufferHtml = `<span class="queue-buffer ${cls}">${label}</span>`;
  }

  // Client due date display
  const clientDueHtml = v.clientDueDate
    ? `<span style="font-size:11px;color:var(--text)">${new Date(v.clientDueDate).toLocaleDateString('en-GB',{day:'numeric',month:'short'})}</span>`
    : `<span style="font-size:10px;color:var(--td)">Not set</span>`;

  // Internal deadline — editable for admins only
  const internalDeadlineHtml = isAdmin()
    ? `<input type="date" class="queue-date-input${v.deadline?' set':''}" value="${v.deadline||''}"
        onchange="updateQueueDeadline('${v.projectId}','${v.id}',this.value)"
        style="color-scheme:dark" />`
    : v.deadline
    ? `<span style="font-size:11px;color:var(--text)">${new Date(v.deadline).toLocaleDateString('en-GB',{day:'numeric',month:'short'})}</span>`
    : `<span style="font-size:10px;color:var(--td)">Not set</span>`;

  // Assignee — editable for admins only
  const editors = TEAM.filter(t => t.isEditor);
  const assigneeHtml = isAdmin()
    ? `<select class="queue-assignee-select${v.assigneeId?' set':''}"
        onchange="updateQueueAssignee('${v.projectId}','${v.id}',this.value)">
        <option value="">Unassigned</option>
        ${editors.map(e => `<option value="${e.id}"${v.assigneeId===e.id?' selected':''}>${e.name}</option>`).join('')}
      </select>`
    : (() => {
        const editor = TEAM.find(t => t.id === v.assigneeId);
        return editor
          ? `<span style="font-size:11px;color:var(--text)">${editor.name}</span>`
          : `<span style="font-size:10px;color:var(--td)">Unassigned</span>`;
      })();

  return `<tr class="queue-row${isUnstarted?' unstarted':''}">
    <td class="queue-cell">
      <div class="queue-vid-name">${v.name}</div>
      <div class="queue-vid-project">${v.projectName}</div>
    </td>
    <td class="queue-cell"><span class="type-badge ${v.type}">${EDIT_TYPES[v.type].label}</span></td>
    <td class="queue-cell">${clientDueHtml}</td>
    <td class="queue-cell">${internalDeadlineHtml}</td>
    <td class="queue-cell">${bufferHtml}</td>
    <td class="queue-cell">${assigneeHtml}</td>
    <td class="queue-cell">${stagePill}</td>
  </tr>`;
}

async function updateQueueDeadline(projId, vidId, value){
  const p = projects.find(x => x.id === parseInt(projId) || x.id === projId);
  const v = p?.videos.find(x => x.id === vidId);
  if(!v) return;
  v.deadline = value || null;
  renderQueue();
  syncVideo(v, p.id);
}

async function updateQueueAssignee(projId, vidId, value){
  const p = projects.find(x => x.id === parseInt(projId) || x.id === projId);
  const v = p?.videos.find(x => x.id === vidId);
  if(!v) return;
  const editorId = value ? parseInt(value) : null;
  v.assigneeId = editorId;
  if(editorId) showWaPing(`${waTag(editorId)} 📋 *Assigned:* ${p.client} · ${v.name} (${EDIT_TYPES[v.type].label}) — due ${fmtDue(v.deadline)}`);
  renderQueue();
  syncVideo(v, p.id);
}
```

- [ ] **Step 2: Reload hub in browser, click Queue tab — verify it renders without JS errors**

---

## Chunk 4: Client Due Date on Video Creation

### Task 5: Add `clientDueDate` field to video creation in new project form

**Files:**
- Modify: `flushit-ops-hub.html` — new project modal and `createProject()` function

- [ ] **Step 1: Add `clientDueDate` input to the video rows in the edit plan section of the modal**

Find where video rows are rendered in the modal (search for `ep-row` or `editPlan`). In the function that renders edit plan rows, add a date input for client due date alongside each video row:

In the `addEditPlanRow()` function or wherever `ep-row` HTML is built, add after the type/count selects:
```html
<input type="date" class="ep-client-due" placeholder="Client due" style="color-scheme:dark;font-family:var(--mono);font-size:11px;padding:4px 8px;background:var(--s3);border:1px solid var(--border);border-radius:var(--rs);color:var(--tm)" />
```

- [ ] **Step 2: Read `clientDueDate` values when creating videos in `createProject()`**

Find the video creation loop in `createProject()` (search for `id:'v'+nextVidId`). For each video `i` within an edit plan row, read the client due date:

```js
// inside the loop that creates video objects:
const epRow = epRows[epIdx]; // the DOM row element
const clientDueInput = epRow?.querySelector('.ep-client-due');
const clientDueDate = clientDueInput?.value || null;
const v = {
  id:'v'+nextVidId++, name:`${EDIT_TYPES[ep.type].label} ${i}`, type:ep.type,
  assigneeId:null, stage:0, deadline:p.deadline, clientDueDate: clientDueDate,
  revisions:0, deliveredAt:null, startedAt:null, completedAt:null,
  actualHours:null, latencyScore:null, draft:false
};
```

- [ ] **Step 3: Include `clientDueDate` in the Supabase insert inside `createProject()`**

When inserting videos via `db.from('videos').insert(...)`, add `client_due_date: v.clientDueDate||null`.

- [ ] **Step 4: Verify — create a new project with 2 videos, set client due dates in the form, save. Open Queue tab and verify the client due dates appear.**

---

## Chunk 5: Polish & Role Gating

### Task 6: Queue tab role visibility + queue-specific touches

**Files:**
- Modify: `flushit-ops-hub.html` — `applyRoleGating()`, queue header display

- [ ] **Step 1: Queue tab visible to all users — verify nav button has no role gate**

The Queue tab should be visible to all users (editors need to see their assigned videos). Confirm no `isAdmin()` check blocks the Queue nav button.

- [ ] **Step 2: For limited users, hide the sort/filter controls and show only their own assigned videos**

In `renderQueue()`, after flattening all videos, add:
```js
// Limited users only see their assigned videos
if(!isAdmin() && currentUser){
  allVids = allVids.filter(v => v.assigneeId === currentUser.id);
}
```

- [ ] **Step 3: Add a summary line to the queue header showing total unstarted vs in-progress vs delivered counts**

In the Queue tab `sec-hdr`, after the title add a live stats strip (rendered by `renderQueue()`):
```js
const unstarted = allVids.filter(v => !v.assigneeId && v.stage === 0).length;
const inProg = allVids.filter(v => v.assigneeId && v.stage < 3).length;
const done = allVids.filter(v => v.stage === 3).length;
document.getElementById('queue-stats').textContent =
  `${unstarted} unstarted · ${inProg} in progress · ${done} delivered`;
```

Add `<span id="queue-stats" style="font-size:10px;color:var(--td)"></span>` to the queue sec-hdr.

- [ ] **Step 4: Final verification**

- Open hub as admin — Queue tab shows all videos across all projects, can edit deadlines and assignees inline
- Open hub as a limited user — Queue tab shows only their own assigned videos, no edit controls
- Sort by Client Due Date — videos without client due dates sink to bottom
- Buffer column shows green/yellow/red correctly based on gap between client due and internal deadline
- Assigning an editor from the queue fires a WA ping

---

## SQL Summary

Run these in Supabase SQL editor in order:

```sql
-- Task 1
alter table videos add column if not exists client_due_date date default null;
```
