-- Server pricing (price_cart) against the shared cases in test_vectors/pricing.json.
-- The Dart copy (lib/domain/pricing.dart) is checked against the same file.
\set ON_ERROR_STOP 1
\set vectors `cat ../test_vectors/pricing.json`
begin;
\o /dev/null
select set_config('tests.vectors', :'vectors', true);
\o

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c1', 'buyer@test.in');

do $$
declare
  d    jsonb := current_setting('tests.vectors')::jsonb;
  shop uuid := '11110000-0000-4000-8000-000000000001';
  p    jsonb;
  v    jsonb;
  x    jsonb;
begin
  insert into public.shops (id, slug, name, delivery_charge, free_delivery_above, min_order)
  values (shop, 'pricing-test', 'Pricing Test', (d #>> '{shop,delivery_charge}')::numeric,
          (d #>> '{shop,free_delivery_above}')::numeric, (d #>> '{shop,min_order}')::numeric);
  for x in select * from jsonb_array_elements(d -> 'categories') loop
    insert into public.categories (id, shop_id, name) values ((x ->> 'id')::uuid, shop, x ->> 'name');
  end loop;
  for p in select * from jsonb_array_elements(d -> 'products') loop
    insert into public.products (id, shop_id, category_id, name, is_loose, is_active)
    values ((p ->> 'id')::uuid, shop, (p ->> 'category_id')::uuid, p ->> 'name', (p ->> 'is_loose')::boolean,
            (p ->> 'is_active')::boolean);
    for v in select * from jsonb_array_elements(p -> 'variants') loop
      insert into public.product_variants (id, shop_id, product_id, label, unit, mrp, price, stock, track_stock, is_active)
      values ((v ->> 'id')::uuid, shop, (p ->> 'id')::uuid, v ->> 'label', v ->> 'unit', (v ->> 'mrp')::numeric,
              (v ->> 'price')::numeric, (v ->> 'stock')::numeric, (v ->> 'track_stock')::boolean, (v ->> 'is_active')::boolean);
    end loop;
  end loop;
  for x in select * from jsonb_array_elements(d -> 'offers') loop
    insert into public.offers (id, shop_id, title, kind, product_id, category_id, percent, amount, min_order,
                               max_discount, buy_qty, get_qty, starts_at, ends_at, is_active, created_at)
    values ((x ->> 'id')::uuid, shop, x ->> 'title', x ->> 'kind', (x ->> 'product_id')::uuid,
            (x ->> 'category_id')::uuid, (x ->> 'percent')::numeric, (x ->> 'amount')::numeric,
            (x ->> 'min_order')::numeric, (x ->> 'max_discount')::numeric, (x ->> 'buy_qty')::int,
            (x ->> 'get_qty')::int, (x ->> 'starts_at')::timestamptz, (x ->> 'ends_at')::timestamptz,
            (x ->> 'is_active')::boolean, (x ->> 'created_at')::timestamptz);
  end loop;
  for x in select * from jsonb_array_elements(d -> 'coupons') loop
    insert into public.coupons (id, shop_id, code, kind, value, max_discount, min_order, usage_limit, used_count,
                                per_user_limit, starts_at, ends_at, is_active)
    values ((x ->> 'id')::uuid, shop, x ->> 'code', x ->> 'kind', (x ->> 'value')::numeric,
            (x ->> 'max_discount')::numeric, (x ->> 'min_order')::numeric, (x ->> 'usage_limit')::int,
            (x ->> 'used_count')::int, (x ->> 'per_user_limit')::int, (x ->> 'starts_at')::timestamptz,
            (x ->> 'ends_at')::timestamptz, (x ->> 'is_active')::boolean);
  end loop;
end $$;

-- Compare one value: numbers numerically, everything else as JSON.
create or replace function tests.same(p_got jsonb, p_want jsonb) returns boolean language sql immutable as $$
  select case
    when jsonb_typeof(p_want) = 'number' and jsonb_typeof(p_got) = 'number' then (p_got #>> '{}')::numeric = (p_want #>> '{}')::numeric
    when p_want = 'null'::jsonb then p_got is null or p_got = 'null'::jsonb
    else p_got = p_want end
$$;

do $$
declare
  d     jsonb := current_setting('tests.vectors')::jsonb;
  shop  uuid := '11110000-0000-4000-8000-000000000001';
  cs    jsonb;
  q     jsonb;
  k     text;
  want  jsonb;
  line  jsonb;
  lk    text;
  err   text;
  n     int := 0;
begin
  for cs in select * from jsonb_array_elements(d -> 'cases') loop
    begin
      q := public.price_cart(shop, cs -> 'items', cs ->> 'coupon', cs ->> 'fulfilment',
                             case when (cs ->> 'logged_in')::boolean then '00000000-0000-0000-0000-0000000000c1'::uuid end,
                             (d ->> 'now')::timestamptz, false);
    exception when others then
      get stacked diagnostics err = pg_exception_detail;
      if cs ? 'error' and (err::jsonb ->> 'code') = cs ->> 'error' then
        raise notice 'ok  %', cs ->> 'name';
        n := n + 1;
        continue;
      end if;
      raise exception 'FAIL: % — unexpected error % (%)', cs ->> 'name', sqlerrm, err;
    end;
    if cs ? 'error' then
      raise exception 'FAIL: % — expected error %', cs ->> 'name', cs ->> 'error';
    end if;
    for k, want in select * from jsonb_each(cs -> 'expect') loop
      if k = 'lines' then
        for lk, want in select * from jsonb_each(cs #> '{expect,lines}') loop
          select l into line from jsonb_array_elements(q -> 'lines') l where l ->> 'variant_id' = lk;
          for k, want in select * from jsonb_each(cs #> array['expect', 'lines', lk]) loop
            if not tests.same(line -> k, want) then
              raise exception 'FAIL: % — line % %: got %, want %', cs ->> 'name', lk, k, line -> k, want;
            end if;
          end loop;
        end loop;
      elsif k = 'unavailable' then
        if (select jsonb_agg(jsonb_build_object('variant_id', u ->> 'variant_id', 'reason', u ->> 'reason',
                                               'available', (u ->> 'available')::numeric) order by u ->> 'variant_id')
              from jsonb_array_elements(q -> 'unavailable') u)
           is distinct from
           (select jsonb_agg(jsonb_build_object('variant_id', u ->> 'variant_id', 'reason', u ->> 'reason',
                                               'available', (u ->> 'available')::numeric) order by u ->> 'variant_id')
              from jsonb_array_elements(want) u) then
          raise exception 'FAIL: % — unavailable: got %', cs ->> 'name', q -> 'unavailable';
        end if;
      elsif not tests.same(q -> k, want) then
        raise exception 'FAIL: % — %: got %, want %', cs ->> 'name', k, q -> k, want;
      end if;
    end loop;
    raise notice 'ok  %', cs ->> 'name';
    n := n + 1;
  end loop;
  raise notice 'ok  % shared pricing cases', n;
end $$;
rollback;
\echo 'pricing tests passed'
