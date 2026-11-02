-- 0006 · Coupon limits and double taps hold under rush.
-- The load test (tools/load_test.sh) found that a coupon limited to 100 uses
-- could be used 103 times when many customers ordered at the same moment.
-- It also showed that two taps at the very same moment gave the second tap a
-- duplicate error (still only one order). Now the second tap gets the same order.
-- place_order is unchanged except these two steps. The whole order
-- is still one transaction, so a refused coupon undoes the order and its stock.

create or replace function public.place_order(
  p_shop uuid,
  p_items jsonb,
  p_fulfilment text,
  p_payment_method text,
  p_slot_date date,
  p_slot text,
  p_address_id uuid default null,
  p_coupon text default null,
  p_note text default null,
  p_client_ref uuid default null,
  p_expected_total numeric default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  s         public.shops%rowtype;
  a         public.addresses%rowtype;
  q         jsonb;
  l         jsonb;
  v_order   uuid;
  v_no      int;
  v_name    text;
  v_phone   text;
  v_addr    jsonb;
begin
  if v_uid is null then
    perform public.money_error('login_required', 'Please log in to order');
  end if;
  if p_client_ref is not null then
    -- Two taps at the same moment: the second waits here for the first to finish,
    -- then gets the same order back (instead of a confusing duplicate error).
    perform pg_advisory_xact_lock(hashtextextended('order:' || p_client_ref::text, 0));
    select id into v_order from public.orders where client_ref = p_client_ref and customer_id = v_uid;
    if found then
      return jsonb_build_object('order_id', v_order, 'repeat', true);   -- double tap / retry: same order
    end if;
  end if;
  if not public.hit_rate('order:' || v_uid, 5, 600) then
    perform public.money_error('rate_limited', 'Too many orders. Please wait a few minutes.');
  end if;

  select * into s from public.shops where id = p_shop for share;
  if not found then
    perform public.money_error('shop_not_found', 'Shop not found');
  end if;
  if not s.is_open or s.holiday_mode then
    perform public.money_error('shop_closed', 'The shop is not taking orders right now');
  end if;
  if (p_fulfilment = 'delivery' and not s.delivery_enabled) or (p_fulfilment = 'pickup' and not s.pickup_enabled) then
    perform public.money_error('fulfilment_off', 'This option is not available');
  end if;
  if not ((p_payment_method = 'cod' and s.cod_enabled)
          or (p_payment_method = 'upi_direct' and s.upi_direct_enabled and s.upi_id is not null)
          or (p_payment_method = 'gateway' and s.gateway_enabled)) then
    perform public.money_error('payment_off', 'This payment method is not available');
  end if;
  if not public.slot_ok(p_shop, p_slot_date, p_slot, now()) then
    perform public.money_error('bad_slot', 'Please choose another time slot');
  end if;

  if p_fulfilment = 'delivery' then
    select * into a from public.addresses where id = p_address_id and user_id = v_uid;
    if not found then
      perform public.money_error('address_required', 'Please choose a delivery address');
    end if;
    if cardinality(s.delivery_pincodes) > 0 and not (a.pincode = any (s.delivery_pincodes)) then
      perform public.money_error('outside_area', 'We do not deliver to this pincode yet',
                                 jsonb_build_object('pincode', a.pincode));
    end if;
    v_addr := to_jsonb(a) - 'user_id' - 'created_at' - 'is_default';
    v_name := a.name;
    v_phone := a.phone;
  else
    select full_name, phone into v_name, v_phone from public.profiles where id = v_uid;
  end if;

  q := public.price_cart(p_shop, p_items, p_coupon, p_fulfilment, v_uid, now(), true);

  if jsonb_array_length(q -> 'unavailable') > 0 then
    perform public.money_error('items_changed', 'Some items are no longer available',
                               jsonb_build_object('unavailable', q -> 'unavailable'));
  end if;
  if (q ->> 'coupon_error') is not null then
    perform public.money_error('coupon_' || (q ->> 'coupon_error'), 'This coupon cannot be used');
  end if;
  if (q ->> 'below_min_order')::boolean then
    perform public.money_error('below_min_order', 'Minimum order not reached',
                               jsonb_build_object('min_order', s.min_order));
  end if;
  if p_expected_total is not null and p_expected_total <> (q ->> 'total')::numeric then
    perform public.money_error('price_changed', 'Prices changed. Please check the new total.',
                               jsonb_build_object('total', q -> 'total'));
  end if;

  insert into public.order_counters (shop_id, last_no) values (p_shop, 1)
  on conflict (shop_id) do update set last_no = public.order_counters.last_no + 1
  returning last_no into v_no;

  insert into public.orders (shop_id, order_no, customer_id, customer_name, customer_phone, channel, status,
                             fulfilment, address, slot_date, slot, subtotal_mrp, items_total, item_discount,
                             cart_discount, cart_offer, coupon_id, coupon_code, coupon_discount, delivery_charge,
                             total, savings, payment_method, note, client_ref)
  values (p_shop, v_no, v_uid, v_name, v_phone, 'online', 'new', p_fulfilment, v_addr, p_slot_date, p_slot,
          (q ->> 'subtotal_mrp')::numeric, (q ->> 'items_total')::numeric, (q ->> 'item_discount')::numeric,
          (q ->> 'cart_discount')::numeric, q ->> 'cart_offer', (q ->> 'coupon_id')::uuid,
          case when (q ->> 'coupon_id') is not null then q ->> 'coupon_code' end,
          (q ->> 'coupon_discount')::numeric, (q ->> 'delivery_charge')::numeric, (q ->> 'total')::numeric,
          (q ->> 'savings')::numeric, p_payment_method, left(nullif(trim(p_note), ''), 300), p_client_ref)
  returning id into v_order;

  for l in select * from jsonb_array_elements(q -> 'lines') loop
    insert into public.order_items (order_id, shop_id, product_id, variant_id, name, name_hi, label, unit, is_loose,
                                    qty, mrp, price, line_mrp, discount, line_total, free_qty, offer)
    values (v_order, p_shop, (l ->> 'product_id')::uuid, (l ->> 'variant_id')::uuid, l ->> 'name', l ->> 'name_hi',
            l ->> 'label', l ->> 'unit', (l ->> 'is_loose')::boolean, (l ->> 'qty')::numeric,
            (l ->> 'mrp')::numeric, (l ->> 'price')::numeric, (l ->> 'line_mrp')::numeric,
            (l ->> 'discount')::numeric, (l ->> 'line_total')::numeric, (l ->> 'free_qty')::numeric, l ->> 'offer');
    update public.product_variants set stock = stock - (l ->> 'qty')::numeric
     where id = (l ->> 'variant_id')::uuid and track_stock;
    if found then
      insert into public.stock_movements (shop_id, variant_id, delta, reason, order_id, by_user)
      values (p_shop, (l ->> 'variant_id')::uuid, -(l ->> 'qty')::numeric, 'sale', v_order, v_uid);
    end if;
  end loop;

  if (q ->> 'coupon_id') is not null then
    -- Count the use only while uses are left. The row lock makes orders that use the
    -- same coupon at the same moment wait in line, so "100 uses" can never become 103.
    update public.coupons set used_count = used_count + 1
     where id = (q ->> 'coupon_id')::uuid and (usage_limit is null or used_count < usage_limit);
    if not found then
      perform public.money_error('coupon_used_up', 'This coupon cannot be used');
    end if;
    -- Re-check this customer's own limit now that earlier orders in the line have finished.
    if (select count(*) from public.coupon_redemptions
         where coupon_id = (q ->> 'coupon_id')::uuid and user_id = v_uid)
       >= (select per_user_limit from public.coupons where id = (q ->> 'coupon_id')::uuid) then
      perform public.money_error('coupon_already_used', 'This coupon cannot be used');
    end if;
    insert into public.coupon_redemptions (coupon_id, user_id, order_id) values ((q ->> 'coupon_id')::uuid, v_uid, v_order);
  end if;
  insert into public.order_events (order_id, shop_id, status, by_user) values (v_order, p_shop, 'new', v_uid);

  return jsonb_build_object('order_id', v_order, 'order_no', v_no, 'total', q -> 'total', 'repeat', false);
end $$;
