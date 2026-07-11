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
