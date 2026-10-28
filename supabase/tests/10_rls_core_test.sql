-- RLS tests for 0001_core. Each block runs in a transaction that is rolled back.
\set ON_ERROR_STOP 1
begin;

-- ── Fixtures (as admin) ────────────────────────────────────────────────────
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'owner@test.in',    '{"full_name":"Mr Chhabra"}'),
  ('00000000-0000-0000-0000-00000000000b', 'cashier@test.in',  '{}'),
  ('00000000-0000-0000-0000-00000000000c', 'manager@test.in',  '{}'),
  ('00000000-0000-0000-0000-00000000000d', 'customer@test.in', '{"full_name":"Asha","phone":"9876543210"}'),
  ('00000000-0000-0000-0000-00000000000e', 'other@test.in',    '{}');

insert into public.shops (id, slug, name) values
  ('10000000-0000-0000-0000-000000000001', 'chhabra-test', 'Chhabra Test'),
  ('10000000-0000-0000-0000-000000000002', 'other-shop', 'Other Shop');

insert into public.shop_members (shop_id, user_id, role, permissions) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'owner', '{}'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'staff', '{billing,products}'),
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c', 'staff', '{billing,products,prices}'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000e', 'owner', '{}');

insert into public.categories (id, shop_id, name, is_active) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Oil', true),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Hidden', false);

insert into public.products (id, shop_id, category_id, name, is_active) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Mustard Oil', true),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Old Oil', false),
  ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', null, 'Other shop item', true);

insert into public.product_variants (id, shop_id, product_id, label, unit, unit_qty, mrp, price, stock, is_active) values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '1 L', 'l', 1, 200, 180, 10, true),
  ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '5 L', 'l', 5, 950, 900, 4, false),
  ('40000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000002', '1 L', 'l', 1, 150, 150, 2, true),
  ('40000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000003', '1 pc', 'pc', 1, 10, 10, 2, true);

insert into public.variant_costs (variant_id, shop_id, cost_price) values
  ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 150);

-- ── Sign-up creates a profile ──────────────────────────────────────────────
select tests.eq((select full_name from public.profiles where id = '00000000-0000-0000-0000-00000000000d'), 'Asha', 'signup trigger copies name');
select tests.eq((select phone from public.profiles where id = '00000000-0000-0000-0000-00000000000d'), '9876543210', 'signup trigger copies valid phone');

-- ── Visitor (not logged in) ────────────────────────────────────────────────
select tests.logout();
select tests.eq((select count(*) from public.shops where slug in ('chhabra-test', 'other-shop'))::int, 2, 'visitor can read shop info');
select tests.eq((select count(*) from public.categories where shop_id = '10000000-0000-0000-0000-000000000001')::int, 1, 'visitor sees only active categories');
select tests.eq((select count(*) from public.products where shop_id = '10000000-0000-0000-0000-000000000001')::int, 1, 'visitor sees only active products');
select tests.eq((select count(*) from public.product_variants where shop_id = '10000000-0000-0000-0000-000000000001')::int, 1, 'visitor sees only active variants of active products');
select tests.fails('select * from public.variant_costs', 'visitor cannot read cost price');
select tests.fails('select * from public.profiles', 'visitor cannot read profiles');
select tests.fails($$insert into public.categories (shop_id, name) values ('10000000-0000-0000-0000-000000000001', 'x')$$, 'visitor cannot add category');
select tests.fails($$update public.shops set name = 'Hacked'$$, 'visitor cannot edit shop');

-- ── Customer ───────────────────────────────────────────────────────────────
select tests.login('customer@test.in');
select tests.eq((select count(*) from public.products where shop_id = '10000000-0000-0000-0000-000000000001')::int, 1, 'customer sees only active products');
select tests.eq((select count(*) from public.variant_costs)::int, 0, 'customer sees no cost prices');
select tests.eq((select count(*) from public.profiles)::int, 1, 'customer sees only own profile');
select tests.eq((select count(*) from public.shop_members)::int, 0, 'customer sees no staff list');
select tests.eq(tests.affected($$update public.shops set name = 'Hacked'$$), 0, 'customer cannot edit shop');
select tests.eq(tests.affected($$update public.product_variants set price = 1$$), 0, 'customer cannot change prices');
select tests.eq(tests.affected($$delete from public.products$$), 0, 'customer cannot delete products');
select tests.fails($$insert into public.products (shop_id, name) values ('10000000-0000-0000-0000-000000000001', 'x')$$, 'customer cannot add products');
select tests.fails($$insert into public.shop_members (shop_id, user_id, role) values ('10000000-0000-0000-0000-000000000001', auth.uid(), 'owner')$$, 'customer cannot make self owner');
select tests.eq(tests.affected($$update public.profiles set full_name = 'Asha Rani'$$), 1, 'customer can edit own profile');
select tests.fails($$update public.profiles set id = gen_random_uuid()$$, 'customer cannot change profile id');
select tests.fails($$select public.bulk_update_prices('10000000-0000-0000-0000-000000000001', 10)$$, 'customer cannot bulk-update prices');
select tests.fails($$insert into storage.objects (bucket_id, name) values ('product-images', '10000000-0000-0000-0000-000000000001/x/a.jpg')$$, 'customer cannot upload product images');

-- ── Cashier: products but NOT prices ───────────────────────────────────────
select tests.login('cashier@test.in');
select tests.eq((select count(*) from public.products where shop_id = '10000000-0000-0000-0000-000000000001')::int, 2, 'staff sees inactive products too');
select tests.eq((select count(*) from public.products where shop_id = '10000000-0000-0000-0000-000000000002')::int, 1, 'staff sees other shop only if active (public)');
select tests.eq(tests.affected($$update public.product_variants set stock = 25 where id = '40000000-0000-0000-0000-000000000001'$$), 1, 'cashier can update stock');
select tests.fails($$update public.product_variants set price = 100 where id = '40000000-0000-0000-0000-000000000001'$$, 'cashier cannot change price');
select tests.fails($$update public.product_variants set mrp = 300 where id = '40000000-0000-0000-0000-000000000001'$$, 'cashier cannot change MRP');
select tests.fails($$insert into public.product_variants (shop_id, product_id, label, unit, mrp, price) values ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '2 L', 'l', 10, 10)$$, 'cashier cannot create priced variant');
select tests.eq((select count(*) from public.variant_costs)::int, 0, 'cashier cannot see cost price');
select tests.eq(tests.affected($$update public.products set name = 'Sarson Oil' where id = '30000000-0000-0000-0000-000000000001'$$), 1, 'cashier can rename product');
select tests.eq(tests.affected($$update public.shops set name = 'X'$$), 0, 'cashier cannot edit shop settings');
select tests.eq((select count(*) from public.shop_members)::int, 1, 'staff sees only own membership');
select tests.eq(tests.affected($$update public.products set name = 'Y' where shop_id = '10000000-0000-0000-0000-000000000002'$$), 0, 'staff cannot edit another shop');
insert into storage.objects (bucket_id, name) values ('product-images', '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/a.jpg');
select tests.eq(1, 1, 'product staff can upload images to own shop folder');
select tests.fails($$insert into storage.objects (bucket_id, name) values ('product-images', '10000000-0000-0000-0000-000000000002/x/a.jpg')$$, 'staff cannot upload to another shop folder');
select tests.fails($$insert into storage.objects (bucket_id, name) values ('product-images', 'not-a-uuid/a.jpg')$$, 'upload to a junk path is rejected');

-- ── Manager: prices allowed ────────────────────────────────────────────────
select tests.login('manager@test.in');
select tests.eq(tests.affected($$update public.product_variants set price = 175 where id = '40000000-0000-0000-0000-000000000001'$$), 1, 'manager can change price');
select tests.fails($$update public.product_variants set price = 250 where id = '40000000-0000-0000-0000-000000000001'$$, 'price above MRP is rejected');
select tests.fails($$update public.product_variants set stock = -1 where id = '40000000-0000-0000-0000-000000000001'$$, 'stock cannot go negative');
select tests.eq((select cost_price from public.variant_costs where variant_id = '40000000-0000-0000-0000-000000000001'), 150.00, 'manager sees cost price');
select tests.fails($$insert into public.product_variants (shop_id, product_id, label, unit, mrp, price) values ('10000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000003', 'x', 'pc', 1, 1)$$, 'cannot attach variant to another shop''s product');
select tests.fails($$insert into public.products (shop_id, category_id, name) values ('10000000-0000-0000-0000-000000000002', null, 'x')$$, 'cannot add product to another shop');

-- ── Owner ──────────────────────────────────────────────────────────────────
select tests.login('owner@test.in');
select tests.eq(tests.affected($$update public.shops set upi_id = 'chhabra@okaxis' where id = '10000000-0000-0000-0000-000000000001'$$), 1, 'owner edits shop settings');
select tests.eq(tests.affected($$update public.shops set name = 'X' where id = '10000000-0000-0000-0000-000000000002'$$), 0, 'owner cannot edit another shop');
select tests.fails($$update public.shops set upi_id = 'not a upi'$$, 'invalid UPI ID rejected');
select tests.fails($$update public.shops set slug = 'new-slug'$$, 'slug cannot be changed from the app');
select tests.eq((select count(*) from public.shop_members)::int, 3, 'owner sees all staff of own shop');
select tests.eq(public.bulk_update_prices('10000000-0000-0000-0000-000000000001', 10, '20000000-0000-0000-0000-000000000001'), 3, 'bulk update touches all oil variants');
select tests.eq((select mrp from public.product_variants where id = '40000000-0000-0000-0000-000000000001'), 220.00, 'bulk +10% MRP 200 → 220');
select tests.eq((select price from public.product_variants where id = '40000000-0000-0000-0000-000000000001'), 193.00, 'bulk +10% price 175 → 192.5 → ₹193');
select tests.eq(public.bulk_update_prices('10000000-0000-0000-0000-000000000001', 20, null, null, 'price'), 3, 'bulk price-only update');
select tests.eq((select price from public.product_variants where id = '40000000-0000-0000-0000-000000000001'), 220.00, 'price-only increase is capped at MRP');
select tests.eq((select price from public.product_variants where id = '40000000-0000-0000-0000-000000000004'), 10.00, 'bulk update never touches another shop');
select tests.fails($$select public.bulk_update_prices('10000000-0000-0000-0000-000000000001', 500)$$, 'absurd percent rejected');

-- ── Account deletion ───────────────────────────────────────────────────────
select tests.login('customer@test.in');
select public.delete_my_account();
select tests.as_admin();
select tests.eq((select count(*) from auth.users where email = 'customer@test.in')::int, 0, 'delete_my_account removes the user');
select tests.eq((select count(*) from public.profiles where id = '00000000-0000-0000-0000-00000000000d')::int, 0, 'profile removed with the account');

rollback;
\echo 'core RLS tests passed'
