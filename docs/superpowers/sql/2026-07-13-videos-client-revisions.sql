-- Fix: videos.client_revisions missing from live DB (discovered in Task 10 testing 2026-07-13).
-- syncVideo() has been sending client_revisions on every upsert; PostgREST rejects the whole
-- upsert with PGRST204/400, so NO video insert/update has ever persisted (videos table is empty
-- in production). This unblocks video tracking app-wide, including Today's editor cards.
alter table videos add column if not exists client_revisions integer default 0;
