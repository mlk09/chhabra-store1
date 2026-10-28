-- ═══════════════════════════════════════════════════════════════════════════
-- 0002 · Daily limit for AI photo recognition (Edge Function "product-ai").
-- Only the Edge Function (service role) can touch this; the app cannot.
-- ═══════════════════════════════════════════════════════════════════════════
create table public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null default current_date,
  count   int  not null default 0,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;   -- no policies: nobody via the API
revoke all on public.ai_usage from anon, authenticated;

-- Atomically uses one unit of today's quota. True = allowed.
create or replace function public.ai_take_quota(p_user uuid, p_limit int) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  n int;
begin
  insert into public.ai_usage (user_id, day, count) values (p_user, current_date, 1)
  on conflict (user_id, day) do update set count = public.ai_usage.count + 1
  returning count into n;
  if n > p_limit then
    update public.ai_usage set count = count - 1 where user_id = p_user and day = current_date;
    return false;
  end if;
  return true;
end $$;

revoke execute on function public.ai_take_quota(uuid, int) from public, anon, authenticated;
grant execute on function public.ai_take_quota(uuid, int) to service_role;
