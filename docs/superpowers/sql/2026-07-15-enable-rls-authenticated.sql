-- 2026-07-15-enable-rls-authenticated.sql
-- Re-enable Row Level Security on every app table. A single policy grants full
-- access to any authenticated session; the anon role gets no policy and is
-- therefore blocked from all rows. Supersedes 2026-07-13-code-login-rls.sql.
-- Rerunnable: drops the policy by name before recreating it.
-- Run in the Supabase dashboard SQL editor.

alter table projects enable row level security;
alter table videos   enable row level security;
alter table tasks    enable row level security;
alter table notes    enable row level security;
alter table leads    enable row level security;
alter table meta     enable row level security;

do $$
declare t text;
begin
  foreach t in array array['projects','videos','tasks','notes','leads','meta'] loop
    execute format('drop policy if exists "authenticated full access" on public.%I;', t);
    execute format('create policy "authenticated full access" on public.%I for all to authenticated using (true) with check (true);', t);
  end loop;
end $$;
