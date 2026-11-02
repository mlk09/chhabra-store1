-- Load test data: one shop with 3,000 products, 2,000 customers.
-- Runs ONLY on a throw-away test database (tools/load_test.sh). Never on Supabase.
\set ON_ERROR_STOP 1
create schema loadtest;

-- What every pgbench call did (filled by the helper functions below).
create table loadtest.results (
  id      bigserial primary key,
  kind    text not null,          -- order / owner / dup
  outcome text not null,          -- ok / repeat / items_changed / rate_limited / deadlock / ...
  ms      numeric not null,
  at      timestamptz not null default clock_timestamp()
);

insert into public.shops (id, slug, name, delivery_charge, free_delivery_above, min_order, delivery_pincodes)
values ('e0000000-0000-0000-0000-000000000001', 'load-test', 'Load Test Store', 20, 499, 0, '{132001}');

insert into auth.users (id, email) values ('e0000000-0000-0000-0000-00000000000a', 'owner@load.test');
insert into public.shop_members (shop_id, user_id, role)
values ('e0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-00000000000a', 'owner');

insert into public.categories (shop_id, name, sort_order)
select 'e0000000-0000-0000-0000-000000000001', 'Category ' || g, g from generate_series(1, 20) g;

-- 3,000 products, one size each. Normal stock 1,000. The first 30 are "hot":
-- only 25 in stock, so many customers fight for the last packs.
create table loadtest.variant_no (n int primary key, variant_id uuid not null, hot boolean not null);
insert into public.products (id, shop_id, name, name_hi, category_id, synonyms)
select ('e1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'e0000000-0000-0000-0000-000000000001',
       'Product ' || g, 'सामान ' || g,
       (select id from public.categories where shop_id = 'e0000000-0000-0000-0000-000000000001' order by sort_order
        offset (g % 20) limit 1),
       array['item' || g]
from generate_series(1, 3000) g;
insert into public.product_variants (id, shop_id, product_id, label, unit, mrp, price, stock)
select ('e2000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'e0000000-0000-0000-0000-000000000001',
       ('e1000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, '1 kg', 'kg',
       20 + (g % 50) * 10, 18 + (g % 50) * 9.5, case when g <= 30 then 25 else 1000 end
from generate_series(1, 3000) g;
insert into loadtest.variant_no
select g, ('e2000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, g <= 30 from generate_series(1, 3000) g;

create table loadtest.initial_stock as
select id as variant_id, stock from public.product_variants where shop_id = 'e0000000-0000-0000-0000-000000000001';

-- A coupon only 100 people may use, while ~30 % of 3,000+ orders try it.
insert into public.coupons (shop_id, code, kind, value, usage_limit, per_user_limit, is_public)
values ('e0000000-0000-0000-0000-000000000001', 'LOAD10', 'flat', 10, 100, 1, true);

-- 2,000 customers, each with a delivery address.
insert into auth.users (id, email, raw_user_meta_data)
select ('e3000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid, 'c' || g || '@load.test',
       jsonb_build_object('full_name', 'Customer ' || g)
from generate_series(1, 2000) g;
insert into public.addresses (id, user_id, name, phone, line1, pincode)
select ('e4000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
       ('e3000000-0000-0000-0000-' || lpad(g::text, 12, '0'))::uuid,
       'Customer ' || g, '98' || lpad(g::text, 8, '0'), 'House ' || g || ', Railway Road', '132001'
from generate_series(1, 2000) g;

-- ── Helpers called by the pgbench scripts ─────────────────────────────────

-- Short name for an error from place_order / set_order_status.
create function loadtest.code_of(p_state text, p_detail text) returns text language sql immutable as $$
  select case
    when p_state = '40P01' then 'deadlock'
    when p_state = '40001' then 'serialization'
    when p_state = '23505' then 'unique_violation'
    when p_detail like '{%' then coalesce(p_detail::jsonb ->> 'code', 'error')
    else 'sql_' || p_state end
$$;

-- One customer places one order of 1–8 random items (a third also try the
-- hot items, a third try the limited coupon), exactly like the app does.
create function loadtest.place(p_customer int, p_ref uuid default null) returns void
language plpgsql as $$
declare
  t0     timestamptz := clock_timestamp();
  v_items jsonb;
  v_out  text := 'ok';
  r      jsonb;
  st     text;
  dt     text;
begin
  perform set_config('request.jwt.claim.sub', ('e3000000-0000-0000-0000-' || lpad(p_customer::text, 12, '0')), true);
  select jsonb_agg(jsonb_build_object('variant_id', v.variant_id, 'qty', 1 + floor(random() * 3)::int))
    into v_items
  from (
    select variant_id from loadtest.variant_no
     where n = any (array(select case when random() < 0.33 and i = 1 then 1 + floor(random() * 30)::int
                                      else 31 + floor(random() * 2970)::int end
                          from generate_series(1, 1 + floor(random() * 8)::int) i))
  ) v;
  begin
    r := public.place_order(
      'e0000000-0000-0000-0000-000000000001', v_items, 'delivery', 'cod',
      ((now() at time zone 'Asia/Kolkata')::date + 1), '09:00-12:00',
      ('e4000000-0000-0000-0000-' || lpad(p_customer::text, 12, '0'))::uuid,
      case when random() < 0.3 then 'LOAD10' end, null, coalesce(p_ref, gen_random_uuid()));
    if (r ->> 'repeat')::boolean then v_out := 'repeat'; end if;
  exception when others then
    get stacked diagnostics st = returned_sqlstate, dt = pg_exception_detail;
    v_out := loadtest.code_of(st, dt);
  end;
  insert into loadtest.results (kind, outcome, ms)
  values (case when p_ref is null then 'order' else 'dup' end, v_out,
          extract(epoch from clock_timestamp() - t0) * 1000);
end $$;

-- The shop moves one waiting order a step forward (1 in 8: cancels it, which puts the stock back).
create function loadtest.owner_step() returns void language plpgsql as $$
declare
  t0  timestamptz := clock_timestamp();
  o   public.orders%rowtype;
  nxt text;
  v_out text := 'ok';
  st  text;
  dt  text;
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-0000-0000-00000000000a', true);
  select * into o from public.orders
   where shop_id = 'e0000000-0000-0000-0000-000000000001' and status not in ('delivered', 'cancelled')
   order by random() limit 1;
  if not found then return; end if;
  nxt := case when random() < 0.125 then 'cancelled'
              else case o.status when 'new' then 'accepted' when 'accepted' then 'packed'
                                 when 'packed' then 'out_for_delivery' else 'delivered' end end;
  begin
    perform public.set_order_status(o.id, nxt);
  exception when others then
    get stacked diagnostics st = returned_sqlstate, dt = pg_exception_detail;
    v_out := loadtest.code_of(st, dt);
  end;
  insert into loadtest.results (kind, outcome, ms) values ('owner', v_out, extract(epoch from clock_timestamp() - t0) * 1000);
end $$;
