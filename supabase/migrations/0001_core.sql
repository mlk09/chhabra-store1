-- ═══════════════════════════════════════════════════════════════════════════
-- 0001 · Core: shop, people & roles, catalog (categories, products, variants)
-- Applied by the "setup-backend" GitHub Action. Safe to read; contains no secrets.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Shop ───────────────────────────────────────────────────────────────────
create table public.shops (
  id                  uuid primary key default gen_random_uuid(),
  slug                text not null unique check (slug ~ '^[a-z0-9-]{3,40}$'),
  name                text not null check (char_length(name) between 2 and 80),
  name_hi             text check (char_length(name_hi) <= 80),
  tagline             text check (char_length(tagline) <= 120),
  address             text check (char_length(address) <= 300),
  city                text check (char_length(city) <= 60),
  pincode             text check (pincode ~ '^[1-9][0-9]{5}$'),
  phone               text check (phone ~ '^\+?[0-9]{10,13}$'),
  whatsapp            text check (whatsapp ~ '^\+?[0-9]{10,13}$'),
  email               text check (char_length(email) <= 120),
  gstin               text check (gstin ~ '^[0-9]{2}[A-Z0-9]{13}$'),
  upi_id              text check (upi_id ~ '^[a-zA-Z0-9._-]{2,100}@[a-zA-Z]{2,64}$'),
  upi_name            text check (char_length(upi_name) <= 60),
  lat                 double precision,
  lng                 double precision,
  delivery_enabled    boolean not null default true,
  pickup_enabled      boolean not null default true,
  delivery_pincodes   text[] not null default '{}',
  delivery_radius_km  numeric(5,2) not null default 3 check (delivery_radius_km between 0 and 50),
  delivery_charge     numeric(10,2) not null default 0 check (delivery_charge >= 0),
  free_delivery_above numeric(10,2) check (free_delivery_above >= 0),
  min_order           numeric(10,2) not null default 0 check (min_order >= 0),
  open_time           time not null default '08:00',
  close_time          time not null default '21:30',
  is_open             boolean not null default true,
  holiday_mode        boolean not null default false,
  holiday_note        text check (char_length(holiday_note) <= 200),
  time_slots          jsonb not null default '["09:00-12:00","12:00-15:00","15:00-18:00","18:00-21:00"]',
  cod_enabled         boolean not null default true,
  upi_direct_enabled  boolean not null default true,
  gateway_enabled     boolean not null default false,
  gst_invoice_enabled boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- ── People ─────────────────────────────────────────────────────────────────
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text check (char_length(full_name) <= 80),
  phone      text check (phone ~ '^\+?[0-9]{10,13}$'),
  language   text not null default 'en' check (language in ('en', 'hi')),
  created_at timestamptz not null default now()
);

-- Absent from this table = customer.
-- Permissions: billing, orders, products, prices, offers, khata, reports, settings, staff
create table public.shop_members (
  shop_id     uuid not null references public.shops(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        text not null check (role in ('owner', 'staff')),
  permissions text[] not null default '{billing}',
  created_at  timestamptz not null default now(),
  primary key (shop_id, user_id)
);
create index on public.shop_members (user_id);

-- ── Catalog ────────────────────────────────────────────────────────────────
create table public.categories (
  id         uuid primary key default gen_random_uuid(),
  shop_id    uuid not null references public.shops(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 60),
  name_hi    text check (char_length(name_hi) <= 60),
  icon       text check (char_length(icon) <= 16),
  sort_order int not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.categories (shop_id, sort_order);

create table public.products (
  id              uuid primary key default gen_random_uuid(),
  shop_id         uuid not null references public.shops(id) on delete cascade,
  category_id     uuid references public.categories(id) on delete set null,
  name            text not null check (char_length(name) between 1 and 100),
  name_hi         text check (char_length(name_hi) <= 100),
  brand           text check (char_length(brand) <= 60),
  description     text check (char_length(description) <= 1000),
  image_path      text check (char_length(image_path) <= 300),
  thumb_path      text check (char_length(thumb_path) <= 300),
  is_loose        boolean not null default false,
  gst_rate        numeric(4,2) not null default 0 check (gst_rate between 0 and 40),
  hsn             text check (hsn ~ '^[0-9]{4,8}$'),
  synonyms        text[] not null default '{}' check (cardinality(synonyms) <= 20),
  low_stock_limit numeric(12,3) not null default 5 check (low_stock_limit >= 0),
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on public.products (shop_id, category_id);
create index on public.products (shop_id, updated_at);

-- Every product has at least one variant (the "size"): Atta 1 kg / 5 kg / 10 kg.
-- Loose item: unit = 'kg' (or 'l'), unit_qty = 1, price per kg; quantity 0.25 = 250 g.
create table public.product_variants (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references public.shops(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  label       text not null check (char_length(label) between 1 and 40),
  unit        text not null check (unit in ('kg', 'g', 'l', 'ml', 'pc', 'pack', 'dozen')),
  unit_qty    numeric(10,3) not null default 1 check (unit_qty > 0),
  mrp         numeric(10,2) not null check (mrp >= 0),
  price       numeric(10,2) not null check (price >= 0),
  barcode     text check (barcode ~ '^[0-9A-Za-z-]{4,32}$'),
  stock       numeric(12,3) not null default 0 check (stock >= 0),
  track_stock boolean not null default true,
  expiry_date date,
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Selling above MRP is illegal in India.
  constraint price_not_above_mrp check (price <= mrp)
);
create index on public.product_variants (product_id);
create index on public.product_variants (shop_id, updated_at);
create unique index product_variants_barcode_uq on public.product_variants (shop_id, barcode) where barcode is not null;

-- Purchase price lives in its own table so customers can never read it.
create table public.variant_costs (
  variant_id uuid primary key references public.product_variants(id) on delete cascade,
  shop_id    uuid not null references public.shops(id) on delete cascade,
  cost_price numeric(10,2) not null check (cost_price >= 0),
  updated_at timestamptz not null default now()
);
create index on public.variant_costs (shop_id);

-- ── Helpers ────────────────────────────────────────────────────────────────
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger touch before update on public.shops for each row execute function public.touch_updated_at();
create trigger touch before update on public.categories for each row execute function public.touch_updated_at();
create trigger touch before update on public.products for each row execute function public.touch_updated_at();
create trigger touch before update on public.product_variants for each row execute function public.touch_updated_at();
create trigger touch before update on public.variant_costs for each row execute function public.touch_updated_at();

-- True for the shop owner, or for staff who were given this permission.
-- SECURITY DEFINER so policies can call it without recursive RLS on shop_members.
create or replace function public.has_perm(p_shop uuid, p_perm text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.shop_members m
    where m.shop_id = p_shop
      and m.user_id = auth.uid()
      and (m.role = 'owner' or p_perm = any (m.permissions))
  )
$$;

create or replace function public.is_member(p_shop uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.shop_members m
    where m.shop_id = p_shop and m.user_id = auth.uid()
  )
$$;

create or replace function public.try_uuid(p text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin
  return p::uuid;
exception when others then
  return null;
end $$;

-- New sign-up → profile row.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    left(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 80),
    case when (new.raw_user_meta_data ->> 'phone') ~ '^\+?[0-9]{10,13}$'
         then new.raw_user_meta_data ->> 'phone' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Staff without the "prices" permission may edit stock, photo, name…
-- but not MRP / selling price, and may not create new priced variants.
create or replace function public.guard_price_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  if auth.uid() is null then
    return new;            -- service role / SQL editor
  end if;
  if tg_op = 'INSERT' or new.price is distinct from old.price or new.mrp is distinct from old.mrp then
    if not public.has_perm(new.shop_id, 'prices') then
      raise exception 'You do not have permission to change prices' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create trigger guard_price before insert or update on public.product_variants
  for each row execute function public.guard_price_change();

-- shop_id on a variant / cost must match its parent, so nobody can attach rows
-- to another shop's product.
create or replace function public.check_variant_shop() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.products p where p.id = new.product_id and p.shop_id = new.shop_id) then
    raise exception 'Product does not belong to this shop' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger check_shop before insert or update of shop_id, product_id on public.product_variants
  for each row execute function public.check_variant_shop();

create or replace function public.check_cost_shop() returns trigger
language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.product_variants v where v.id = new.variant_id and v.shop_id = new.shop_id) then
    raise exception 'Variant does not belong to this shop' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger check_shop before insert or update on public.variant_costs
  for each row execute function public.check_cost_shop();

create or replace function public.check_product_category() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.category_id is not null and not exists (
    select 1 from public.categories c where c.id = new.category_id and c.shop_id = new.shop_id
  ) then
    raise exception 'Category does not belong to this shop' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger check_category before insert or update of shop_id, category_id on public.products
  for each row execute function public.check_product_category();

-- ── Row Level Security ─────────────────────────────────────────────────────
alter table public.shops            enable row level security;
alter table public.profiles         enable row level security;
alter table public.shop_members     enable row level security;
alter table public.categories       enable row level security;
alter table public.products         enable row level security;
alter table public.product_variants enable row level security;
alter table public.variant_costs    enable row level security;

create policy "shop is public" on public.shops for select using (true);
create policy "owner edits shop" on public.shops for update to authenticated
  using (public.has_perm(id, 'settings')) with check (public.has_perm(id, 'settings'));

create policy "own profile" on public.profiles for select to authenticated using (id = auth.uid());
create policy "edit own profile" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy "see own membership or staff list" on public.shop_members for select to authenticated
  using (user_id = auth.uid() or public.has_perm(shop_id, 'staff'));

create policy "active categories are public" on public.categories for select
  using (is_active or public.is_member(shop_id));
create policy "staff add categories" on public.categories for insert to authenticated
  with check (public.has_perm(shop_id, 'products'));
create policy "staff edit categories" on public.categories for update to authenticated
  using (public.has_perm(shop_id, 'products')) with check (public.has_perm(shop_id, 'products'));
create policy "staff delete categories" on public.categories for delete to authenticated
  using (public.has_perm(shop_id, 'products'));

create policy "active products are public" on public.products for select
  using (is_active or public.is_member(shop_id));
create policy "staff add products" on public.products for insert to authenticated
  with check (public.has_perm(shop_id, 'products'));
create policy "staff edit products" on public.products for update to authenticated
  using (public.has_perm(shop_id, 'products')) with check (public.has_perm(shop_id, 'products'));
create policy "staff delete products" on public.products for delete to authenticated
  using (public.has_perm(shop_id, 'products'));

create policy "active variants are public" on public.product_variants for select
  using (
    (is_active and exists (select 1 from public.products p where p.id = product_id and p.is_active))
    or public.is_member(shop_id)
  );
create policy "staff add variants" on public.product_variants for insert to authenticated
  with check (public.has_perm(shop_id, 'products'));
create policy "staff edit variants" on public.product_variants for update to authenticated
  using (public.has_perm(shop_id, 'products')) with check (public.has_perm(shop_id, 'products'));
create policy "staff delete variants" on public.product_variants for delete to authenticated
  using (public.has_perm(shop_id, 'products'));

create policy "cost visible to price/report staff" on public.variant_costs for select to authenticated
  using (public.has_perm(shop_id, 'prices') or public.has_perm(shop_id, 'reports'));
create policy "price staff add cost" on public.variant_costs for insert to authenticated
  with check (public.has_perm(shop_id, 'prices'));
create policy "price staff edit cost" on public.variant_costs for update to authenticated
  using (public.has_perm(shop_id, 'prices')) with check (public.has_perm(shop_id, 'prices'));
create policy "price staff delete cost" on public.variant_costs for delete to authenticated
  using (public.has_perm(shop_id, 'prices'));

-- ── Grants (explicit; never rely on Supabase's broad defaults) ─────────────
revoke all on all tables in schema public from anon, authenticated;
grant select on public.shops, public.categories, public.products, public.product_variants to anon, authenticated;
grant update (name, name_hi, tagline, address, city, pincode, phone, whatsapp, email, gstin, upi_id, upi_name,
              lat, lng, delivery_enabled, pickup_enabled, delivery_pincodes, delivery_radius_km,
              delivery_charge, free_delivery_above, min_order, open_time, close_time, is_open,
              holiday_mode, holiday_note, time_slots, cod_enabled, upi_direct_enabled,
              gateway_enabled, gst_invoice_enabled)
  on public.shops to authenticated;
grant select on public.profiles to authenticated;
grant update (full_name, phone, language) on public.profiles to authenticated;
grant select on public.shop_members to authenticated;
grant insert, update, delete on public.categories, public.products, public.product_variants to authenticated;
grant select, insert, update, delete on public.variant_costs to authenticated;

-- ── Owner tools ────────────────────────────────────────────────────────────
-- "Raise all oil prices 5%": percent between -50 and +100, rounded to the
-- nearest rupee (or 50 paise). Selling price never goes above MRP.
create or replace function public.bulk_update_prices(
  p_shop uuid,
  p_percent numeric,
  p_category uuid default null,
  p_product_ids uuid[] default null,
  p_apply_to text default 'both',      -- 'price' | 'mrp' | 'both'
  p_round text default 'rupee'         -- 'none' | 'fifty' | 'rupee'
) returns int
language plpgsql security invoker set search_path = '' as $$
declare
  n int;
begin
  if not public.has_perm(p_shop, 'prices') then
    raise exception 'You do not have permission to change prices' using errcode = '42501';
  end if;
  if p_percent is null or p_percent < -50 or p_percent > 100 or p_percent = 0 then
    raise exception 'Percent must be between -50 and 100' using errcode = '22023';
  end if;
  if p_apply_to not in ('price', 'mrp', 'both') or p_round not in ('none', 'fifty', 'rupee') then
    raise exception 'Invalid option' using errcode = '22023';
  end if;

  with target as (
    select v.id, v.price, v.mrp
    from public.product_variants v
    join public.products p on p.id = v.product_id
    where v.shop_id = p_shop
      and (p_category is null or p.category_id = p_category)
      and (p_product_ids is null or p.id = any (p_product_ids))
    for update of v
  ), calc as (
    select id,
      case when p_apply_to in ('mrp', 'both') then public.round_money(mrp * (1 + p_percent / 100), p_round) else mrp end as new_mrp,
      case when p_apply_to in ('price', 'both') then public.round_money(price * (1 + p_percent / 100), p_round) else price end as new_price
    from target
  )
  update public.product_variants v
     set mrp = c.new_mrp,
         price = least(c.new_price, c.new_mrp)
    from calc c
   where v.id = c.id;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.round_money(p numeric, p_mode text) returns numeric
language sql immutable set search_path = '' as $$
  select case p_mode
    when 'rupee' then round(p)
    when 'fifty' then round(p * 2) / 2
    else round(p, 2)
  end
$$;

-- In-app "Delete my account" (required by Google Play).
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'Not logged in' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

-- Save a product with all its sizes in ONE transaction (all or nothing).
-- Runs with the caller's rights, so RLS + the price guard still apply.
-- A variant's "stock" is only changed when the key is sent, so an old edit
-- screen can't overwrite sales that happened meanwhile.
create or replace function public.save_product(p_product jsonb, p_variants jsonb, p_with_costs boolean default false)
returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  v_shop uuid := (p_product ->> 'shop_id')::uuid;
  v_id   uuid := coalesce((p_product ->> 'id')::uuid, gen_random_uuid());
  v      jsonb;
  v_vid  uuid;
  v_keep uuid[] := '{}';
  v_syn  text[] := coalesce(array(select jsonb_array_elements_text(p_product -> 'synonyms')), '{}');
begin
  if not public.has_perm(v_shop, 'products') then
    raise exception 'You do not have permission to edit products' using errcode = '42501';
  end if;
  if jsonb_typeof(p_variants) is distinct from 'array' or jsonb_array_length(p_variants) not between 1 and 30 then
    raise exception 'A product needs 1 to 30 sizes' using errcode = '22023';
  end if;

  if exists (select 1 from public.products where id = v_id) then
    update public.products set
      category_id     = (p_product ->> 'category_id')::uuid,
      name            = trim(p_product ->> 'name'),
      name_hi         = nullif(trim(p_product ->> 'name_hi'), ''),
      brand           = nullif(trim(p_product ->> 'brand'), ''),
      description     = nullif(trim(p_product ->> 'description'), ''),
      image_path      = p_product ->> 'image_path',
      thumb_path      = p_product ->> 'thumb_path',
      is_loose        = coalesce((p_product ->> 'is_loose')::boolean, false),
      gst_rate        = coalesce((p_product ->> 'gst_rate')::numeric, 0),
      hsn             = nullif(trim(p_product ->> 'hsn'), ''),
      synonyms        = v_syn,
      low_stock_limit = coalesce((p_product ->> 'low_stock_limit')::numeric, 5),
      is_active       = coalesce((p_product ->> 'is_active')::boolean, true)
    where id = v_id and shop_id = v_shop;
    if not found then
      raise exception 'Product not found' using errcode = 'P0002';
    end if;
  else
    insert into public.products (id, shop_id, category_id, name, name_hi, brand, description, image_path,
                                 thumb_path, is_loose, gst_rate, hsn, synonyms, low_stock_limit, is_active)
    values (v_id, v_shop, (p_product ->> 'category_id')::uuid, trim(p_product ->> 'name'),
            nullif(trim(p_product ->> 'name_hi'), ''), nullif(trim(p_product ->> 'brand'), ''),
            nullif(trim(p_product ->> 'description'), ''), p_product ->> 'image_path', p_product ->> 'thumb_path',
            coalesce((p_product ->> 'is_loose')::boolean, false), coalesce((p_product ->> 'gst_rate')::numeric, 0),
            nullif(trim(p_product ->> 'hsn'), ''), v_syn,
            coalesce((p_product ->> 'low_stock_limit')::numeric, 5), coalesce((p_product ->> 'is_active')::boolean, true));
  end if;

  for v in select * from jsonb_array_elements(p_variants) loop
    v_vid := coalesce((v ->> 'id')::uuid, gen_random_uuid());
    if exists (select 1 from public.product_variants where id = v_vid and product_id = v_id) then
      update public.product_variants set
        label       = trim(v ->> 'label'),
        unit        = v ->> 'unit',
        unit_qty    = coalesce((v ->> 'unit_qty')::numeric, 1),
        mrp         = (v ->> 'mrp')::numeric,
        price       = (v ->> 'price')::numeric,
        barcode     = nullif(trim(v ->> 'barcode'), ''),
        stock       = case when v ? 'stock' then (v ->> 'stock')::numeric else stock end,
        track_stock = coalesce((v ->> 'track_stock')::boolean, true),
        expiry_date = (v ->> 'expiry_date')::date,
        sort_order  = coalesce((v ->> 'sort_order')::int, 0),
        is_active   = coalesce((v ->> 'is_active')::boolean, true)
      where id = v_vid;
    else
      insert into public.product_variants (id, shop_id, product_id, label, unit, unit_qty, mrp, price, barcode,
                                           stock, track_stock, expiry_date, sort_order, is_active)
      values (v_vid, v_shop, v_id, trim(v ->> 'label'), v ->> 'unit', coalesce((v ->> 'unit_qty')::numeric, 1),
              (v ->> 'mrp')::numeric, (v ->> 'price')::numeric, nullif(trim(v ->> 'barcode'), ''),
              coalesce((v ->> 'stock')::numeric, 0), coalesce((v ->> 'track_stock')::boolean, true),
              (v ->> 'expiry_date')::date, coalesce((v ->> 'sort_order')::int, 0),
              coalesce((v ->> 'is_active')::boolean, true));
    end if;
    v_keep := v_keep || v_vid;

    if p_with_costs and public.has_perm(v_shop, 'prices') then
      if nullif(v ->> 'cost_price', '') is null then
        delete from public.variant_costs where variant_id = v_vid;
      else
        insert into public.variant_costs (variant_id, shop_id, cost_price)
        values (v_vid, v_shop, (v ->> 'cost_price')::numeric)
        on conflict (variant_id) do update set cost_price = excluded.cost_price;
      end if;
    end if;
  end loop;

  delete from public.product_variants where product_id = v_id and id <> all (v_keep);
  return v_id;
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.has_perm(uuid, text), public.is_member(uuid), public.try_uuid(text)
  to anon, authenticated;
grant execute on function public.bulk_update_prices(uuid, numeric, uuid, uuid[], text, text),
                          public.round_money(numeric, text),
                          public.delete_my_account(),
                          public.save_product(jsonb, jsonb, boolean)
  to authenticated;

-- ── Storage: product photos ────────────────────────────────────────────────
-- Path: <shop_id>/<product_id>/<file>.jpg — public read, upload by product staff.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 2097152, array['image/jpeg', 'image/webp', 'image/png'])
on conflict (id) do update set public = excluded.public,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "product staff upload images" on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images'
              and public.has_perm(public.try_uuid((storage.foldername(name))[1]), 'products'));
create policy "product staff update images" on storage.objects for update to authenticated
  using (bucket_id = 'product-images'
         and public.has_perm(public.try_uuid((storage.foldername(name))[1]), 'products'));
create policy "product staff delete images" on storage.objects for delete to authenticated
  using (bucket_id = 'product-images'
         and public.has_perm(public.try_uuid((storage.foldername(name))[1]), 'products'));
