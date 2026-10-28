-- save_product(): all-or-nothing product + sizes save, with permission checks.
\set ON_ERROR_STOP 1
begin;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner2@test.in'),
  ('00000000-0000-0000-0000-0000000000b1', 'cashier2@test.in'),
  ('00000000-0000-0000-0000-0000000000d1', 'cust2@test.in');
insert into public.shops (id, slug, name) values ('11000000-0000-0000-0000-000000000001', 'sp-test', 'SP Test');
insert into public.shop_members values
  ('11000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', 'owner', '{}', now()),
  ('11000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', 'staff', '{products}', now());

select tests.login('owner2@test.in');
select tests.eq(public.save_product(
  '{"id":"31000000-0000-0000-0000-000000000001","shop_id":"11000000-0000-0000-0000-000000000001","name":" Atta ","name_hi":"आटा","synonyms":["gehun"],"is_loose":false}',
  '[{"id":"41000000-0000-0000-0000-000000000001","label":"1 kg","unit":"kg","mrp":68,"price":62,"stock":10,"cost_price":55},
    {"id":"41000000-0000-0000-0000-000000000002","label":"5 kg","unit":"kg","unit_qty":5,"mrp":315,"price":279,"stock":3}]',
  true), '31000000-0000-0000-0000-000000000001'::uuid, 'owner creates product with 2 sizes');
select tests.eq((select name from public.products where id = '31000000-0000-0000-0000-000000000001'), 'Atta', 'name is trimmed');
select tests.eq((select count(*) from public.product_variants where product_id = '31000000-0000-0000-0000-000000000001')::int, 2, 'both sizes saved');
select tests.eq((select cost_price from public.variant_costs where variant_id = '41000000-0000-0000-0000-000000000001'), 55.00, 'cost price saved');

-- Edit: drop the 5 kg size, change price, leave stock untouched (no "stock" key).
select public.save_product(
  '{"id":"31000000-0000-0000-0000-000000000001","shop_id":"11000000-0000-0000-0000-000000000001","name":"Atta"}',
  '[{"id":"41000000-0000-0000-0000-000000000001","label":"1 kg","unit":"kg","mrp":70,"price":64}]', true);
select tests.eq((select count(*) from public.product_variants where product_id = '31000000-0000-0000-0000-000000000001')::int, 1, 'removed size is deleted');
select tests.eq((select stock from public.product_variants where id = '41000000-0000-0000-0000-000000000001'), 10.000, 'stock kept when not sent');
select tests.eq((select count(*) from public.variant_costs where variant_id = '41000000-0000-0000-0000-000000000001')::int, 0, 'blank cost removes cost row');

select tests.fails($$select public.save_product('{"shop_id":"11000000-0000-0000-0000-000000000001","name":"X"}', '[]')$$, 'product without sizes rejected');
select tests.fails($$select public.save_product(
  '{"id":"31000000-0000-0000-0000-000000000002","shop_id":"11000000-0000-0000-0000-000000000001","name":"Bad"}',
  '[{"label":"1","unit":"pc","mrp":10,"price":12}]')$$, 'price above MRP rejected');
select tests.eq((select count(*) from public.products where id = '31000000-0000-0000-0000-000000000002')::int, 0, 'failed save leaves nothing behind');

select tests.login('cashier2@test.in');
select public.save_product(
  '{"id":"31000000-0000-0000-0000-000000000001","shop_id":"11000000-0000-0000-0000-000000000001","name":"Chakki Atta"}',
  '[{"id":"41000000-0000-0000-0000-000000000001","label":"1 kg","unit":"kg","mrp":70,"price":64,"stock":25,"cost_price":1}]', true);
select tests.eq((select name from public.products where id = '31000000-0000-0000-0000-000000000001'), 'Chakki Atta', 'staff can rename + restock');
select tests.as_admin();
select tests.eq((select count(*) from public.variant_costs where variant_id = '41000000-0000-0000-0000-000000000001')::int, 0, 'staff without prices cannot set cost');
select tests.login('cashier2@test.in');
select tests.fails($$select public.save_product(
  '{"id":"31000000-0000-0000-0000-000000000001","shop_id":"11000000-0000-0000-0000-000000000001","name":"Atta"}',
  '[{"id":"41000000-0000-0000-0000-000000000001","label":"1 kg","unit":"kg","mrp":70,"price":50}]')$$, 'staff without prices cannot change price');

select tests.login('cust2@test.in');
select tests.fails($$select public.save_product(
  '{"shop_id":"11000000-0000-0000-0000-000000000001","name":"X"}', '[{"label":"1","unit":"pc","mrp":1,"price":1}]')$$, 'customer cannot save products');
rollback;
\echo 'save_product tests passed'
