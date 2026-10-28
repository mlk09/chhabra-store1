-- ═══════════════════════════════════════════════════════════════════════════
-- 0003 · Online orders: offers, coupons, addresses, orders, stock, pricing.
-- Every rupee a customer pays is decided HERE (price_cart), never by the app.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.shops
  add column timezone text not null default 'Asia/Kolkata',
  add column slot_lead_minutes int not null default 60 check (slot_lead_minutes between 0 and 600);

-- ── Offers (shown to everyone) ─────────────────────────────────────────────
-- product_percent / product_flat (₹ off per unit) / bxgy → one product
-- category_percent → every product in a category
-- cart_flat / cart_percent → whole cart above min_order
-- free_delivery → delivery free above min_order
create table public.offers (
  id           uuid primary key default gen_random_uuid(),
  shop_id      uuid not null references public.shops(id) on delete cascade,
  title        text not null check (char_length(title) between 2 and 80),
  title_hi     text check (char_length(title_hi) <= 80),
  kind         text not null check (kind in ('product_percent', 'product_flat', 'category_percent',
                                             'cart_flat', 'cart_percent', 'free_delivery', 'bxgy')),
  product_id   uuid references public.products(id) on delete cascade,
  category_id  uuid references public.categories(id) on delete cascade,
  percent      numeric(5,2) check (percent > 0 and percent <= 90),
  amount       numeric(10,2) check (amount > 0),
  min_order    numeric(10,2) not null default 0 check (min_order >= 0),
  max_discount numeric(10,2) check (max_discount > 0),
  buy_qty      int check (buy_qty between 1 and 20),
  get_qty      int check (get_qty between 1 and 20),
  starts_at    timestamptz,
  ends_at      timestamptz,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  constraint offer_target check (
    (kind in ('product_percent', 'product_flat', 'bxgy') and product_id is not null and category_id is null) or
    (kind = 'category_percent' and category_id is not null and product_id is null) or
    (kind in ('cart_flat', 'cart_percent', 'free_delivery') and product_id is null and category_id is null)),
  constraint offer_value check (
    (kind in ('product_percent', 'category_percent', 'cart_percent') and percent is not null) or
    (kind in ('product_flat', 'cart_flat') and amount is not null) or
    (kind = 'bxgy' and buy_qty is not null and get_qty is not null) or
    kind = 'free_delivery'),
  constraint offer_dates check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index on public.offers (shop_id, is_active);

-- ── Coupons (codes are secret unless is_public) ────────────────────────────
create table public.coupons (
  id             uuid primary key default gen_random_uuid(),
  shop_id        uuid not null references public.shops(id) on delete cascade,
  code           text not null check (code ~ '^[A-Z0-9]{3,20}$'),
  title          text check (char_length(title) <= 80),
  kind           text not null check (kind in ('percent', 'flat', 'free_delivery')),
  value          numeric(10,2) not null default 0 check (value >= 0),
  max_discount   numeric(10,2) check (max_discount > 0),
  min_order      numeric(10,2) not null default 0 check (min_order >= 0),
  starts_at      timestamptz,
  ends_at        timestamptz,
  usage_limit    int check (usage_limit > 0),
  per_user_limit int not null default 1 check (per_user_limit between 1 and 100),
  used_count     int not null default 0 check (used_count >= 0),
  is_public      boolean not null default false,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  unique (shop_id, code),
  constraint coupon_value check (
    (kind = 'percent' and value > 0 and value <= 90) or (kind = 'flat' and value > 0) or kind = 'free_delivery'),
  constraint coupon_dates check (ends_at is null or starts_at is null or ends_at > starts_at)
);

-- ── Customer addresses ─────────────────────────────────────────────────────
create table public.addresses (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  label      text check (char_length(label) <= 30),
  name       text not null check (char_length(name) between 2 and 80),
  phone      text not null check (phone ~ '^\+?[0-9]{10,13}$'),
  line1      text not null check (char_length(line1) between 3 and 200),
  line2      text check (char_length(line2) <= 200),
  landmark   text check (char_length(landmark) <= 100),
  pincode    text not null check (pincode ~ '^[1-9][0-9]{5}$'),
  lat        double precision,
  lng        double precision,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);
create index on public.addresses (user_id);

-- ── Orders ─────────────────────────────────────────────────────────────────
create table public.order_counters (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  last_no int not null default 0
);

create table public.orders (
  id              uuid primary key default gen_random_uuid(),
  shop_id         uuid not null references public.shops(id) on delete cascade,
  order_no        int not null,
  customer_id     uuid references auth.users(id) on delete set null,
  customer_name   text,
  customer_phone  text,
  channel         text not null default 'online' check (channel in ('online', 'counter')),
  status          text not null default 'new' check (status in ('new', 'accepted', 'packed', 'out_for_delivery',
                                                                'ready_for_pickup', 'delivered', 'cancelled')),
  fulfilment      text not null check (fulfilment in ('delivery', 'pickup')),
  address         jsonb,
  slot_date       date,
  slot            text,
  subtotal_mrp    numeric(12,2) not null,
  items_total     numeric(12,2) not null,
  item_discount   numeric(12,2) not null default 0,
  cart_discount   numeric(12,2) not null default 0,
  cart_offer      text,
  coupon_id       uuid references public.coupons(id) on delete set null,
  coupon_code     text,
  coupon_discount numeric(12,2) not null default 0,
  delivery_charge numeric(10,2) not null default 0,
  total           numeric(12,2) not null check (total >= 0),
  savings         numeric(12,2) not null default 0,
  payment_method  text not null check (payment_method in ('cod', 'upi_direct', 'gateway', 'cash', 'card', 'udhaar', 'split')),
  payment_status  text not null default 'pending' check (payment_status in ('pending', 'paid', 'failed', 'refunded')),
  note            text check (char_length(note) <= 300),
  cancel_reason   text check (char_length(cancel_reason) <= 200),
  cancelled_by    text check (cancelled_by in ('customer', 'shop')),
  client_ref      uuid unique,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (shop_id, order_no)
);
create index on public.orders (shop_id, created_at desc);
create index on public.orders (customer_id, created_at desc);
create trigger touch before update on public.orders for each row execute function public.touch_updated_at();

create table public.order_items (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders(id) on delete cascade,
  shop_id     uuid not null references public.shops(id) on delete cascade,
  product_id  uuid references public.products(id) on delete set null,
  variant_id  uuid references public.product_variants(id) on delete set null,
  name        text not null,
  name_hi     text,
  label       text not null,
  unit        text not null,
  is_loose    boolean not null default false,
  qty         numeric(10,3) not null check (qty > 0),
  mrp         numeric(10,2) not null,
  price       numeric(10,2) not null,
  line_mrp    numeric(12,2) not null,
  discount    numeric(12,2) not null default 0,
  line_total  numeric(12,2) not null,
  free_qty    numeric(10,3) not null default 0,
  offer       text,
  status      text not null default 'ok' check (status in ('ok', 'unavailable'))
);
create index on public.order_items (order_id);

create table public.order_events (
  id       bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  shop_id  uuid not null references public.shops(id) on delete cascade,
  status   text not null,
  note     text,
  by_user  uuid,
  at       timestamptz not null default now()
);
create index on public.order_events (order_id);

create table public.coupon_redemptions (
  coupon_id  uuid not null references public.coupons(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  order_id   uuid not null references public.orders(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (coupon_id, order_id)
);

create table public.stock_movements (
  id         bigint generated always as identity primary key,
  shop_id    uuid not null references public.shops(id) on delete cascade,
  variant_id uuid references public.product_variants(id) on delete set null,
  delta      numeric(12,3) not null,
  reason     text not null check (reason in ('sale', 'cancel', 'unavailable', 'restock', 'adjust')),
  order_id   uuid references public.orders(id) on delete set null,
  by_user    uuid,
  at         timestamptz not null default now()
);
create index on public.stock_movements (shop_id, at desc);

create table public.rate_hits (
  key          text not null,
  window_start timestamptz not null,
  count        int not null default 0,
  primary key (key, window_start)
);

-- ── Helpers ────────────────────────────────────────────────────────────────
create or replace function public.check_offer_shop() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.product_id is not null and not exists (
    select 1 from public.products p where p.id = new.product_id and p.shop_id = new.shop_id) then
    raise exception 'Product does not belong to this shop' using errcode = '23514';
  end if;
  if new.category_id is not null and not exists (
    select 1 from public.categories c where c.id = new.category_id and c.shop_id = new.shop_id) then
    raise exception 'Category does not belong to this shop' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger check_shop before insert or update on public.offers
  for each row execute function public.check_offer_shop();

-- Coupon codes are stored in capitals.
create or replace function public.upper_coupon_code() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.code := upper(trim(new.code));
  return new;
end $$;
create trigger upper_code before insert or update of code on public.coupons
  for each row execute function public.upper_coupon_code();

-- Fixed-window rate limit. True = allowed.
create or replace function public.hit_rate(p_key text, p_limit int, p_window_seconds int) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  w timestamptz := to_timestamp(floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds);
  n int;
begin
  insert into public.rate_hits (key, window_start, count) values (p_key, w, 1)
  on conflict (key, window_start) do update set count = public.rate_hits.count + 1
  returning count into n;
  delete from public.rate_hits where window_start < now() - interval '1 day';
  return n <= p_limit;
end $$;

create or replace function public.money_error(p_code text, p_message text, p_detail jsonb default '{}')
returns void language plpgsql set search_path = '' as $$
begin
  -- The app reads "code" from the JSON detail to show a friendly Hindi/English message.
  raise exception '%', p_message using errcode = 'P0001', detail = (jsonb_build_object('code', p_code) || p_detail)::text;
end $$;

-- ── THE pricing rules (one copy; lib/domain/pricing.dart mirrors it for demo/offline) ──
-- 1. Line = price × qty. Best ONE item offer (product %, product ₹/unit, category %, buy X get Y).
-- 2. Best ONE cart offer (flat / %) whose min_order ≤ items total.
-- 3. Coupon on top (min_order checked on items total).
-- 4. Delivery free above shop threshold / free-delivery offer / coupon; pickup = no charge.
-- Money rounded to paise, half away from zero.
create or replace function public.price_cart(
  p_shop uuid, p_items jsonb, p_coupon text, p_fulfilment text, p_user uuid, p_now timestamptz, p_lock boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  s            public.shops%rowtype;
  r            record;
  v            public.product_variants%rowtype;
  p            public.products%rowtype;
  o            public.offers%rowtype;
  c            public.coupons%rowtype;
  v_lines      jsonb := '[]';
  v_unavail    jsonb := '[]';
  v_base       numeric;
  v_line_mrp   numeric;
  v_best       numeric;
  v_title      text;
  v_free       numeric;
  v_d          numeric;
  v_fq         numeric;
  v_sub_mrp    numeric := 0;
  v_items      numeric := 0;
  v_item_disc  numeric := 0;
  v_cart_disc  numeric := 0;
  v_cart_offer text;
  v_after_cart numeric;
  v_code       text := nullif(upper(trim(coalesce(p_coupon, ''))), '');
  v_coupon_err text;
  v_coupon_id  uuid;
  v_coupon_d   numeric := 0;
  v_free_del   boolean := false;
  v_delivery   numeric := 0;
  v_del_saved  numeric := 0;
  v_after      numeric;
  v_count      int := 0;
begin
  select * into s from public.shops where id = p_shop;
  if not found then
    perform public.money_error('shop_not_found', 'Shop not found');
  end if;
  if p_fulfilment not in ('delivery', 'pickup') then
    perform public.money_error('bad_request', 'Choose delivery or pickup');
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then
    perform public.money_error('bad_request', 'Cart must have 1 to 100 items');
  end if;

  for r in
    select x.variant_id, sum(x.qty) as qty
    from jsonb_to_recordset(p_items) as x(variant_id uuid, qty numeric)
    group by x.variant_id
    order by x.variant_id
  loop
    if r.variant_id is null or r.qty is null or r.qty <= 0 or r.qty > 1000 then
      perform public.money_error('bad_quantity', 'Invalid quantity');
    end if;
    v := null;
    p := null;
    if p_lock then
      select * into v from public.product_variants where id = r.variant_id and shop_id = p_shop for update;
    else
      select * into v from public.product_variants where id = r.variant_id and shop_id = p_shop;
    end if;
    if v.id is not null then
      select * into p from public.products where id = v.product_id;
    end if;
    if v.id is null or not v.is_active or p.id is null or not p.is_active then
      v_unavail := v_unavail || jsonb_build_object('variant_id', r.variant_id, 'reason', 'unavailable', 'available', 0);
      continue;
    end if;
    if not p.is_loose and r.qty <> trunc(r.qty) then
      perform public.money_error('bad_quantity', 'Whole quantity needed for ' || p.name);
    end if;
    if v.track_stock and v.stock < r.qty then
      v_unavail := v_unavail || jsonb_build_object('variant_id', r.variant_id, 'reason', 'insufficient',
                                                   'available', v.stock, 'name', p.name, 'label', v.label);
      continue;
    end if;

    v_base := round(v.price * r.qty, 2);
    v_line_mrp := round(v.mrp * r.qty, 2);
    v_best := 0;
    v_title := null;
    v_free := 0;
    for o in
      select * from public.offers x
      where x.shop_id = p_shop and x.is_active
        and (x.starts_at is null or x.starts_at <= p_now) and (x.ends_at is null or x.ends_at > p_now)
        and ((x.product_id = p.id and x.kind in ('product_percent', 'product_flat', 'bxgy'))
             or (x.kind = 'category_percent' and x.category_id = p.category_id))
      order by x.created_at, x.id
    loop
      v_fq := 0;
      v_d := case o.kind
        when 'product_percent' then round(v_base * o.percent / 100, 2)
        when 'category_percent' then round(v_base * o.percent / 100, 2)
        when 'product_flat' then round(least(o.amount, v.price) * r.qty, 2)
        else 0 end;
      if o.kind = 'bxgy' and not p.is_loose then
        v_fq := floor(r.qty / (o.buy_qty + o.get_qty)) * o.get_qty;
        v_d := round(v_fq * v.price, 2);
      end if;
      if v_d > v_best then
        v_best := v_d;
        v_title := o.title;
        v_free := v_fq;
      end if;
    end loop;
    v_best := least(v_best, v_base);

    v_lines := v_lines || jsonb_build_object(
      'variant_id', v.id, 'product_id', p.id, 'name', p.name, 'name_hi', p.name_hi, 'label', v.label,
      'unit', v.unit, 'is_loose', p.is_loose, 'qty', r.qty, 'mrp', v.mrp, 'price', v.price,
      'line_mrp', v_line_mrp, 'discount', v_best, 'line_total', v_base - v_best, 'free_qty', v_free,
      'offer', v_title);
    v_sub_mrp := v_sub_mrp + v_line_mrp;
    v_items := v_items + v_base - v_best;
    v_item_disc := v_item_disc + v_best;
    v_count := v_count + 1;
  end loop;

  -- Best cart offer
  for o in
    select * from public.offers x
    where x.shop_id = p_shop and x.is_active and x.kind in ('cart_flat', 'cart_percent')
      and (x.starts_at is null or x.starts_at <= p_now) and (x.ends_at is null or x.ends_at > p_now)
      and x.min_order <= v_items
    order by x.created_at, x.id
  loop
    v_d := case o.kind
      when 'cart_flat' then least(o.amount, v_items)
      else least(round(v_items * o.percent / 100, 2), coalesce(o.max_discount, v_items)) end;
    if v_d > v_cart_disc then
      v_cart_disc := v_d;
      v_cart_offer := o.title;
    end if;
  end loop;
  v_after_cart := v_items - v_cart_disc;

  if exists (
    select 1 from public.offers x
    where x.shop_id = p_shop and x.is_active and x.kind = 'free_delivery' and x.min_order <= v_items
      and (x.starts_at is null or x.starts_at <= p_now) and (x.ends_at is null or x.ends_at > p_now)) then
    v_free_del := true;
  end if;

  -- Coupon
  if v_code is not null then
    select * into c from public.coupons where shop_id = p_shop and code = v_code;
    if not found or not c.is_active then
      v_coupon_err := 'invalid';
    elsif c.starts_at is not null and c.starts_at > p_now then
      v_coupon_err := 'not_started';
    elsif c.ends_at is not null and c.ends_at <= p_now then
      v_coupon_err := 'expired';
    elsif c.usage_limit is not null and c.used_count >= c.usage_limit then
      v_coupon_err := 'used_up';
    elsif p_user is null then
      v_coupon_err := 'login_required';
    elsif (select count(*) from public.coupon_redemptions x where x.coupon_id = c.id and x.user_id = p_user)
          >= c.per_user_limit then
      v_coupon_err := 'already_used';
    elsif v_items < c.min_order then
      v_coupon_err := 'min_order';
    else
      v_coupon_id := c.id;
      v_coupon_d := case c.kind
        when 'percent' then least(round(v_after_cart * c.value / 100, 2), coalesce(c.max_discount, v_after_cart))
        when 'flat' then least(c.value, v_after_cart)
        else 0 end;
      if c.kind = 'free_delivery' then
        v_free_del := true;
      end if;
    end if;
  end if;
  v_after := v_after_cart - v_coupon_d;

  if p_fulfilment = 'delivery' and v_count > 0 then
    if v_free_del or (s.free_delivery_above is not null and v_after_cart >= s.free_delivery_above) then
      v_del_saved := s.delivery_charge;
    else
      v_delivery := s.delivery_charge;
    end if;
  end if;

  return jsonb_build_object(
    'lines', v_lines,
    'unavailable', v_unavail,
    'subtotal_mrp', v_sub_mrp,
    'items_total', v_items,
    'item_discount', v_item_disc,
    'cart_discount', v_cart_disc,
    'cart_offer', v_cart_offer,
    'coupon_code', v_code,
    'coupon_id', v_coupon_id,
    'coupon_discount', v_coupon_d,
    'coupon_error', v_coupon_err,
    'coupon_min_order', case when v_coupon_err = 'min_order' then c.min_order end,
    'delivery_charge', v_delivery,
    'delivery_saved', v_del_saved,
    'total', v_after + v_delivery,
    'savings', (v_sub_mrp - v_after) + v_del_saved,
    'min_order', s.min_order,
    'below_min_order', p_fulfilment = 'delivery' and v_count > 0 and v_items < s.min_order
  );
end $$;

-- Public: cart preview. Coupon tries are rate-limited per user.
create or replace function public.quote_cart(p_shop uuid, p_items jsonb, p_coupon text default null,
                                             p_fulfilment text default 'delivery')
returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if nullif(trim(coalesce(p_coupon, '')), '') is not null and auth.uid() is not null
     and not public.hit_rate('coupon:' || auth.uid(), 30, 600) then
    perform public.money_error('rate_limited', 'Too many coupon tries. Please wait a few minutes.');
  end if;
  return public.price_cart(p_shop, p_items, p_coupon, p_fulfilment, auth.uid(), now(), false);
end $$;

-- Is this delivery slot valid right now (shop's local time)?
create or replace function public.slot_ok(p_shop uuid, p_date date, p_slot text, p_now timestamptz) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  s     public.shops%rowtype;
  local timestamp;
  start time;
begin
  select * into s from public.shops where id = p_shop;
  if p_slot is null or p_date is null or not (s.time_slots ? p_slot) or p_slot !~ '^\d{2}:\d{2}-\d{2}:\d{2}$' then
    return false;
  end if;
  local := p_now at time zone s.timezone;
  if p_date < local::date or p_date > local::date + 6 then
    return false;
  end if;
  start := split_part(p_slot, '-', 1)::time;
  if p_date = local::date and (p_date + start) - local < make_interval(mins => s.slot_lead_minutes) then
    return false;
  end if;
  return true;
end $$;

-- ── Customer places an order (one transaction: price, stock, coupon, order) ──
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
    update public.coupons set used_count = used_count + 1 where id = (q ->> 'coupon_id')::uuid;
    insert into public.coupon_redemptions (coupon_id, user_id, order_id) values ((q ->> 'coupon_id')::uuid, v_uid, v_order);
  end if;
  insert into public.order_events (order_id, shop_id, status, by_user) values (v_order, p_shop, 'new', v_uid);

  return jsonb_build_object('order_id', v_order, 'order_no', v_no, 'total', q -> 'total', 'repeat', false);
end $$;

-- Puts stock back for every still-"ok" item of an order.
create or replace function public.restock_order(p_order uuid, p_reason text, p_by uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  i public.order_items%rowtype;
begin
  for i in select * from public.order_items where order_id = p_order and status = 'ok' and variant_id is not null loop
    update public.product_variants set stock = stock + i.qty where id = i.variant_id and track_stock;
    if found then
      insert into public.stock_movements (shop_id, variant_id, delta, reason, order_id, by_user)
      values (i.shop_id, i.variant_id, i.qty, p_reason, p_order, p_by);
    end if;
  end loop;
end $$;

-- Shop moves an order forward; customer may only cancel a "new" order.
create or replace function public.set_order_status(p_order uuid, p_status text, p_note text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid   uuid := auth.uid();
  o       public.orders%rowtype;
  v_staff boolean;
  v_ok    boolean;
begin
  select * into o from public.orders where id = p_order for update;
  if not found then
    perform public.money_error('not_found', 'Order not found');
  end if;
  v_staff := public.has_perm(o.shop_id, 'orders');
  if not v_staff and not (o.customer_id = v_uid and p_status = 'cancelled' and o.status = 'new') then
    perform public.money_error('forbidden', 'You cannot change this order');
  end if;

  v_ok := case o.status
    when 'new' then p_status in ('accepted', 'cancelled')
    when 'accepted' then p_status in ('packed', 'cancelled')
    when 'packed' then p_status in ('cancelled', case o.fulfilment when 'delivery' then 'out_for_delivery' else 'ready_for_pickup' end)
    when 'out_for_delivery' then p_status in ('delivered', 'cancelled')
    when 'ready_for_pickup' then p_status in ('delivered', 'cancelled')
    else false end;
  if not v_ok then
    perform public.money_error('bad_status', 'This step is not possible now',
                               jsonb_build_object('from', o.status, 'to', p_status));
  end if;

  if p_status = 'cancelled' then
    perform public.restock_order(o.id, 'cancel', v_uid);
    if o.coupon_id is not null then
      delete from public.coupon_redemptions where order_id = o.id;
      update public.coupons set used_count = greatest(used_count - 1, 0) where id = o.coupon_id;
    end if;
    update public.orders set status = 'cancelled', cancel_reason = left(nullif(trim(p_note), ''), 200),
                             cancelled_by = case when v_staff and o.customer_id is distinct from v_uid then 'shop' else 'customer' end
     where id = o.id;
  elsif p_status = 'delivered' then
    update public.orders set status = 'delivered',
                             payment_status = case when payment_method = 'cod' then 'paid' else payment_status end
     where id = o.id;
  else
    update public.orders set status = p_status where id = o.id;
  end if;
  insert into public.order_events (order_id, shop_id, status, note, by_user)
  values (o.id, o.shop_id, p_status, left(nullif(trim(p_note), ''), 200), v_uid);
  return jsonb_build_object('status', p_status);
end $$;

-- Item out of stock while packing: customer simply doesn't pay for it.
-- (Discounts already given stay; the bill can only go down.)
create or replace function public.mark_item_unavailable(p_item uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  i public.order_items%rowtype;
  o public.orders%rowtype;
begin
  select * into i from public.order_items where id = p_item;
  if not found then
    perform public.money_error('not_found', 'Item not found');
  end if;
  select * into o from public.orders where id = i.order_id for update;
  if not public.has_perm(o.shop_id, 'orders') then
    perform public.money_error('forbidden', 'You cannot change this order');
  end if;
  if o.status not in ('new', 'accepted', 'packed') or i.status <> 'ok' then
    perform public.money_error('bad_status', 'This item cannot be changed now');
  end if;
  if (select count(*) from public.order_items where order_id = o.id and status = 'ok') <= 1 then
    perform public.money_error('last_item', 'This is the last item — cancel the order instead');
  end if;
  if i.variant_id is not null then
    update public.product_variants set stock = stock + i.qty where id = i.variant_id and track_stock;
    if found then
      insert into public.stock_movements (shop_id, variant_id, delta, reason, order_id, by_user)
      values (i.shop_id, i.variant_id, i.qty, 'unavailable', o.id, auth.uid());
    end if;
  end if;
  update public.order_items set status = 'unavailable' where id = i.id;
  update public.orders set
    items_total   = items_total - i.line_total,
    subtotal_mrp  = subtotal_mrp - i.line_mrp,
    item_discount = item_discount - i.discount,
    total         = greatest(total - i.line_total, 0),
    savings       = greatest(savings - (i.line_mrp - i.line_total), 0)
  where id = o.id;
  insert into public.order_events (order_id, shop_id, status, note, by_user)
  values (o.id, o.shop_id, 'item_unavailable', i.name || ' · ' || i.label, auth.uid());
  return (select jsonb_build_object('total', total) from public.orders where id = o.id);
end $$;

-- ── Row Level Security ─────────────────────────────────────────────────────
alter table public.offers             enable row level security;
alter table public.coupons            enable row level security;
alter table public.addresses          enable row level security;
alter table public.order_counters     enable row level security;
alter table public.orders             enable row level security;
alter table public.order_items        enable row level security;
alter table public.order_events       enable row level security;
alter table public.coupon_redemptions enable row level security;
alter table public.stock_movements    enable row level security;
alter table public.rate_hits          enable row level security;

create policy "live offers are public" on public.offers for select
  using (is_active or public.is_member(shop_id));
create policy "offer staff add" on public.offers for insert to authenticated with check (public.has_perm(shop_id, 'offers'));
create policy "offer staff edit" on public.offers for update to authenticated
  using (public.has_perm(shop_id, 'offers')) with check (public.has_perm(shop_id, 'offers'));
create policy "offer staff delete" on public.offers for delete to authenticated using (public.has_perm(shop_id, 'offers'));

create policy "public coupons are visible" on public.coupons for select
  using ((is_public and is_active) or public.has_perm(shop_id, 'offers'));
create policy "coupon staff add" on public.coupons for insert to authenticated with check (public.has_perm(shop_id, 'offers'));
create policy "coupon staff edit" on public.coupons for update to authenticated
  using (public.has_perm(shop_id, 'offers')) with check (public.has_perm(shop_id, 'offers'));
create policy "coupon staff delete" on public.coupons for delete to authenticated using (public.has_perm(shop_id, 'offers'));

create policy "own addresses" on public.addresses for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "own or shop orders" on public.orders for select to authenticated
  using (customer_id = auth.uid() or public.has_perm(shop_id, 'orders'));
create policy "own or shop order items" on public.order_items for select to authenticated
  using (public.has_perm(shop_id, 'orders')
         or exists (select 1 from public.orders o where o.id = order_id and o.customer_id = auth.uid()));
create policy "own or shop order events" on public.order_events for select to authenticated
  using (public.has_perm(shop_id, 'orders')
         or exists (select 1 from public.orders o where o.id = order_id and o.customer_id = auth.uid()));
create policy "stock history for product staff" on public.stock_movements for select to authenticated
  using (public.has_perm(shop_id, 'products'));
-- order_counters, coupon_redemptions, rate_hits: no policies → only server functions.

-- ── Grants ─────────────────────────────────────────────────────────────────
revoke all on public.offers, public.coupons, public.addresses, public.order_counters, public.orders,
              public.order_items, public.order_events, public.coupon_redemptions, public.stock_movements,
              public.rate_hits from anon, authenticated;
grant select on public.offers, public.coupons to anon, authenticated;
grant insert, update, delete on public.offers, public.coupons to authenticated;
grant select, insert, update, delete on public.addresses to authenticated;
grant select on public.orders, public.order_items, public.order_events, public.stock_movements to authenticated;
grant update (slot_lead_minutes) on public.shops to authenticated;

revoke execute on function public.check_offer_shop(), public.upper_coupon_code(), public.hit_rate(text, int, int),
  public.money_error(text, text, jsonb), public.price_cart(uuid, jsonb, text, text, uuid, timestamptz, boolean),
  public.quote_cart(uuid, jsonb, text, text), public.slot_ok(uuid, date, text, timestamptz),
  public.place_order(uuid, jsonb, text, text, date, text, uuid, text, text, uuid, numeric),
  public.restock_order(uuid, text, uuid), public.set_order_status(uuid, text, text),
  public.mark_item_unavailable(uuid)
  from public, anon, authenticated;
grant execute on function public.quote_cart(uuid, jsonb, text, text) to anon, authenticated;
grant execute on function public.place_order(uuid, jsonb, text, text, date, text, uuid, text, text, uuid, numeric),
                          public.set_order_status(uuid, text, text),
                          public.mark_item_unavailable(uuid)
  to authenticated;

-- Live updates: new orders for the shop, status changes for the customer (RLS applies).
alter publication supabase_realtime add table public.orders;
