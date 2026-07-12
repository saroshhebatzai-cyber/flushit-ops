-- Code-login migration (2026-07-13): the app now gates access with per-person
-- codes (TEAM[].code) instead of Supabase Auth, so all app tables must be
-- reachable with the anon key. tasks/notes/leads/meta already had RLS disabled
-- (2026-07-12-command-tables.sql); this brings projects/videos in line.
-- Run in the Supabase dashboard SQL editor.
alter table projects disable row level security;
alter table videos disable row level security;
