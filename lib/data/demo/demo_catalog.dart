import '../../core/units.dart';
import '../models/catalog.dart';
import '../models/order.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/shop.dart';

/// Sample shop used by Demo mode. Prices are realistic but made up.
Catalog buildDemoCatalog() {
  const shop = Shop(
    id: 'demo-shop',
    slug: 'demo',
    name: 'Demo Kirana Store',
    nameHi: 'डेमो किराना स्टोर',
    tagline: 'Fresh groceries, fair prices',
    address: 'Main Bazaar',
    city: 'Karnal',
    pincode: '132001',
    phone: '9999999999',
    upiId: 'demo@upi',
    upiName: 'Demo Kirana Store',
    deliveryPincodes: ['132001'],
    deliveryRadiusKm: 3,
    deliveryCharge: 2000,
    freeDeliveryAbove: 29900,
    minOrder: 10000,
  );

  final categories = <Category>[
    const Category(id: 'c-atta', name: 'Atta, Rice & Dal', nameHi: 'आटा, चावल और दाल', icon: '🌾', sortOrder: 1),
    const Category(id: 'c-oil', name: 'Oil & Ghee', nameHi: 'तेल और घी', icon: '🫙', sortOrder: 2),
    const Category(id: 'c-masala', name: 'Masala & Spices', nameHi: 'मसाले', icon: '🌶️', sortOrder: 3),
    const Category(id: 'c-sugar', name: 'Sugar, Salt & Jaggery', nameHi: 'चीनी, नमक और गुड़', icon: '🧂', sortOrder: 4),
    const Category(id: 'c-dairy', name: 'Dairy & Bread', nameHi: 'दूध और ब्रेड', icon: '🥛', sortOrder: 5),
    const Category(id: 'c-veg', name: 'Fruits & Vegetables', nameHi: 'फल और सब्ज़ियाँ', icon: '🥬', sortOrder: 6),
    const Category(id: 'c-snacks', name: 'Snacks & Biscuits', nameHi: 'नमकीन और बिस्कुट', icon: '🍪', sortOrder: 7),
    const Category(id: 'c-drinks', name: 'Tea, Coffee & Drinks', nameHi: 'चाय, कॉफ़ी और पेय', icon: '☕', sortOrder: 8),
    const Category(id: 'c-care', name: 'Personal Care', nameHi: 'पर्सनल केयर', icon: '🧴', sortOrder: 9),
    const Category(id: 'c-home', name: 'Cleaning & Household', nameHi: 'सफ़ाई और घरेलू', icon: '🧹', sortOrder: 10),
  ];

  var n = 0;
  final now = DateTime.now();
  Product p(
    String cat,
    String name,
    String hi,
    String emoji,
    List<(String label, SaleUnit unit, double qty, int mrp, int price, double stock)> sizes, {
    String? brand,
    bool loose = false,
    double gst = 5,
    List<String> synonyms = const [],
    int? expiresInDays,
    String? barcode,
  }) {
    final id = 'p${++n}';
    var vi = 0;
    return Product(
      id: id,
      name: name,
      nameHi: hi,
      categoryId: cat,
      brand: brand,
      emoji: emoji,
      isLoose: loose,
      gstRate: gst,
      synonyms: synonyms,
      lowStockLimit: loose ? 5 : 4,
      variants: [
        for (final s in sizes)
          Variant(
            id: '$id-v${++vi}',
            productId: id,
            label: s.$1,
            unit: s.$2,
            unitQty: s.$3,
            mrp: s.$4 * 100,
            price: s.$5 * 100,
            costPrice: (s.$5 * 0.86).round() * 100,
            stock: s.$6,
            sortOrder: vi,
            barcode: vi == 1 ? barcode : null,
            expiryDate: expiresInDays == null ? null : now.add(Duration(days: expiresInDays)),
          ),
      ],
    );
  }

  const kg = SaleUnit.kg, g = SaleUnit.g, l = SaleUnit.l, ml = SaleUnit.ml, pc = SaleUnit.pc, pack = SaleUnit.pack;

  final products = <Product>[
    p(
      'c-atta',
      'Aashirvaad Whole Wheat Atta',
      'आशीर्वाद आटा',
      '🌾',
      [('1 kg', kg, 1, 68, 62, 30), ('5 kg', kg, 5, 315, 279, 18), ('10 kg', kg, 10, 610, 545, 6)],
      brand: 'Aashirvaad',
      barcode: '8901725181123',
    ),
    p('c-atta', 'Basmati Rice', 'बासमती चावल', '🍚', [
      ('1 kg', kg, 1, 140, 118, 25),
      ('5 kg', kg, 5, 690, 560, 8),
    ], brand: 'India Gate'),
    p(
      'c-atta',
      'Sona Masoori Rice (Loose)',
      'सोना मसूरी चावल (खुला)',
      '🍚',
      [('per kg', kg, 1, 64, 58, 80)],
      loose: true,
      gst: 0,
    ),
    p('c-atta', 'Toor Dal', 'अरहर दाल', '🫘', [
      ('500 g', g, 500, 95, 84, 22),
      ('1 kg', kg, 1, 185, 162, 14),
    ], brand: 'Tata Sampann'),
    p('c-atta', 'Moong Dal (Loose)', 'मूंग दाल (खुली)', '🫘', [('per kg', kg, 1, 130, 118, 40)], loose: true, gst: 0),
    p('c-atta', 'Chana Dal', 'चना दाल', '🫘', [('1 kg', kg, 1, 110, 96, 3)]),
    p('c-atta', 'Rajma Chitra', 'राजमा चित्रा', '🫘', [('500 g', g, 500, 89, 79, 12)]),
    p('c-atta', 'Besan', 'बेसन', '🌾', [('500 g', g, 500, 62, 55, 16)], brand: 'Rajdhani'),
    p(
      'c-oil',
      'Fortune Kachi Ghani Mustard Oil',
      'फॉर्च्यून सरसों तेल',
      '🫙',
      [('1 L', l, 1, 195, 172, 24), ('5 L', l, 5, 940, 829, 5)],
      brand: 'Fortune',
      barcode: '8906007280017',
    ),
    p('c-oil', 'Refined Soyabean Oil', 'रिफाइंड सोयाबीन तेल', '🫙', [('1 L', l, 1, 160, 138, 20)], brand: 'Fortune'),
    p(
      'c-oil',
      'Amul Pure Ghee',
      'अमूल शुद्ध घी',
      '🧈',
      [('500 ml', ml, 500, 330, 315, 10), ('1 L', l, 1, 650, 620, 6)],
      brand: 'Amul',
      gst: 12,
      expiresInDays: 150,
    ),
    p('c-masala', 'Haldi Powder', 'हल्दी पाउडर', '🟡', [
      ('100 g', g, 100, 38, 34, 30),
      ('200 g', g, 200, 72, 64, 12),
    ], brand: 'MDH'),
    p('c-masala', 'Red Chilli Powder', 'लाल मिर्च पाउडर', '🌶️', [('100 g', g, 100, 52, 46, 26)], brand: 'MDH'),
    p('c-masala', 'Jeera (Loose)', 'जीरा (खुला)', '🌿', [('per kg', kg, 1, 520, 480, 4)], loose: true),
    p('c-masala', 'Garam Masala', 'गरम मसाला', '🧆', [('100 g', g, 100, 92, 84, 15)], brand: 'Everest'),
    p('c-sugar', 'Sugar (Loose)', 'चीनी (खुली)', '🍬', [('per kg', kg, 1, 46, 44, 120)], loose: true, gst: 5),
    p(
      'c-sugar',
      'Tata Salt',
      'टाटा नमक',
      '🧂',
      [('1 kg', kg, 1, 30, 28, 60)],
      brand: 'Tata',
      gst: 0,
      barcode: '8904043901015',
    ),
    p('c-sugar', 'Desi Gud', 'देसी गुड़', '🟫', [('per kg', kg, 1, 70, 64, 18)], loose: true),
    p(
      'c-dairy',
      'Amul Taaza Milk',
      'अमूल ताज़ा दूध',
      '🥛',
      [('500 ml', ml, 500, 29, 29, 40), ('1 L', l, 1, 56, 56, 20)],
      brand: 'Amul',
      gst: 0,
      expiresInDays: 2,
    ),
    p(
      'c-dairy',
      'Amul Butter',
      'अमूल मक्खन',
      '🧈',
      [('100 g', g, 100, 62, 60, 14), ('500 g', g, 500, 285, 275, 4)],
      brand: 'Amul',
      gst: 12,
      expiresInDays: 60,
    ),
    p('c-dairy', 'Fresh Paneer', 'ताज़ा पनीर', '🧀', [('200 g', g, 200, 95, 90, 8)], gst: 5, expiresInDays: 3),
    p(
      'c-dairy',
      'Brown Bread',
      'ब्राउन ब्रेड',
      '🍞',
      [('400 g', g, 400, 55, 50, 6)],
      brand: 'Harvest Gold',
      expiresInDays: 4,
    ),
    p('c-dairy', 'Eggs', 'अंडे', '🥚', [('6 pc', pc, 6, 48, 45, 20), ('30 pc', pc, 30, 225, 210, 6)], gst: 0),
    p('c-veg', 'Potato', 'आलू', '🥔', [('per kg', kg, 1, 30, 25, 150)], loose: true, gst: 0),
    p('c-veg', 'Onion', 'प्याज', '🧅', [('per kg', kg, 1, 45, 40, 90)], loose: true, gst: 0),
    p('c-veg', 'Tomato', 'टमाटर', '🍅', [('per kg', kg, 1, 40, 36, 3)], loose: true, gst: 0),
    p('c-veg', 'Banana', 'केला', '🍌', [('1 dozen', SaleUnit.dozen, 1, 60, 55, 15)], gst: 0),
    p('c-veg', 'Lemon', 'नींबू', '🍋', [('250 g', g, 250, 30, 25, 10)], gst: 0),
    p(
      'c-snacks',
      'Parle-G Biscuits',
      'पारले-जी बिस्कुट',
      '🍪',
      [('250 g', g, 250, 25, 25, 48), ('800 g', g, 800, 80, 75, 10)],
      brand: 'Parle',
      gst: 18,
      barcode: '8901719110016',
    ),
    p(
      'c-snacks',
      'Haldiram Aloo Bhujia',
      'हल्दीराम आलू भुजिया',
      '🥨',
      [('200 g', g, 200, 55, 52, 20), ('1 kg', kg, 1, 240, 225, 5)],
      brand: 'Haldiram',
      gst: 12,
    ),
    p(
      'c-snacks',
      'Maggi Noodles',
      'मैगी नूडल्स',
      '🍜',
      [('4-pack', pack, 1, 60, 56, 30), ('12-pack', pack, 1, 168, 156, 8)],
      brand: 'Nestle',
      gst: 12,
      synonyms: ['noodles'],
    ),
    p(
      'c-drinks',
      'Tata Tea Gold',
      'टाटा टी गोल्ड',
      '🍵',
      [('250 g', g, 250, 150, 138, 18), ('500 g', g, 500, 295, 268, 9)],
      brand: 'Tata',
      gst: 5,
    ),
    p(
      'c-drinks',
      'Nescafe Classic',
      'नेस्कैफ़े क्लासिक',
      '☕',
      [('50 g', g, 50, 185, 175, 6)],
      brand: 'Nestle',
      gst: 18,
    ),
    p(
      'c-drinks',
      'Frooti Mango Drink',
      'फ्रूटी',
      '🥭',
      [('600 ml', ml, 600, 40, 38, 24)],
      brand: 'Parle Agro',
      gst: 12,
      expiresInDays: 20,
    ),
    p(
      'c-care',
      'Lux Soap (Pack of 4)',
      'लक्स साबुन (4 का पैक)',
      '🧼',
      [('4 x 100 g', pack, 1, 180, 155, 12)],
      brand: 'Lux',
      gst: 18,
    ),
    p(
      'c-care',
      'Colgate Toothpaste',
      'कोलगेट टूथपेस्ट',
      '🪥',
      [('200 g', g, 200, 125, 110, 15)],
      brand: 'Colgate',
      gst: 18,
    ),
    p(
      'c-care',
      'Clinic Plus Shampoo',
      'क्लिनिक प्लस शैम्पू',
      '🧴',
      [('340 ml', ml, 340, 270, 239, 2)],
      brand: 'Clinic Plus',
      gst: 18,
    ),
    p(
      'c-home',
      'Surf Excel Easy Wash',
      'सर्फ एक्सेल',
      '🧺',
      [('1 kg', kg, 1, 140, 128, 14), ('3 kg', kg, 3, 420, 365, 3)],
      brand: 'Surf Excel',
      gst: 18,
    ),
    p('c-home', 'Vim Bar', 'विम बार', '🧽', [('300 g', g, 300, 35, 32, 25)], brand: 'Vim', gst: 18),
    p('c-home', 'Phool Broom', 'फूल झाड़ू', '🧹', [('1 pc', pc, 1, 120, 99, 7)], gst: 0),
    p('c-home', 'Agarbatti', 'अगरबत्ती', '🪔', [('1 pack', pack, 1, 50, 45, 20)], brand: 'Cycle', gst: 5),
  ];

  String pid(String startsWith) => products.firstWhere((p) => p.name.startsWith(startsWith)).id;
  final created = DateTime(2026, 1, 1);
  final offers = <Offer>[
    Offer(
      id: 'o-oil',
      title: 'Oil & Ghee 5% off',
      titleHi: 'तेल और घी पर 5% छूट',
      kind: OfferKind.categoryPercent,
      categoryId: 'c-oil',
      percent: 5,
      createdAt: created,
    ),
    Offer(
      id: 'o-parle',
      title: 'Parle-G: Buy 2 Get 1 free',
      titleHi: 'पारले-जी: 2 लो 1 फ़्री',
      kind: OfferKind.bxgy,
      productId: pid('Parle-G'),
      buyQty: 2,
      getQty: 1,
      createdAt: created.add(const Duration(minutes: 1)),
    ),
    Offer(
      id: 'o-cart50',
      title: '₹50 off above ₹500',
      titleHi: '₹500 से ऊपर ₹50 छूट',
      kind: OfferKind.cartFlat,
      amount: 5000,
      minOrder: 50000,
      createdAt: created.add(const Duration(minutes: 2)),
    ),
  ];

  return Catalog(shop: shop, categories: categories, products: products, offers: offers);
}

/// Sample coupon codes for Demo mode.
List<Coupon> buildDemoCoupons() => const [
  Coupon(
    id: 'cp-welcome',
    code: 'WELCOME50',
    title: '₹50 off your first order above ₹300',
    kind: CouponKind.flat,
    value: 5000,
    minOrder: 30000,
    isPublic: true,
  ),
  Coupon(
    id: 'cp-ten',
    code: 'CHHABRA10',
    title: '10% off, up to ₹40',
    kind: CouponKind.percent,
    value: 10,
    maxDiscount: 4000,
    minOrder: 20000,
    perUserLimit: 5,
    isPublic: true,
  ),
];
