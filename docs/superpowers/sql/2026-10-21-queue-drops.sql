-- 2026-10-21-queue-drops.sql
-- Queue drops build: adds the "With client" stage and the time a video was sent.
--   * new column videos.sent_at (when a video went to the client; drives the 48h chase note)
--   * video stages renumbered: 0 Edit · 1 QC · 2 Sarosh Review · 3 With client · 4 Approved & sent
--     Existing "Delivered" videos (old stage 3) become Approved & sent (4).
-- Safe to run more than once: the renumber only happens the first time,
-- in the same step that adds the sent_at column.
-- Run this BEFORE publishing the new page.

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'videos' and column_name = 'sent_at'
  ) then
    alter table public.videos add column sent_at timestamptz;
    update public.videos set stage = 4 where stage = 3;
  end if;
end $$;
