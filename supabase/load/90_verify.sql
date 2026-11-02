-- After the load: is every order, rupee and packet accounted for?
\set ON_ERROR_STOP 1
\pset footer off
\echo
\echo '── What happened ──'
select kind, outcome, count(*) as times,
       round(percentile_cont(0.5) within group (order by ms)::numeric, 1) as median_ms,
       round(percentile_cont(0.95) within group (order by ms)::numeric, 1) as p95_ms,
       round(max(ms), 1) as max_ms
from loadtest.results group by kind, outcome order by kind, times desc;

select status, count(*) from public.orders where shop_id = 'e0000000-0000-0000-0000-000000000001'
group by status order by 2 desc;

\echo '── Checks ──'
create temp table checks (name text, bad bigint);

-- 1. Stock never below zero.
insert into checks select 'stock below zero', count(*) from public.product_variants
 where shop_id = 'e0000000-0000-0000-0000-000000000001' and stock < 0;

-- 2. Stock now = starting stock − what live (not cancelled) orders hold. Every packet accounted for.
insert into checks select 'stock does not match orders', count(*) from (
  select i.variant_id, i.stock - coalesce(sum(oi.qty) filter (where o.status <> 'cancelled' and oi.status = 'ok'), 0) as expect,
         v.stock
  from loadtest.initial_stock i
  join public.product_variants v on v.id = i.variant_id
  left join public.order_items oi on oi.variant_id = i.variant_id
  left join public.orders o on o.id = oi.order_id
  group by i.variant_id, i.stock, v.stock) x where expect <> stock;

-- 3. Stock history (movements) adds up too.
insert into checks select 'stock history does not add up', count(*) from (
  select i.variant_id from loadtest.initial_stock i join public.product_variants v on v.id = i.variant_id
  left join public.stock_movements m on m.variant_id = i.variant_id
  group by i.variant_id, i.stock, v.stock having i.stock + coalesce(sum(m.delta), 0) <> v.stock) x;

-- 4. Hot items (25 in stock): never sold more than there was.
insert into checks select 'hot item oversold', count(*) from (
  select oi.variant_id, sum(oi.qty) sold from public.order_items oi join public.orders o on o.id = oi.order_id
  join loadtest.variant_no n on n.variant_id = oi.variant_id and n.hot
  where o.status <> 'cancelled' group by oi.variant_id having sum(oi.qty) > 25) x;

-- 5. Each bill adds up: items = sum of lines; total = items − discounts + delivery.
insert into checks select 'order total wrong', count(*) from public.orders o
 where o.shop_id = 'e0000000-0000-0000-0000-000000000001'
   and (o.items_total <> (select sum(line_total) from public.order_items where order_id = o.id)
        or o.total <> o.items_total - o.cart_discount - o.coupon_discount + o.delivery_charge
        or o.delivery_charge <> case when o.items_total - o.cart_discount >= 499 then 0 else 20 end);

-- 6. Each line priced from the price list (price × qty).
insert into checks select 'line price wrong', count(*) from public.order_items oi
 join public.product_variants v on v.id = oi.variant_id
 where oi.shop_id = 'e0000000-0000-0000-0000-000000000001' and oi.line_total <> round(v.price * oi.qty, 2) - oi.discount;

-- 7. Order numbers 1, 2, 3 … with no repeats or gaps.
insert into checks select 'order numbers repeat or skip', (select count(*) - count(distinct order_no) + (max(order_no) - count(*))
  from public.orders where shop_id = 'e0000000-0000-0000-0000-000000000001');

-- 8. Limited coupon (100 uses): never used more than 100 times.
insert into checks select 'coupon used more than its limit',
  greatest((select count(*) from public.orders where coupon_code = 'LOAD10' and status <> 'cancelled') - 100, 0);
insert into checks select 'coupon counter wrong',
  abs((select used_count from public.coupons where code = 'LOAD10')
      - (select count(*) from public.coupon_redemptions r join public.coupons c on c.id = r.coupon_id where c.code = 'LOAD10'));

-- 9. Same customer + same order ref (double tap) → only one order.
insert into checks select 'double order from one tap', count(*) from (
  select client_ref from public.orders where client_ref is not null group by client_ref having count(*) > 1) x;

-- 10. Every finished pgbench call is in the results; none lost to a crash.
insert into checks select 'unexpected errors', count(*) from loadtest.results
 where outcome not in ('ok', 'repeat', 'items_changed', 'rate_limited', 'coupon_used_up', 'coupon_already_used', 'bad_status');

select name as check, bad, case when bad = 0 then 'PASS' else 'FAIL' end as result from checks;
