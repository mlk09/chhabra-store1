-- Tiny test toolkit (plain SQL, no extensions).
create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

create or replace function tests.uid_of(p_email text) returns uuid
language sql stable security definer as $$ select id from auth.users where email = p_email $$;

-- Act as a logged-in user (like the app does through PostgREST) or as a visitor.
create or replace function tests.login(p_email text) returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', tests.uid_of(p_email)::text, true);
end $$;
create or replace function tests.logout() returns void language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
create or replace function tests.as_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

create or replace function tests.eq(p_got anyelement, p_want anyelement, p_msg text) returns void language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise exception 'FAIL: % (got %, want %)', p_msg, p_got, p_want;
  end if;
  raise notice 'ok  %', p_msg;
end $$;

-- Runs SQL and expects it to be rejected (RLS / permission / check error).
create or replace function tests.fails(p_sql text, p_msg text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'ok  % (blocked: %)', p_msg, sqlerrm;
    return;
  end;
  raise exception 'FAIL: % — statement was allowed: %', p_msg, p_sql;
end $$;

-- Runs an UPDATE/DELETE and returns how many rows it touched (RLS hides rows silently).
create or replace function tests.affected(p_sql text) returns int language plpgsql as $$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

grant usage on schema tests to service_role;
grant execute on all functions in schema tests to anon, authenticated, service_role;
