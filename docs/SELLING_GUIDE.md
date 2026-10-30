# Dukaandar ko app bechna: monthly service guide

Model: **aap app aur server chalate hain, dukaandar har mahine fees deta hai.**
Dukaandar ko tech ka kuch nahi sambhalna padta. Aap updates, backup aur support dete hain.

---

## 1. Aap dukaandar ko kya denge

| Cheez | Kaise |
|---|---|
| **Android app** (apne naam/logo ke saath) | Download page ka link + QR: `https://mlk09.github.io/chhabra-store1/` |
| **Web app** (iPhone / computer ke liye) | `https://mlk09.github.io/chhabra-store1/app/` |
| **Owner login** | Dukaandar apne email se sign up kare → aap **make-owner** chalayein |
| **Saare products ka setup** | Pehli baar aap ya dukaandar: AI photo / Bulk photos se |
| **QR poster** dukaan ke counter ke liye | Download page par QR hai, print karke lagayein |
| **Training** (30–45 minute) | Products, rate badalna, order accept karna, offers (neeche checklist) |
| **Support** | Aapka WhatsApp number. Update aur problem aap theek karenge |

## 2. Dukaandar aapko kya dega

**Pehle din:**
- Dukaan ka naam (English + Hindi), pata, pincode(s), phone, WhatsApp number
- Owner ka **email** (login ke liye)
- **UPI ID** (dukaandar khud app mein Shop details mein daalega, aap nahi)
- Logo (agar hai), ya pasand ka rang
- Delivery: kitne km tak, delivery charge, kitne ke upar free, minimum order, time slots
- Products ki list ya photos (ya aap dukaan jaakar Bulk photos se daal dein)
- GSTIN (agar GST bill chahiye, optional)

**Online payment (Phase 3) ke liye**, dukaandar ke **apne naam** par:
- Razorpay account aur KYC: PAN, bank account, dukaan ka proof. Paisa seedha dukaandar ke bank mein jaata hai, aap ke paas nahi.
- Iske liye aap koi password nahi lenge. Dukaandar keys khud Supabase Secrets mein daalega, ya screen share par aap batayenge.

**Monthly fees**: tay ki hui tareekh par.

## 3. Kya aapke paas rahega (aapke naam par)

| Account | Kyon |
|---|---|
| GitHub repo `mlk09/chhabra-store1` | App ka code, builds, updates |
| Supabase project | Database aur server. Aap chalate hain, isliye pause/resume kar sakte hain |
| Signing key (backup aapke paas) | Updates isi se jaate hain |
| Google Play developer account (jab banayein) | App Play Store par aapke developer naam se, dukaandar ki likhit permission ke saath |
| Gemini API key | Photo pehchaan (AI) |

**Kabhi share na karein:** Supabase access token, signing key/password, GitHub login.

## 4. Aapka mahine ka kharcha (andaza, 2026)

| Cheez | Kharcha |
|---|---|
| Supabase | Free plan ek dukaan ke liye kaafi hai (keep-alive chalta hai). Asli kaam ke liye **Pro ~$25/mahina (~₹2,100)** behtar hai: backup aur pause nahi hota |
| GitHub, Pages, Actions | Free (public repo) |
| Gemini AI | Free tier aam use ke liye kaafi |
| Google Play | $25 **ek baar** (aapka account) |
| Razorpay | Aapka kuch nahi. Dukaandar ke online payments par ~2% fees unke account se |
| Domain (optional) | ~₹800–1,000/saal agar `chhabrastore.in` jaisa naam chahiye |

**Fees kitni rakhein:** ye aapka faisla hai. Socha samjha tareeka:
- **Setup fees** (ek baar): products daalna, training, poster
- **Monthly fees** jo Supabase Pro + aapke support ka samay cover kare

Bazaar ka andaza lene ke liye local dukaandaar se baat kar lijiye. Aam taur par chhoti dukaano ke liye ₹500–1,500/mahina jaisi range suni jaati hai, lekin ise pakka mat maaniye.

## 5. Pehle din ka checklist (dukaan par)

1. README Step 2–5 ho chuke hon (Supabase, secrets, setup-backend).
2. Dukaandar ke phone par download page se app install karein (Chrome se).
3. Dukaandar sign up kare → aap **Actions → make-owner** → unka email.
4. **More → Shop details**: naam, pata, phone, UPI ID, delivery, time slots, logo, rang.
5. 20–30 products daalein (AI / Bulk photos). Rate dukaandar khud check kare.
6. Ek offer aur ek coupon banayein (jaise `WELCOME50`).
7. Aap ek test order dein. Dukaandar ke phone par **ghanti** baje, wo Accept → Delivered kare.
8. **Share shop link**: dukaandar apne WhatsApp groups mein bheje. QR poster counter par lagayein.
9. Dukaandar ko sikhayein:
   - Rate badalna
   - Stock bharna
   - Order aate hi Accept karna
   - Item na ho to **Not available** karna
   - Chhutti par **Holiday mode** lagana

## 6. Mahine ka kaam (aapka)

- **Fees aayi?** Nahi aayi to **Actions → shop-service → pause** (note: "Fees baaki hai, call karein").
  - App dikhti rahegi, bas naye online order band honge. Purana data surakshit rahega.
- Fees aate hi **shop-service → resume** (paid_until bhi likh dein).
- Har update ke baad **release** chalayein. Dukaandar ka app purane ke upar update hoga.
- Keep-alive aur backups chalte rahein (Pro plan par roz backup).

## 7. Agreement mein kya likhein (saadi bhasha mein)

- Service kya hai: app, server, updates, support (kitne ghante mein jawab).
- Fees, tareekh, aur na dene par **pause** ki baat.
- Data dukaandar ka hai. Service band karne par aap products aur orders ki list (Excel/CSV) dukaandar ko denge.
- Online payment ka paisa seedha dukaandar ke account mein jaata hai. Aap payment nahi pakadte.
- Privacy: customers ka data sirf orders ke liye use hota hai. Privacy policy mein dukaan ko seller aur aapko service provider likhein (Phase 6 mein page banega).
- Play Store par app aapke developer account se dukaandar ke naam/logo ke saath jayegi: dukaandar se **likhit permission** lein.

> Ye kanooni salaah nahi hai. Bade contract ke liye kisi CA/vakil se agreement check karwa lein.
