-- Your shop + starter categories. Runs once from "setup-backend"; re-running is safe.
-- Change everything later inside the app (Shop settings), not here.
insert into public.shops (slug, name, name_hi, tagline, address, city, pincode, delivery_pincodes, delivery_radius_km)
values ('chhabra-general-store', 'Chhabra General Store', 'छाबड़ा जनरल स्टोर',
        'Fresh groceries, fair prices', 'Railway Road', 'Karnal', '132001', '{132001}', 3)
on conflict (slug) do nothing;

insert into public.categories (shop_id, name, name_hi, icon, sort_order)
select s.id, c.name, c.name_hi, c.icon, c.sort_order
from public.shops s
cross join (values
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
) as c(name, name_hi, icon, sort_order)
where s.slug = 'chhabra-general-store'
  and not exists (select 1 from public.categories x where x.shop_id = s.id);
