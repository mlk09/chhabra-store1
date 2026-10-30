-- ═══════════════════════════════════════════════════════════════════════════
-- 0004 · Many shops on one platform (sold as a monthly service).
--  • service_status: the platform (you) can pause a shop, e.g. unpaid fees.
--    A paused shop stays visible but takes no new orders.
--  • brand_color / logo_path: each shop's own look inside the app.
--  • seed_shop(): adds a shop + starter categories (used by "add-shop").
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.shops
  add column service_status text not null default 'active' check (service_status in ('active', 'paused')),
  add column service_note   text check (char_length(service_note) <= 200),
  add column paid_until     date,
  add column brand_color    text check (brand_color ~ '^#[0-9A-Fa-f]{6}$'),
  add column logo_path      text check (char_length(logo_path) <= 300),
  add column listed         boolean not null default true;

-- Owners may change their look; service fields are only for the platform (no grant).
grant update (brand_color, logo_path) on public.shops to authenticated;

-- No new orders while the platform has paused the shop (covers every way an order is made).
create or replace function public.check_shop_service() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (select service_status from public.shops where id = new.shop_id) = 'paused' then
    perform public.money_error('service_paused', 'This shop is not taking orders right now');
  end if;
  return new;
end $$;
create trigger check_service before insert on public.orders
  for each row execute function public.check_shop_service();

-- Adds a shop if its slug is new, plus 10 starter categories. Never overwrites
-- a shop that already exists (the owner may have edited it in the app).
create or replace function public.seed_shop(p jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  insert into public.shops (slug, name, name_hi, tagline, address, city, pincode, phone, delivery_pincodes,
                            delivery_radius_km, brand_color)
  values (p ->> 'slug', p ->> 'name', nullif(p ->> 'name_hi', ''), nullif(p ->> 'tagline', ''),
          nullif(p ->> 'address', ''), nullif(p ->> 'city', ''), nullif(p ->> 'pincode', ''),
          nullif(p ->> 'phone', ''),
          coalesce(array(select jsonb_array_elements_text(p -> 'delivery_pincodes')), '{}'),
          coalesce((p ->> 'delivery_radius_km')::numeric, 3), nullif(p ->> 'brand_color', ''))
  on conflict (slug) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.shops where slug = p ->> 'slug';
    return v_id;   -- existing shop: leave it alone
  end if;

  insert into public.categories (shop_id, name, name_hi, icon, sort_order)
  select v_id, c.name, c.name_hi, c.icon, c.sort_order
  from (values
    ('Atta, Rice & Dal', 'आटा, चावल और दाल', '🌾', 1),
    ('Oil & Ghee', 'तेल और घी', '🫙', 2),
    ('Masala & Spices', 'मसाले', '🌶️', 3),
    ('Sugar, Salt & Jaggery', 'चीनी, नमक और गुड़', '🧂', 4),
    ('Dairy & Bread', 'दूध और ब्रेड', '🥛', 5),
    ('Fruits & Vegetables', 'फल और सब्ज़ियाँ', '🥬', 6),
    ('Snacks & Biscuits', 'नमकीन और बिस्कुट', '🍪', 7),
    ('Tea, Coffee & Drinks', 'चाय, कॉफ़ी और पेय', '☕', 8),
    ('Personal Care', 'पर्सनल केयर', '🧴', 9),
    ('Cleaning & Household', 'सफ़ाई और घरेलू', '🧹', 10)
  ) as c(name, name_hi, icon, sort_order);
  return v_id;
end $$;

revoke execute on function public.check_shop_service(), public.seed_shop(jsonb) from public, anon, authenticated;
