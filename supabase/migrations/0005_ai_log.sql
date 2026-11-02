-- ═══════════════════════════════════════════════════════════════════════════
-- 0005 · What happened on each photo-recognition try (model, HTTP, time).
-- Written only by the product-ai Edge Function; read by the diagnose workflow.
-- Kept 14 days.
-- ═══════════════════════════════════════════════════════════════════════════
create table public.ai_log (
  id       bigint generated always as identity primary key,
  user_id  uuid references auth.users(id) on delete cascade,
  at       timestamptz not null default now(),
  model    text not null,
  status   int not null,
  ms       int not null,
  bytes    int,
  note     text check (char_length(note) <= 300)
);
create index on public.ai_log (at desc);
alter table public.ai_log enable row level security;   -- no policies: not visible to the app
revoke all on public.ai_log from anon, authenticated;

create or replace function public.ai_log_cleanup() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.ai_log where at < now() - interval '14 days';
  return null;
end $$;
create trigger cleanup after insert on public.ai_log
  for each statement execute function public.ai_log_cleanup();
revoke execute on function public.ai_log_cleanup() from public, anon, authenticated;
