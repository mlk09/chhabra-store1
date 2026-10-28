-- Orders: placing, stock, coupons, status changes, and who can see what.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a2', 'owner3@test.in', '{}'),
  ('00000000-0000-0000-0000-0000000000b2', 'cashier3@test.in', '{}'),
  ('00000000-0000-0000-0000-0000000000b3', 'packer3@test.in', '{}'),
  ('00000000-0000-0000-0000-0000000000d2', 'asha@test.in', '{"full_name":"Asha"}'),
  ('00000000-0000-0000-0000-0000000000d3', 'ravi@test.in', '{"full_name":"Ravi"}');
insert into public.shops (id, slug, name, delivery_charge, free_delivery_above, min_order, delivery_pincodes)
values ('12000000-0000-0000-0000-000000000001', 'order-test', 'Order Test', 20, 499, 100, '{132001}');
insert into public.shop_members values
  ('12000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2', 'owner', '{}', now()),
  ('12000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b2', 'staff', '{billing}', now()),
  ('12000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b3', 'staff', '{orders}', now());
insert into public.products (id, shop_id, name) values
  ('32000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000001', 'Atta'),
  ('32000000-0000-0000-0000-000000000002', '12000000-0000-0000-0000-000000000001', 'Salt');
insert into public.product_variants (id, shop_id, product_id, label, unit, mrp, price, stock) values
  ('42000000-0000-0000-0000-000000000001', '12000000-0000-0000-0000-000000000001', '32000000-0000-0000-0000-000000000001', '5 kg', 'kg', 315, 279, 10),
  ('42000000-0000-0000-0000-000000000002', '12000000-0000-0000-0000-000000000001', '32000000-0000-0000-0000-000000000002', '1 kg', 'kg', 30, 28, 5);
insert into public.coupons (shop_id, code, kind, value, per_user_limit, is_public) values
  ('12000000-0000-0000-0000-000000000001', 'FIRST30', 'flat', 30, 1, false),
  ('12000000-0000-0000-0000-000000000001', 'DIWALI', 'flat', 10, 5, true);

-- Helper: tomorrow (shop time) is always a valid slot date.
create or replace function tests.tomorrow() returns date language sql stable as
$$ select (now() at time zone 'Asia/Kolkata')::date + 1 $$;

-- ── Customer: addresses are private ────────────────────────────────────────
select tests.login('asha@test.in');
insert into public.addresses (id, name, phone, line1, pincode)
values ('52000000-0000-0000-0000-000000000001', 'Asha', '9876543210', '12 Railway Road', '132001'),
       ('52000000-0000-0000-0000-000000000002', 'Asha', '9876543210', 'Far village', '110001');
select tests.eq((select count(*) from public.addresses)::int, 2, 'customer sees own addresses');
select tests.fails($$insert into public.addresses (user_id, name, phone, line1, pincode)
  values ('00000000-0000-0000-0000-0000000000d3', 'X', '9876543210', 'abc road', '132001')$$, 'cannot add an address for someone else');
select tests.login('ravi@test.in');
select tests.eq((select count(*) from public.addresses)::int, 0, 'other customer cannot see Asha''s addresses');
select tests.eq((select count(*) from public.coupons)::int, 1, 'only public coupons are visible to customers');

-- ── Placing orders ─────────────────────────────────────────────────────────
select tests.logout();
select tests.eq((public.quote_cart('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":1}]') ->> 'total')::numeric, 299.00, 'visitor can see a cart total');
select tests.fails($$select public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":1}]', 'pickup', 'cod', tests.tomorrow(), '09:00-12:00')$$,
  'visitor cannot place an order');

select tests.login('asha@test.in');
select tests.fails($$insert into public.orders (shop_id, order_no, fulfilment, subtotal_mrp, items_total, total, payment_method)
  values ('12000000-0000-0000-0000-000000000001', 99, 'pickup', 1, 1, 1, 'cod')$$, 'orders cannot be inserted directly (prices would be trusted)');
select tests.fails($$select public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":1}]', 'delivery', 'cod', tests.tomorrow(), '09:00-12:00',
  '52000000-0000-0000-0000-000000000002')$$, 'pincode outside delivery area is refused');
select tests.fails($$select public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":1}]', 'pickup', 'cod', tests.tomorrow(), '02:00-03:00')$$,
  'unknown time slot is refused');
select tests.fails($$select public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":1}]', 'pickup', 'cod', tests.tomorrow() + 10, '09:00-12:00')$$,
  'slot too far ahead is refused');
select tests.fails($$select public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":1}]', 'pickup', 'cod', tests.tomorrow(), '09:00-12:00',
  null, null, null, null, 1)$$, 'app-sent total that differs from the server is refused (price_changed)');
select tests.fails($$select public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000002","qty":6}]', 'pickup', 'cod', tests.tomorrow(), '09:00-12:00')$$,
  'more than the stock is refused');
select tests.fails($$select public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000002","qty":1}]', 'delivery', 'cod', tests.tomorrow(), '09:00-12:00',
  '52000000-0000-0000-0000-000000000001')$$, 'below the minimum order for delivery is refused');

select null from set_config('tests.o1', (public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":2},{"variant_id":"42000000-0000-0000-0000-000000000002","qty":1}]',
  'delivery', 'cod', tests.tomorrow(), '09:00-12:00', '52000000-0000-0000-0000-000000000001', 'first30',
  'Ring the bell', '62000000-0000-0000-0000-000000000001', 556) ->> 'order_id'), true);
select tests.eq((select total from public.orders where id = current_setting('tests.o1')::uuid), 556.00,
  'order total decided by the server (586 − ₹30 coupon, free delivery above 499)');
select tests.eq((select order_no from public.orders where id = current_setting('tests.o1')::uuid), 1, 'first order is #1');
select tests.eq((select count(*) from public.order_items where order_id = current_setting('tests.o1')::uuid)::int, 2, 'items saved');
select tests.eq((select address ->> 'pincode' from public.orders where id = current_setting('tests.o1')::uuid), '132001', 'address copied into the order');
select tests.eq((select (public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":2}]', 'pickup', 'cod', tests.tomorrow(), '09:00-12:00',
  null, null, null, '62000000-0000-0000-0000-000000000001') ->> 'repeat')::boolean), true,
  'same client_ref (double tap / retry) returns the same order, no duplicate');
select tests.eq((select (public.quote_cart('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":2}]', 'FIRST30') ->> 'coupon_error')), 'already_used',
  'coupon limited to once per customer');

select tests.as_admin();
select tests.eq((select stock from public.product_variants where id = '42000000-0000-0000-0000-000000000001'), 8.000, 'stock went down by 2');
select tests.eq((select used_count from public.coupons where code = 'FIRST30'), 1, 'coupon use counted');

-- ── Who can see the order ──────────────────────────────────────────────────
select tests.login('ravi@test.in');
select tests.eq((select count(*) from public.orders)::int, 0, 'another customer cannot see Asha''s order');
select tests.eq((select count(*) from public.order_items)::int, 0, 'nor its items');
select tests.fails($$select null from public.set_order_status(current_setting('tests.o1')::uuid, 'cancelled')$$, 'another customer cannot cancel it');
select tests.login('cashier3@test.in');
select tests.eq((select count(*) from public.orders)::int, 0, 'staff without "orders" permission cannot see online orders');
select tests.login('packer3@test.in');
select tests.eq((select count(*) from public.orders)::int, 1, 'staff with "orders" permission sees the order');

-- ── Status flow ────────────────────────────────────────────────────────────
select tests.fails($$select null from public.set_order_status(current_setting('tests.o1')::uuid, 'delivered')$$, 'cannot jump from new to delivered');
select null from public.set_order_status(current_setting('tests.o1')::uuid, 'accepted');
select tests.login('asha@test.in');
select tests.fails($$select null from public.set_order_status(current_setting('tests.o1')::uuid, 'cancelled')$$, 'customer cannot cancel after the shop accepted');
select tests.login('packer3@test.in');
select tests.eq((select (public.mark_item_unavailable(i.id) ->> 'total')::numeric from public.order_items i
  where i.order_id = current_setting('tests.o1')::uuid and i.name = 'Salt'), 528.00, 'item unavailable: bill drops by its price');
select null from public.set_order_status(current_setting('tests.o1')::uuid, 'packed');
select tests.fails($$select null from public.set_order_status(current_setting('tests.o1')::uuid, 'ready_for_pickup')$$, 'delivery order cannot go to pickup');
select null from public.set_order_status(current_setting('tests.o1')::uuid, 'out_for_delivery');
select null from public.set_order_status(current_setting('tests.o1')::uuid, 'delivered');
select tests.as_admin();
select tests.eq((select payment_status from public.orders where id = current_setting('tests.o1')::uuid), 'paid', 'cash on delivery marked paid when delivered');
select tests.eq((select stock from public.product_variants where id = '42000000-0000-0000-0000-000000000002'), 5.000, 'unavailable item went back to stock');
select tests.eq((select count(*) from public.order_events where order_id = current_setting('tests.o1')::uuid)::int, 6, 'every step is in the timeline');

-- ── Customer cancels a new order → stock and coupon come back ──────────────
select tests.login('ravi@test.in');
select null from set_config('tests.o2', (public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":3}]', 'pickup', 'cod', tests.tomorrow(), '09:00-12:00',
  null, 'diwali') ->> 'order_id'), true);
select tests.eq((select order_no from public.orders where id = current_setting('tests.o2')::uuid), 2, 'order numbers go up');
select null from public.set_order_status(current_setting('tests.o2')::uuid, 'cancelled', 'Ordered by mistake');
select tests.as_admin();
select tests.eq((select stock from public.product_variants where id = '42000000-0000-0000-0000-000000000001'), 8.000, 'cancel returns stock');
select tests.eq((select used_count from public.coupons where code = 'DIWALI'), 0, 'cancel returns the coupon use');
select tests.eq((select cancelled_by from public.orders where id = current_setting('tests.o2')::uuid), 'customer', 'records who cancelled');

-- ── Shop closed ────────────────────────────────────────────────────────────
update public.shops set holiday_mode = true where id = '12000000-0000-0000-0000-000000000001';
select tests.login('ravi@test.in');
select tests.fails($$select public.place_order('12000000-0000-0000-0000-000000000001',
  '[{"variant_id":"42000000-0000-0000-0000-000000000001","qty":1}]', 'pickup', 'cod', tests.tomorrow(), '09:00-12:00')$$,
  'no orders in holiday mode');

-- ── Offers & coupons: only the owner manages them ──────────────────────────
select tests.fails($$insert into public.offers (shop_id, title, kind, percent) values
  ('12000000-0000-0000-0000-000000000001', 'Free money', 'cart_percent', 90)$$, 'customer cannot create offers');
select tests.login('owner3@test.in');
insert into public.offers (shop_id, title, kind, amount, min_order)
values ('12000000-0000-0000-0000-000000000001', '₹50 off above ₹500', 'cart_flat', 50, 500);
select tests.eq((select count(*) from public.coupons)::int, 2, 'owner sees secret coupons too');
select tests.fails($$insert into public.offers (shop_id, title, kind, percent, product_id) values
  ('12000000-0000-0000-0000-000000000001', 'Bad', 'product_percent', 10, null)$$, 'product offer needs a product');
rollback;
\echo 'order tests passed'
