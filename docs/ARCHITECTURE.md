# Chhabra General Store — Architecture

छाबड़ा जनरल स्टोर · Railway Road, Karnal · Delivery: pincode 132001 or within 3 km

One Flutter app, two roles:

| Role | What they do |
|---|---|
| **Owner** | Everything: products, prices, offers, orders, billing, khata, reports, staff, settings |
| **Staff** | Only what the owner allows (billing / orders / products / khata). Price change and reports are off by default |
| **Customer** | Browse, cart, coupons, pay, track orders, address book |
| **Demo** | No login, no internet. Sample shop on the phone, switch between Customer and Shopkeeper views |

Platforms: Android (APK + AAB), Web/PWA on GitHub Pages (iPhone users + shopkeeper on a computer). iOS later.

---

## 1. Folder structure

```
chhabra_store/
├─ lib/
│  ├─ main.dart                 startup with timeouts → never a white screen
│  ├─ app.dart                  MaterialApp.router, theme, language
│  ├─ core/
│  │  ├─ config.dart            values from --dart-define (URL, anon key only)
│  │  ├─ theme.dart             dark (default) + light, green/saffron
│  │  ├─ money.dart             paise (int) helpers, ₹ formatting
│  │  ├─ i18n.dart              English / Hindi strings
│  │  ├─ router.dart            go_router + role-based redirects
│  │  └─ widgets/               shared UI (price tag, product image, empty/error states)
│  ├─ data/
│  │  ├─ models/                Shop, Category, Product, Variant, Offer, Order …
│  │  ├─ repositories/          abstract interfaces
│  │  ├─ demo/                  in-memory demo implementation + sample catalog
│  │  ├─ supabase/              real implementation
│  │  └─ local/                 Hive cache + offline outbox (counter bills)
│  ├─ domain/
│  │  ├─ pricing.dart           Dart copy of the pricing rules (offline billing / demo only)
│  │  └─ search.dart            Hinglish synonyms (aloo = potato, cheeni = sugar). Search runs
│  │                            on the phone over the cached catalog, so it is instant and offline
│  └─ features/
│     ├─ startup/  auth/  demo/
│     ├─ owner/   products/ categories/ offers/ orders/ billing/ khata/ reports/ staff/ settings/
│     ├─ customer/ home/ catalog/ product/ cart/ checkout/ orders/ addresses/
│     └─ legal/   privacy, terms, refund, account deletion
├─ supabase/
│  ├─ migrations/               0001_core.sql, 0002_orders.sql … (applied by GitHub Action)
│  ├─ seed/                     shop row + starter categories
│  ├─ tests/                    RLS tests + pricing tests (plain SQL, run in CI on Postgres)
│  └─ functions/                Edge Functions (Deno): razorpay-create-order,
│                               razorpay-verify, razorpay-webhook, razorpay-refund, delete-account
├─ test/                        Dart unit + widget tests
├─ test_vectors/pricing.json    SAME cases checked by Dart tests AND SQL tests
├─ web_download/                download landing page + QR (GitHub Pages root)
├─ .github/workflows/           build, release, setup-backend, make-owner,
│                               create-signing-key, keep-alive
└─ docs/                        this file, privacy-policy, play-store checklist
```

**Why two copies of the pricing rules?** The real price is always computed by Postgres. The Dart copy exists only so the counter can keep billing when the internet is down and so Demo mode works. When the offline bill syncs, the server recalculates it. Both copies run the same test file (`test_vectors/pricing.json`), so they can't drift apart silently.

---

## 2. Database tables (Postgres on Supabase)

Money = `numeric(12,2)` rupees on the server and integer **paise** in Dart (no floating-point errors). Quantity = `numeric(10,3)`, so 0.250 kg works.

### Phase 1
| Table | Key columns | Notes |
|---|---|---|
| `shops` | name, name_hi, address, phone, gstin, upi_id, delivery_pincodes[], delivery_radius_km, lat/lng, delivery_charge, free_delivery_above, min_order, open/close time, is_open, holiday_mode, cod/upi/gateway toggles | One row today. Every other table has `shop_id`, so more shops can be added later |
| `profiles` | id (= auth user), full_name, phone, language | Created automatically on signup |
| `shop_members` | shop_id, user_id, role (owner/staff), permissions jsonb | Absent = customer |
| `categories` | name, name_hi, icon, sort_order, is_active | |
| `products` | category_id, name, name_hi, brand, image_path, thumb_path, is_loose, gst_rate, hsn, synonyms[] (extra search words), low_stock_limit, is_active | |
| `product_variants` | product_id, label ("5 kg"), unit, unit_qty, mrp, price, barcode, stock, expiry_date, is_active | Every product has ≥ 1 variant. Loose item = unit `kg`, price per kg, customer buys 0.25 |
| `variant_costs` | variant_id, cost_price | **Separate table** so customers can never read purchase price |

### Phase 2
| `offers` | type (product % / ₹, category %, cart flat / %, free delivery, buy X get Y), min_order, dates, active |
| `coupons` | code, type, value, max_discount, min_order, dates, usage_limit, per_user_limit, used_count |
| `coupon_redemptions` | coupon_id, user_id, order_id |
| `addresses` | user_id, name, phone, line1, landmark, pincode, lat/lng |
| `orders` | order_no, customer_id, channel (online/counter), status, fulfilment, address snapshot, slot, all totals, coupon_code, payment_method, payment_status, client_ref (unique → offline sync can't double-insert) |
| `order_items` | snapshot of name/label/price at order time, qty, discount, free_qty, status (ok/unavailable) |
| `order_events` | status timeline for tracking |
| `stock_movements` | every stock change with reason (sale, cancel, restock, adjust) |

### Phase 3–5
| `payments` | method, amount, status, razorpay_order_id, razorpay_payment_id, verified, refund_id |
| `khata_customers` | name, phone, credit_limit, balance (kept up to date by trigger) |
| `khata_entries` | credit (udhaar given) / payment (received), amount, order_id, note, client_ref |
| `rate_limits` | key, window, count (coupon attempts, order spam) |

### Server functions (all prices are decided here)
| Function | Who | What |
|---|---|---|
| `quote_cart(items, coupon, fulfilment, pincode)` | anyone | Returns lines, discounts, delivery, total, "you saved". Read only |
| `place_order(...)` | logged-in customer | Same maths + locks rows + checks stock + deducts stock + creates order, all in one transaction |
| `counter_checkout(...)` | staff with billing | Counter bill, idempotent by client_ref (safe for offline re-sync) |
| `set_order_status`, `mark_item_unavailable` | staff with orders | Validated status changes; cancel puts stock back; unavailable item re-prices the order |
| `confirm_upi_payment` | owner/staff | Marks a direct-UPI order paid after checking the bank app |
| `save_product(product, sizes)` | staff with products | Product + all sizes + cost in one transaction |
| `bulk_update_prices(filter, percent)` | owner / prices | "All oil +5%" |
| `delete_my_account()` | anyone logged in | Play Store account deletion |
| `add_staff(email, permissions)` | owner | |
| `sales_report`, `top_products`, `payment_split` | owner / reports permission | |

Stock can never go negative: a `CHECK (stock >= 0)` constraint plus `SELECT … FOR UPDATE` inside the order function.

---

## 3. Row Level Security (RLS) — on every table

Helper: `is_member(shop_id, permission)` → true for the owner, or staff whose permissions include it.

| Table | Customer / visitor | Staff | Owner |
|---|---|---|---|
| shops | read | read | read + update |
| categories, products, product_variants | read **active** rows only | read all; write if `products` permission. Changing mrp/price needs `prices` (enforced by trigger) | all |
| variant_costs | ✗ | ✗ (unless `reports`) | all |
| offers | read active | read | all |
| coupons | ✗ (checked only inside `quote_cart`, so codes can't be listed) | read | all |
| addresses | own only | ✗ | ✗ (order keeps an address snapshot) |
| orders, order_items, order_events | own orders only, read | shop orders with `orders` / `billing` | all |
| payments | own, read | read | read |
| khata_* | ✗ | with `khata` permission | all |
| profiles | own | ✗ | ✗ |
| shop_members | own row | own row | all for the shop |

Nobody can INSERT/UPDATE orders, payments or stock directly. Those go only through the server functions above. Storage bucket `product-images`: public read, upload only by members with `products` permission.

**Who becomes owner?** Sign up in the app with your email, then run GitHub Action **make-owner** with that email. (A "first person to sign up becomes owner" rule would let a stranger take your shop.)

---

## 4. Screens

**Common:** Splash (3-second safety timeout) → Welcome (Login / Sign up / Try Demo) → Startup error screen with Retry · Settings (language, theme, text size) · Privacy · Terms · Refund policy · Delete account

**Customer**
1. Home: offer banner, categories, search, "Buy again"
2. Category / search results: quick-commerce product grid
3. Product: MRP crossed out, price, % off, variants, stock status
4. Cart: coupon, savings, delivery charge, server total
5. Checkout: address / pickup, time slot, payment choice
6. Order tracking (live) · Order history · Reorder
7. Addresses · Profile

**Shopkeeper (Owner / Staff)**
1. Dashboard: today's sales, new orders, low stock, near expiry
2. Products: search, filter, add/edit (photo, variants, loose, barcode), bulk price update, CSV import/export
3. Categories
4. Offers & coupons
5. Orders: live list with sound, order detail, status buttons, item unavailable
6. Counter billing (POS): scan / search, qty keypad, payment modes, split, bill PDF / WhatsApp / 58 mm printer
7. Khata: customer list with balance, ledger, record payment, WhatsApp reminder
8. Reports + export
9. Staff & permissions
10. Shop settings: delivery, hours, holiday mode, payments (UPI ID, Razorpay on/off, COD), GST

---

## 5. Payment flows

### A. Direct UPI (free, no gateway)
```
Customer app ──place_order()──► Postgres: order created, total decided by server,
                                payment_status = PENDING
Customer app ──upi://pay?pa=<shop UPI>&am=<server total>&tn=Order-123──► GPay / PhonePe / Paytm
Customer pays in their UPI app (the app CANNOT see whether it succeeded)
Shopkeeper sees "Payment pending ₹245 – Order 123" ──checks bank SMS / UPI app──►
taps "Payment received" ──confirm_upi_payment()──► PAID
```
**Limitation:** UPI apps don't reliably report back to a third-party app. The customer can even press "back" and say they paid. So the order stays **Payment pending** until you confirm it. That's fine for a neighbourhood shop, but always check your bank/UPI app before handing over the goods.

### B. Razorpay (auto-verified)
```
1. App ──► Edge Function razorpay-create-order (user's login token)
             └─ reads order total FROM DATABASE (never from the app)
             └─ calls Razorpay API with RAZORPAY_KEY_SECRET (Supabase Secret)
             ◄─ razorpay_order_id
2. App opens Razorpay Checkout (key_id only — public) → customer pays
3. App ──► Edge Function razorpay-verify (order_id, payment_id, signature)
             └─ HMAC-SHA256 check with secret → payment_status = PAID
4. Razorpay ──webhook──► Edge Function razorpay-webhook
             └─ checks X-Razorpay-Signature with RAZORPAY_WEBHOOK_SECRET
             └─ marks PAID even if the customer's phone died after paying (backup path)
5. Cancel a paid order ──► Edge Function razorpay-refund ──► refund_id saved, status REFUNDED
```
Test mode first (test keys + Razorpay's test UPI ID/cards). Card details never touch our app or database.

### C. Cash on Delivery
Toggle in settings. Order is created with payment_status = PENDING. Delivery partner/shopkeeper marks **Paid (cash)** on delivery.

---

## 6. Offline counter billing
- Catalog (products, prices, offers) is cached on the phone with Hive and refreshed whenever online.
- Offline: bill is calculated with the Dart pricing copy, saved to an **outbox**, and can be shared/printed.
- When the internet comes back, the outbox sends each bill to `counter_checkout` with its `client_ref`. The server re-prices it, deducts stock, and stores both its own total and the offline total. A mismatch, e.g. a price that changed in between, gets a flag for the owner to review.

## 7. Notifications
- App open (Android + web): Supabase Realtime → sound + in-app banner + local notification for new orders and status changes.
- App fully closed: needs Firebase Cloud Messaging (free). It's planned for Phase 5 and needs a Firebase project, so I'll explain the steps then.

## 8. Security checklist
- In the app: only `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `RAZORPAY_KEY_ID`. All three are public by design, and RLS protects the data.
- Supabase Secrets only: `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` (service-role key is automatic inside Edge Functions).
- GitHub Secrets only: Supabase access token, signing keystore + passwords.
- `.gitignore`: `.env`, `*.jks`, `*.keystore`, `key.properties`.
- Coupon tries limited per user per hour, order placing limited per minute, all inputs checked in SQL (lengths, quantities > 0, max 100 lines).

## 9. Build & release
| Workflow | When | Does |
|---|---|---|
| `build` | every push | analyze → Dart tests → SQL/RLS tests → APK → web + download page to GitHub Pages |
| `release` | click "Run", enter 1.0.0 | split-per-ABI APKs (~20 MB) + universal APK + **AAB** → GitHub Release → refresh download page |
| `create-signing-key` | **once only** | makes the permanent key, saves it to GitHub Secrets, gives you an encrypted backup ZIP. Refuses to run again if a key exists |
| `setup-backend` | after Supabase project is made | applies migrations + seed, deploys Edge Functions, sets Supabase Secrets |
| `make-owner` | once | makes your login the shop owner |
| `keep-alive` | every 3 days (automatic) | small query so the free Supabase project doesn't pause |
