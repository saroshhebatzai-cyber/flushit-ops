-- Content Agent: tables, seed, notes migration, daily-drop cron.
-- Run the whole file once in the Supabase SQL editor (project kdfwrjjbpfoweokofjdq).

create table if not exists content_briefs (
  client      text primary key,
  positioning text not null default '',
  audience    text not null default '',
  pillars     jsonb not null default '[]'::jsonb,
  tone        text not null default '',
  cadence     int  not null default 3,
  notes       text not null default '',
  updated_at  timestamptz not null default now()
);

create table if not exists content_ideas (
  id            text primary key,
  client        text not null,
  title         text not null default '',
  angle         text not null default '',
  pillar        text not null default '',
  format        text not null default '',
  status        text not null default 'proposed',  -- proposed | banked | scheduled | killed
  scheduled_for date,
  source        text not null default 'agent',     -- agent | capture | research | manual
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- App convention: no RLS (code login), realtime on, full replica identity.
alter table content_briefs disable row level security;
alter table content_ideas  disable row level security;
alter table content_briefs replica identity full;
alter table content_ideas  replica identity full;
alter publication supabase_realtime add table content_briefs;
alter publication supabase_realtime add table content_ideas;

-- Seed: Bebatzai brief with the old OS pillars (4 raw & real : 1 shaped ≈ 5/week).
insert into content_briefs (client, positioning, audience, pillars, tone, cadence, notes)
values (
  'Bebatzai',
  'Personal brand — shoot it, don''t think it. 4x raw & real (phone, same day, no polish) : 1x has a shape (series, story with a spine).',
  '',
  '["People","My World","Meaningful","Bebatzai Talks","Ammi Series","Ramadan/Eid"]'::jsonb,
  'Raw, personal, unpolished on the 4s; intentional on the 1s.',
  5,
  ''
) on conflict (client) do nothing;

-- One-time: fold existing Research notes into the idea bank.
insert into content_ideas (id, client, title, angle, status, source, created_at, updated_at)
select 'ci_note_' || id, client, title, body, 'banked', 'research', created_at, updated_at
from notes
on conflict (id) do nothing;

-- Daily drop: 06:00 PKT = 01:00 UTC. pg_net posts to the edge function.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.unschedule('content-agent-drop')
  where exists (select 1 from cron.job where jobname = 'content-agent-drop');
select cron.schedule(
  'content-agent-drop',
  '0 1 * * *',
  $$
  select net.http_post(
    url     := 'https://kdfwrjjbpfoweokofjdq.supabase.co/functions/v1/content-agent',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtkZndyampicGZvd2Vva29mamRxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4NjEwNjEsImV4cCI6MjA4OTQzNzA2MX0.LrkuoAo9g0WJ3dpq9CEHsE1dHmaKadcE21n6GinpgA8',
      'x-agent-token', 'fefa2ac2c65cfab6a16d8304'
    ),
    body    := '{"action":"drop"}'::jsonb
  );
  $$
);
