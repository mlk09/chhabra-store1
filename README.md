# Chhabra General Store · छाबड़ा जनरल स्टोर

Kirana app for **Chhabra General Store, Railway Road, Karnal**. One app, two sides:

- **Customers:** browse the shop, search in Hinglish/Hindi/English ("aloo", "cheeni", "आटा"), see MRP vs price.
- **Shopkeeper (owner + staff):** price list, sizes, loose items, stock, expiry, photos, categories, bulk price change, shop details.

Runs on **Android** (APK + Play Store AAB) and as a **web app** (iPhone users, shopkeeper on a computer).
Built with Flutter + Supabase. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for tables, security rules and payment flow.

| Phase | What | Status |
|---|---|---|
| 1 | Login, roles, products & prices, categories, photos, demo mode | ✅ done |
| 1+ | AI photo recognition (Gemini), bulk photos | ✅ done |
| 2 | Customer cart, server-side discounts/coupons, orders + live alerts | ✅ done |
| 3 | Payments: UPI intent, Razorpay (webhook), Cash on Delivery | next |
| 4 | Counter billing (offline), barcode, WhatsApp bill, udhaar/khata | |
| 5 | Reports, staff roles UI, notifications, CSV import/export | |
| 6 | Polish, privacy/terms pages, Play Store prep | |

---

## Try it without any setup (Demo mode)

Open the app → **Demo: Customer** or **Demo: Shopkeeper**. A sample shop with 41 products works fully offline. Changes are not saved. Every build has Demo mode, even before Supabase is connected.

---

## One-time setup (≈ 30 minutes, all clicks)

> 🔐 **Rule:** keys and passwords go **only** into GitHub Secrets or Supabase Secrets, never into chat, code or WhatsApp.

### Step 1: GitHub Pages
Repo → **Settings** → **Pages** → *Build and deployment* → Source: **GitHub Actions**.

### Step 2: Create the Supabase project
1. Open <https://supabase.com/dashboard> → **New project**.
   - Name: `chhabra-store` · Region: **South Asia (Mumbai)** · Create a strong database password and save it in your password manager.
   - Free plan allows **2 active projects**. Family Food is one, this is the second. If you ever make a third, pause one first.
2. Wait ~2 minutes until the project is ready.

### Step 3: Add GitHub Secrets
Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Add each one:

| Secret name | Where to copy it from |
|---|---|
| `SUPABASE_URL` | Supabase → Project Settings → **Data API** (or API) → *Project URL* (`https://xxxx.supabase.co`) |
| `SUPABASE_ANON_KEY` | Supabase → Project Settings → **API Keys** → *Publishable key* (or legacy *anon public*) |
| `SUPABASE_ACCESS_TOKEN` | <https://supabase.com/dashboard/account/tokens> → **Generate new token** → name `github-chhabra` |

### Step 4: Run "setup-backend"
Repo → **Actions** → **setup-backend** → **Run workflow**. It:
- creates all tables + security rules (and only new ones on later runs),
- adds your shop row and 10 starter categories,
- turns **email confirmation OFF** (sign-up logs in directly) and sets the reset-password link to your web app,
- rebuilds the app connected to your shop.

If its log shows a yellow "Set login settings by hand" warning, do it manually:
Supabase → **Authentication** → **Sign In / Providers** → **Email** → turn **Confirm email** OFF → Save.

### Step 5: Become the owner
1. Open the web app (`https://<your-github-name>.github.io/<repo>/app/`) → **Log in / Sign up** → **Create account** with your email.
2. GitHub → **Actions** → **make-owner** → Run workflow → enter that email.
3. In the app: **Account → Log out**, then log in again. You'll now see the **Shop dashboard**.

### Step 6: Permanent signing key (do this BEFORE the first release)
This key proves every update comes from you. Same key forever = updates install over the old app with no uninstall.

1. Invent a long password (12+ characters, letters and numbers, **no spaces or quotes**). Write it in your password manager **and** on paper.
2. Add secret `ANDROID_KEY_PASSWORD` = that password.
3. Create a temporary token: GitHub → your photo → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**
   - Expiration: 7 days · Repository access: **Only select repositories** → this repo
   - Permissions → Repository permissions → **Secrets: Read and write** → Generate → copy it.
4. Add secret `GH_ADMIN_TOKEN` = that token.
5. **Actions** → **create-signing-key** → Run workflow → type `CREATE MY KEY`.
6. When it finishes (green ✓), open the run, scroll to **Artifacts** → download **signing-key-backup-DOWNLOAD-AND-DELETE**. Then click the 🗑 next to it.
7. Delete secret `GH_ADMIN_TOKEN`, and delete the token on GitHub (Fine-grained tokens → Delete).

**Back up the key (very important):**
- The downloaded ZIP is encrypted with your `ANDROID_KEY_PASSWORD`. It opens with 7-Zip (Windows) or ZArchiver (Android).
- Keep **two copies**: Google Drive (private folder) **and** a pen drive at home. Do not email it or upload it to GitHub.
- If it is lost: phones that installed the APK must uninstall once to get updates. On Google Play, use **Play App Signing** (default) and Google can reset a lost *upload* key.

### Step 7: Publish a release
**Actions** → **release** → Run workflow → version `1.0.0` (next time `1.0.1`, `1.1.0`…).
It builds:
- `chhabra-store.apk` (most phones, ~20 MB) · `chhabra-store-old-phones.apk` · `chhabra-store-universal.apk`
- `chhabra-store-play-store.aab` (upload this to Google Play)

It checks that every file is signed with your permanent key, publishes a GitHub Release, and refreshes the download page.

**Download page:** `https://<your-github-name>.github.io/<repo>/`. It has an Android button, a web-app button and a QR code. Share this link, not the APK file.

### Step 8 (optional, recommended): Photo recognition with AI
Lets you add products by just taking a photo: AI reads the name, Hindi name, size, MRP and picks the category.
1. Open <https://aistudio.google.com/apikey> (login with Google) → **Create API key** → copy it. It is **free** for normal shop use. Your Family Food key works too.
2. Add secret `GEMINI_API_KEY` = that key.
3. **Actions** → **setup-backend** → Run workflow. The key goes into **Supabase Secrets**, never into the app.

Limit: 300 photos per person per day (protects your free quota).

---

## Online orders (Phase 2): how it works

**Customer:** ADD → cart (− / +, loose items by weight) → coupon → **Checkout** → address or pickup → time slot → **Place order** → live tracking in **Orders**. Cancel is possible until the shop accepts. **Order again** refills the cart.

**Shop:** the **Orders** tab rings (bell + phone notification) when an order arrives while the app is open or in the background. Open it → **Accept order** → **Mark packed** → **Out for delivery** / **Ready for pickup** → **Mark delivered** (cash orders become "Paid"). Item out of stock? ⋮ → **Not available**: the bill goes down by that item and stock is put back.

**Offers & coupons:** More → **Offers & coupons**.
- Each item gets its single best offer (product %, ₹ off per piece/kg, category %, Buy X Get Y).
- One bill offer applies on top (₹ off / % off above ₹X).
- A coupon comes last. Coupons are once per customer by default, and can be secret or shown in the app.

**Prices are decided by the server.** The app only shows them. If a price changes while a customer is checking out, the order is stopped and they see the new total.

**Settings:** More → Shop details → *Online orders*: delivery / pickup / cash on delivery on-off, time slots, how soon today's first slot can be.

**Not yet:** online UPI/Razorpay payment (Phase 3). Alerts when the app is fully closed need Firebase push (Phase 5).

## Adding products & photos

**How saving works**
- **Demo mode:** nothing is saved (the orange strip says so). Good for practice.
- **Your real shop** (after Steps 2–5): every **Save** goes straight to your Supabase database, so the shop on every phone and the web app updates. Photos are compressed on the phone (~100 KB) before upload.

**One product:** Products → **+ Add** → **Fill from photo (AI)** → take a photo of the front of the pack → check name, size, price → **Save product**.

**Many photos at once:** Products → 🖼 icon (or Dashboard → **Bulk photos**) → **Choose photos** (up to 30). For each photo the app:
1. matches by **file name**, e.g. `Tata Salt.jpg` → Tata Salt (best when photos are on a computer),
2. else asks the **AI**, which finds the existing product or fills in a new one,
3. else lets you pick the product or type it.

Check the cards (red = something missing) → **Save**.

**Photo tips:** front of the pack, close-up, good light, plain background (a white sheet). Square photos look best.

**Why the app doesn't ship ready-made product photos:** brand pack photos on the internet belong to the brands/websites, so copying them into your app is a copyright risk. Your own photos (or ones a supplier/brand gave you permission for) are safe, and with Bulk photos 30 products take ~5 minutes.

---

## All secrets: what, where, who reads them

| Name | Stored in | Used by | Secret? |
|---|---|---|---|
| `SUPABASE_URL` | GitHub Secrets | app build | public value, kept out of git anyway |
| `SUPABASE_ANON_KEY` | GitHub Secrets | app build | public by design; data is protected by RLS |
| `SUPABASE_ACCESS_TOKEN` | GitHub Secrets | setup-backend, make-owner | 🔒 yes, full control of your Supabase account |
| `ANDROID_KEY_PASSWORD` | GitHub Secrets (+ your password manager) | build, release | 🔒 yes |
| `ANDROID_KEYSTORE_BASE64` | GitHub Secrets (created by workflow) | build, release | 🔒 yes |
| `ANDROID_KEY_ALIAS` | GitHub Secrets (created by workflow) | build, release | no (`upload`) |
| `GH_ADMIN_TOKEN` | GitHub Secrets, **temporary** | create-signing-key only | 🔒 delete after use |
| `GEMINI_API_KEY` | GitHub Secrets → copied to **Supabase** Secrets by setup-backend | Edge Function `product-ai` | 🔒 never in the app |
| `RAZORPAY_KEY_ID` | GitHub Secrets (Phase 3) | app build | public key id |
| `RAZORPAY_KEY_SECRET` | **Supabase** Secrets (Phase 3) | Edge Functions | 🔒 never in the app |
| `RAZORPAY_WEBHOOK_SECRET` | **Supabase** Secrets (Phase 3) | Edge Functions | 🔒 never in the app |

The Supabase **service-role key** is never stored anywhere by us. Edge Functions get it automatically on Supabase's servers.

---

## Keep-alive
Free Supabase projects pause after about a week without use. The **keep-alive** workflow reads one row every 3 days. GitHub turns scheduled workflows off after 60 days without any commit. If that happens, Actions → keep-alive → **Enable workflow**.

---

## For developers

```bash
flutter pub get
flutter run                                   # Demo-only (no .env)
cp .env.example .env                          # then fill in values
flutter run --dart-define-from-file=.env      # connected to Supabase
flutter test                                  # Dart unit + widget tests
PGHOST=/tmp PGPORT=5433 tools/test_db.sh      # SQL + RLS tests on a local Postgres
```

- Database changes: add a new file `supabase/migrations/000N_name.sql` (never edit an applied one), add tests in `supabase/tests/`, then run **setup-backend**.
- Every new table needs: RLS enabled, policies, and an explicit `revoke … from anon, authenticated` + the minimum `grant`.
- App id `com.chhabrastore.app` must never change after the first release.

## Troubleshooting

| Problem | Fix |
|---|---|
| App opens in Demo only | `SUPABASE_URL` / `SUPABASE_ANON_KEY` secrets missing → add them, run **build** again |
| "Shop not found" | Run **setup-backend** |
| Logged in but no dashboard | Run **make-owner** with your email, then log out and in |
| "Could not open the shop" screen | Internet, or Supabase project paused → Supabase dashboard → **Restore** |
| APK download stops in WhatsApp | Open the link in **Chrome** (⋮ → Open in Chrome) |
| "App not installed" on update | The APK was signed with a different key → always install from **release**, never from **build** test APKs |
| Release fails "No signing key" | Do Step 6 first |
