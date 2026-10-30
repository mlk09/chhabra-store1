-- Many shops: data stays separate, the platform can pause a shop, seeding is safe.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000e1', 'owner-a@test.in'),
  ('00000000-0000-0000-0000-0000000000e2', 'owner-b@test.in'),
  ('00000000-0000-0000-0000-0000000000e3', 'buyer-x@test.in');

select tests.eq(public.seed_shop('{"slug":"shop-a","name":"Shop A","city":"Karnal","pincode":"132001","delivery_pincodes":["132001"]}') is not null, true, 'seed_shop creates a shop');
select tests.eq((select count(*) from public.categories c join public.shops s on s.id = c.shop_id where s.slug = 'shop-a')::int, 10, 'with 10 starter categories');
update public.shops set name = 'Shop A (edited by owner)' where slug = 'shop-a';
select public.seed_shop('{"slug":"shop-a","name":"Shop A"}');
select tests.eq((select name from public.shops where slug = 'shop-a'), 'Shop A (edited by owner)', 'seeding again never overwrites owner edits');
select tests.eq((select count(*) from public.categories c join public.shops s on s.id = c.shop_id where s.slug = 'shop-a')::int, 10, 'nor duplicates categories');
select public.seed_shop('{"slug":"shop-b","name":"Shop B"}');

insert into public.shop_members (shop_id, user_id, role)
select id, '00000000-0000-0000-0000-0000000000e1', 'owner' from public.shops where slug = 'shop-a';
insert into public.shop_members (shop_id, user_id, role)
select id, '00000000-0000-0000-0000-0000000000e2', 'owner' from public.shops where slug = 'shop-b';
insert into public.products (id, shop_id, name)
select '35000000-0000-0000-0000-000000000001', id, 'A-only item' from public.shops where slug = 'shop-a';
insert into public.product_variants (id, shop_id, product_id, label, unit, mrp, price, stock)
select '45000000-0000-0000-0000-000000000001', id, '35000000-0000-0000-0000-000000000001', '1 pc', 'pc', 200, 150, 10
from public.shops where slug = 'shop-a';

-- Owners are separated
select tests.login('owner-b@test.in');
select tests.eq(tests.affected($$update public.products set name = 'hacked' where id = '35000000-0000-0000-0000-000000000001'$$), 0, 'owner B cannot edit shop A products');
select tests.eq(tests.affected($$update public.shops set name = 'hacked' where slug = 'shop-a'$$), 0, 'owner B cannot edit shop A');
select tests.login('owner-a@test.in');
select tests.eq(tests.affected($$update public.shops set brand_color = '#C2185B' where slug = 'shop-a'$$), 1, 'owner can set own brand colour');
select tests.fails($$update public.shops set service_status = 'active' where slug = 'shop-a'$$, 'owner cannot un-pause / change service status');
select tests.fails($$update public.shops set brand_color = 'red' where slug = 'shop-a'$$, 'brand colour must be #RRGGBB');
select tests.fails($$select public.seed_shop('{"slug":"x","name":"X"}')$$, 'only the platform can create shops');

-- Paused shop takes no orders
select tests.as_admin();
update public.shops set service_status = 'paused', service_note = 'Fees due' where slug = 'shop-a';
select tests.login('buyer-x@test.in');
select tests.fails($$select public.place_order((select id from public.shops where slug = 'shop-a'),
  '[{"variant_id":"45000000-0000-0000-0000-000000000001","qty":1}]', 'pickup', 'cod',
  (now() at time zone 'Asia/Kolkata')::date + 1, '09:00-12:00')$$, 'paused shop refuses new orders');
select tests.eq((select count(*) from public.products where id = '35000000-0000-0000-0000-000000000001')::int, 1, 'paused shop is still visible');
select tests.as_admin();
update public.shops set service_status = 'active' where slug = 'shop-a';
select tests.login('buyer-x@test.in');
select tests.eq((public.place_order((select id from public.shops where slug = 'shop-a'),
  '[{"variant_id":"45000000-0000-0000-0000-000000000001","qty":1}]', 'pickup', 'cod',
  (now() at time zone 'Asia/Kolkata')::date + 1, '09:00-12:00') ->> 'order_no')::int, 1, 'resumed shop takes orders; numbering is per shop');
select tests.login('owner-b@test.in');
select tests.eq((select count(*) from public.orders)::int, 0, 'owner B never sees shop A orders');
rollback;
\echo 'multi-shop tests passed'
