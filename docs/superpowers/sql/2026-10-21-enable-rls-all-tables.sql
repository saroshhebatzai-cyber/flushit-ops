-- 2026-10-21-enable-rls-all-tables.sql
-- Turns database protection (Row Level Security) back on for every app table.
-- Logged-in sessions (via the `login` Edge Function) get full access; the
-- public anon key on its own gets nothing. Supersedes the "disable" migrations
-- of 2026-07-12, 2026-07-13 and 2026-07-19, and extends 2026-07-15 to the two
-- Content tables. Safe to run more than once.
-- Run LAST, after the login function works. Undo: run the disable lines at the bottom.

do $$
declare t text;
begin
  foreach t in array array['projects','videos','tasks','notes','leads','meta','content_briefs','content_ideas'] loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "authenticated full access" on public.%I;', t);
    execute format('create policy "authenticated full access" on public.%I for all to authenticated using (true) with check (true);', t);
  end loop;
end $$;

-- UNDO (only if something breaks): uncomment and run
-- do $$ declare t text; begin
--   foreach t in array array['projects','videos','tasks','notes','leads','meta','content_briefs','content_ideas'] loop
--     execute format('alter table public.%I disable row level security;', t);
--   end loop; end $$;
