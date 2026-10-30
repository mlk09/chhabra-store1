import 'dart:async';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../../domain/order_flow.dart';
import '../../domain/pricing.dart';
import '../../domain/slots.dart';
import '../backend.dart';
import '../models/catalog.dart';
import '../models/category.dart';
import '../models/member.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/product_guess.dart';
import '../models/shop.dart';
import 'demo_catalog.dart';

/// The sample shop's data. Shared by the customer and shopkeeper demo views,
/// so an order placed as "customer" shows up for the "shopkeeper".
/// Lives in memory until the app restarts.
class DemoStore {
  DemoStore._() {
    _seedOrders();
  }
  static DemoStore instance = DemoStore._();

  /// Fresh sample shop (tests).
  static void reset() => instance = DemoStore._();

  Catalog catalog = buildDemoCatalog();
  List<Coupon> coupons = buildDemoCoupons();
  final orders = <Order>[];
  final addresses = <Address>[
    const Address(
      id: 'demo-address',
      label: 'Home',
      name: 'Demo Customer',
      phone: '9876543210',
      line1: '24, Model Town',
      landmark: 'Near Main Bazaar',
      pincode: '132001',
      isDefault: true,
    ),
  ];
  final redemptions = <String, int>{}; // couponId → uses by the demo customer
  final photos = <String, Uint8List>{};
  final changes = StreamController<void>.broadcast();
  var _orderNo = 0;

  void notify() => changes.add(null);

  int nextOrderNo() => ++_orderNo;

  void _seedOrders() {
    final now = DateTime.now();
    Order sample(int minutesAgo, OrderStatus status, List<(String, double)> items) {
      final q = priceCart(
        catalog: catalog,
        offers: catalog.offers,
        items: [for (final i in items) CartItem(_variantByName(i.$1), i.$2)],
        fulfilment: Fulfilment.delivery,
        now: now,
      );
      final at = now.subtract(Duration(minutes: minutesAgo));
      return orderFromQuote(
        q,
        id: const Uuid().v4(),
        orderNo: nextOrderNo(),
        status: status,
        fulfilment: Fulfilment.delivery,
        address: addresses.first,
        slotDate: at,
        slot: '18:00-21:00',
        paymentMethod: 'cod',
        createdAt: at,
        customerName: 'Demo Customer',
        customerPhone: '9876543210',
        events: [
          OrderEvent(status: 'new', at: at),
          if (status != OrderStatus.newOrder) OrderEvent(status: 'accepted', at: at.add(const Duration(minutes: 3))),
          if (status == OrderStatus.delivered) ...[
            OrderEvent(status: 'packed', at: at.add(const Duration(minutes: 20))),
            OrderEvent(status: 'out_for_delivery', at: at.add(const Duration(minutes: 30))),
            OrderEvent(status: 'delivered', at: at.add(const Duration(minutes: 55))),
          ],
        ],
        paymentStatus: status == OrderStatus.delivered ? 'paid' : 'pending',
      );
    }

    orders
      ..add(sample(60 * 26, OrderStatus.delivered, [('Aashirvaad', 1), ('Tata Salt', 1), ('Amul Taaza', 2)]))
      ..add(sample(25, OrderStatus.accepted, [('Fortune Kachi', 1), ('Potato', 2), ('Parle-G', 3)]));
  }

  String _variantByName(String startsWith) =>
      catalog.products.firstWhere((p) => p.name.startsWith(startsWith)).variants.first.id;
}

/// Builds an [Order] snapshot from a priced cart (demo only; the server does this in SQL).
Order orderFromQuote(
  Quote q, {
  required String id,
  required int orderNo,
  required OrderStatus status,
  required Fulfilment fulfilment,
  Address? address,
  DateTime? slotDate,
  String? slot,
  required String paymentMethod,
  required DateTime createdAt,
  String? customerName,
  String? customerPhone,
  String? note,
  List<OrderEvent> events = const [],
  String paymentStatus = 'pending',
}) => Order(
  id: id,
  orderNo: orderNo,
  customerId: 'demo-user',
  customerName: customerName,
  customerPhone: customerPhone,
  status: status,
  fulfilment: fulfilment,
  address: address,
  slotDate: slotDate,
  slot: slot,
  subtotalMrp: q.subtotalMrp,
  itemsTotal: q.itemsTotal,
  itemDiscount: q.itemDiscount,
  cartDiscount: q.cartDiscount,
  cartOffer: q.cartOffer,
  couponCode: q.couponId == null ? null : q.couponCode,
  couponDiscount: q.couponDiscount,
  deliveryCharge: q.deliveryCharge,
  total: q.total,
  savings: q.savings,
  paymentMethod: paymentMethod,
  paymentStatus: paymentStatus,
  note: note,
  createdAt: createdAt,
  items: [
    for (final l in q.lines)
      OrderItem(
        id: const Uuid().v4(),
        variantId: l.variantId,
        productId: l.productId,
        name: l.name,
        nameHi: l.nameHi,
        label: l.label,
        unit: l.unit,
        isLoose: l.isLoose,
        qty: l.qty,
        mrp: l.mrp,
        price: l.price,
        lineMrp: l.lineMrp,
        discount: l.discount,
        lineTotal: l.lineTotal,
        freeQty: l.freeQty,
        offer: l.offer,
      ),
  ],
  events: events,
);

/// Works fully offline with the sample shop, so anyone can try every screen
/// without an account. Follows the same rules as the real server.
class DemoBackend implements Backend {
  DemoBackend({required this.asShopkeeper});

  final bool asShopkeeper;
  DemoStore get _s => DemoStore.instance;
  Catalog get _catalog => _s.catalog;
  set _catalog(Catalog c) {
    _s.catalog = c;
    _s.notify();
  }

  final _auth = StreamController<AppUser?>.broadcast();

  static const _demoUser = AppUser(id: 'demo-user', email: 'demo@example.com', name: 'Demo Customer');

  @override
  bool get isDemo => true;

  @override
  AppUser? get currentUser => _demoUser;

  @override
  Stream<AppUser?> authChanges() => _auth.stream;

  @override
  Future<Membership> membership() async => asShopkeeper ? Membership.owner : Membership.customer;

  @override
  Future<void> signIn({required String email, required String password}) async {}

  @override
  Future<void> signUp({required String name, required String email, required String password, String? phone}) async {}

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Future<void> signOut() async => _auth.add(null);

  @override
  Future<void> deleteAccount() async => _auth.add(null);

  @override
  Future<List<ShopSummary>> listShops() async => [
    ShopSummary(slug: 'demo', name: _catalog.shop.name, nameHi: _catalog.shop.nameHi, city: _catalog.shop.city),
  ];

  @override
  Future<List<String>> myShopSlugs() async => asShopkeeper ? const ['demo'] : const [];

  @override
  Future<String> uploadShopLogo(ProductPhoto photo) async {
    final path = 'demo/logo/${DateTime.now().microsecondsSinceEpoch}.jpg';
    _s.photos[path] = photo.thumb;
    return path;
  }

  @override
  Future<Catalog> loadCatalog({required bool staffView, bool withCosts = false}) async => _catalog;

  @override
  Future<Product> saveProduct(
    Product product, {
    ProductPhoto? photo,
    bool withCosts = false,
    Set<String>? stockChanged,
  }) async {
    for (final v in product.variants) {
      if (v.price > v.mrp) {
        throw const AppException('Selling price cannot be more than MRP', 'बिक्री मूल्य MRP से ज़्यादा नहीं हो सकता');
      }
    }
    var withPhoto = product;
    if (photo != null) {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final full = 'demo/${product.id}/$stamp.jpg', thumb = 'demo/${product.id}/${stamp}_t.jpg';
      _s.photos[full] = photo.full;
      _s.photos[thumb] = photo.thumb;
      withPhoto = product.copyWith(imagePath: full, thumbPath: thumb);
    }
    final saved = Product.fromJson({...withPhoto.toJson(), 'updated_at': DateTime.now().toIso8601String()});
    _catalog = _catalog.withProduct(saved);
    return saved;
  }

  @override
  Future<void> deleteProduct(String productId) async => _catalog = _catalog.withoutProduct(productId);

  @override
  Future<Category> saveCategory(Category category) async {
    _catalog = _catalog.withCategory(category);
    return category;
  }

  @override
  Future<void> deleteCategory(String categoryId) async => _catalog = _catalog.withoutCategory(categoryId);

  @override
  Future<int> bulkUpdatePrices({
    required double percent,
    String? categoryId,
    String applyTo = 'both',
    String rounding = 'rupee',
  }) async {
    var changed = 0;
    final products = _catalog.products.map((p) {
      if (categoryId != null && p.categoryId != categoryId) return p;
      final variants = p.variants.map((v) {
        changed++;
        final mrp = applyTo == 'price' ? v.mrp : applyPercent(v.mrp, percent, rounding);
        final price = applyTo == 'mrp' ? v.price : applyPercent(v.price, percent, rounding);
        return v.copyWith(mrp: mrp, price: price > mrp ? mrp : price);
      }).toList();
      return p.copyWith(variants: variants);
    }).toList();
    _catalog = _catalog.copyWith(products: products);
    return changed;
  }

  @override
  Future<Shop> updateShop(Shop shop) async {
    _catalog = _catalog.copyWith(shop: shop);
    return shop;
  }

  // ── Offers & coupons ──

  @override
  Future<Offer> saveOffer(Offer offer) async {
    _catalog = _catalog.withOffer(offer);
    return offer;
  }

  @override
  Future<void> deleteOffer(String offerId) async => _catalog = _catalog.withoutOffer(offerId);

  @override
  Future<List<Coupon>> loadCoupons() async =>
      asShopkeeper ? List.of(_s.coupons) : _s.coupons.where((c) => c.isPublic && c.isActive).toList();

  @override
  Future<Coupon> saveCoupon(Coupon coupon) async {
    final c = Coupon.fromJson({...coupon.toJson(), 'code': coupon.code.trim().toUpperCase()});
    if (_s.coupons.any((x) => x.code == c.code && x.id != c.id)) {
      throw const AppException('This coupon code already exists.', 'यह कूपन कोड पहले से है।');
    }
    _s.coupons = [..._s.coupons.where((x) => x.id != c.id), c];
    return c;
  }

  @override
  Future<void> deleteCoupon(String couponId) async => _s.coupons = _s.coupons.where((c) => c.id != couponId).toList();

  // ── Cart & checkout ──

  Quote _price(List<CartItem> items, String? coupon, Fulfilment fulfilment) {
    try {
      return priceCart(
        catalog: _catalog,
        offers: _catalog.offers,
        coupons: _s.coupons,
        items: items,
        couponCode: coupon,
        fulfilment: fulfilment,
        userId: _demoUser.id,
        timesUsedByUser: (id) => _s.redemptions[id] ?? 0,
        now: DateTime.now(),
      );
    } on PricingError catch (e) {
      throw AppException(e.message, null, e.code);
    }
  }

  @override
  Future<Quote> quoteCart({required List<CartItem> items, String? coupon, required Fulfilment fulfilment}) async =>
      _price(items, coupon, fulfilment);

  @override
  Future<String> placeOrder(OrderRequest r) async {
    final shop = _catalog.shop;
    final now = DateTime.now();
    if (!shop.takingOrders) throw const AppException('The shop is not taking orders right now', null, 'shop_closed');
    if (!slotOk(shop, r.slotDate, r.slot, now)) {
      throw const AppException('Please choose another time slot', null, 'bad_slot');
    }
    Address? address;
    if (r.fulfilment == Fulfilment.delivery) {
      address = _s.addresses.where((a) => a.id == r.addressId).firstOrNull;
      if (address == null) throw const AppException('Please choose a delivery address', null, 'address_required');
      if (shop.deliveryPincodes.isNotEmpty && !shop.deliveryPincodes.contains(address.pincode)) {
        throw AppException('We do not deliver to this pincode yet', null, 'outside_area', {'pincode': address.pincode});
      }
    }
    final q = _price(r.items, r.coupon, r.fulfilment);
    if (q.unavailable.isNotEmpty) {
      throw const AppException('Some items are no longer available', null, 'items_changed');
    }
    if (q.couponError != null) throw AppException('This coupon cannot be used', null, 'coupon_${q.couponError}');
    if (q.belowMinOrder) {
      throw AppException('Minimum order not reached', null, 'below_min_order', {'min_order': shop.minOrder});
    }
    if (q.total != r.expectedTotal) {
      throw AppException('Prices changed. Please check the new total.', null, 'price_changed', {'total': q.total});
    }

    // Stock goes down, coupon use is counted, order is created.
    final sold = {for (final l in q.lines) l.variantId: l.qty};
    _catalog = _catalog.copyWith(
      products: [
        for (final p in _catalog.products)
          p.copyWith(
            variants: [
              for (final v in p.variants)
                sold.containsKey(v.id) && v.trackStock ? v.copyWith(stock: v.stock - sold[v.id]!) : v,
            ],
          ),
      ],
    );
    if (q.couponId != null) {
      _s.redemptions[q.couponId!] = (_s.redemptions[q.couponId!] ?? 0) + 1;
      _s.coupons = [
        for (final c in _s.coupons)
          c.id == q.couponId ? Coupon.fromJson({...c.toJson(), 'used_count': c.usedCount + 1}) : c,
      ];
    }
    final order = orderFromQuote(
      q,
      id: const Uuid().v4(),
      orderNo: _s.nextOrderNo(),
      status: OrderStatus.newOrder,
      fulfilment: r.fulfilment,
      address: address,
      slotDate: r.slotDate,
      slot: r.slot,
      paymentMethod: r.paymentMethod,
      createdAt: now,
      customerName: address?.name ?? _demoUser.name,
      customerPhone: address?.phone,
      note: r.note,
      events: [OrderEvent(status: 'new', at: now)],
    );
    _s.orders.add(order);
    _s.notify();
    return order.id;
  }

  @override
  Future<List<Address>> addresses() async => List.of(_s.addresses);

  @override
  Future<Address> saveAddress(Address address) async {
    _s.addresses
      ..removeWhere((a) => a.id == address.id)
      ..add(address);
    return address;
  }

  @override
  Future<void> deleteAddress(String addressId) async => _s.addresses.removeWhere((a) => a.id == addressId);

  // ── Orders ──

  List<Order> _sorted() => [..._s.orders]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Stream<T> _live<T>(T Function() read) async* {
    yield read();
    await for (final _ in _s.changes.stream) {
      yield read();
    }
  }

  @override
  Stream<List<Order>> watchMyOrders() => _live(_sorted);

  @override
  Stream<List<Order>> watchShopOrders() => _live(_sorted);

  @override
  Stream<Order> watchOrder(String orderId) => _live(() => _s.orders.firstWhere((o) => o.id == orderId));

  Order _replace(String id, Order Function(Order o) change) {
    final i = _s.orders.indexWhere((o) => o.id == id);
    if (i < 0) throw const AppException('Order not found', null, 'not_found');
    final next = change(_s.orders[i]);
    _s.orders[i] = next;
    return next;
  }

  void _restock(Iterable<OrderItem> items) {
    final back = {
      for (final i in items)
        if (i.variantId != null) i.variantId!: i.qty,
    };
    _catalog = _catalog.copyWith(
      products: [
        for (final p in _catalog.products)
          p.copyWith(
            variants: [
              for (final v in p.variants)
                back.containsKey(v.id) && v.trackStock ? v.copyWith(stock: v.stock + back[v.id]!) : v,
            ],
          ),
      ],
    );
  }

  @override
  Future<List<String>> recentlyBoughtProductIds() async => {
    for (final o in _sorted())
      if (o.status != OrderStatus.cancelled)
        for (final i in o.okItems)
          if (i.productId != null) i.productId!,
  }.toList();

  @override
  Future<void> setOrderStatus(String orderId, OrderStatus status, {String? note}) async {
    final o = _s.orders.firstWhere((o) => o.id == orderId, orElse: () => throw const AppException('Order not found'));
    final allowed = nextStatuses(o).contains(status) && (asShopkeeper || status == OrderStatus.cancelled);
    if (!allowed || (!asShopkeeper && o.status != OrderStatus.newOrder)) {
      throw const AppException('This step is not possible now', 'यह कदम अभी संभव नहीं है', 'bad_status');
    }
    if (status == OrderStatus.cancelled) _restock(o.okItems);
    _replace(
      orderId,
      (o) => Order.fromJson({
        ...o.toJson(),
        'status': status.code,
        if (status == OrderStatus.cancelled) 'cancel_reason': note,
        if (status == OrderStatus.cancelled) 'cancelled_by': asShopkeeper ? 'shop' : 'customer',
        if (status == OrderStatus.delivered && o.paymentMethod == 'cod') 'payment_status': 'paid',
        'events': [
          ...o.events.map((e) => e.toJson()),
          OrderEvent(status: status.code, note: note, at: DateTime.now()).toJson(),
        ],
      }),
    );
    _s.notify();
  }

  @override
  Future<void> markItemUnavailable(String orderItemId) async {
    final o = _s.orders.firstWhere((o) => o.items.any((i) => i.id == orderItemId));
    final item = o.items.firstWhere((i) => i.id == orderItemId);
    if (o.okItems.length <= 1) {
      throw const AppException(
        'This is the last item — cancel the order instead',
        'यह आख़िरी सामान है — ऑर्डर कैंसिल करें',
        'last_item',
      );
    }
    _restock([item]);
    _replace(
      o.id,
      (o) => Order.fromJson({
        ...o.toJson(),
        'items': [
          for (final i in o.items) i.id == orderItemId ? {...i.toJson(), 'status': 'unavailable'} : i.toJson(),
        ],
        'items_total': paiseToJson(o.itemsTotal - item.lineTotal),
        'subtotal_mrp': paiseToJson(o.subtotalMrp - item.lineMrp),
        'item_discount': paiseToJson(o.itemDiscount - item.discount),
        'total': paiseToJson((o.total - item.lineTotal).clamp(0, 1 << 40)),
        'savings': paiseToJson((o.savings - (item.lineMrp - item.lineTotal)).clamp(0, 1 << 40)),
        'events': [
          ...o.events.map((e) => e.toJson()),
          OrderEvent(status: 'item_unavailable', note: '${item.name} · ${item.label}', at: DateTime.now()).toJson(),
        ],
      }),
    );
    _s.notify();
  }

  /// Demo only: pretend a new customer just ordered (to try the alert).
  void simulateNewOrder() {
    final picks = [..._catalog.visibleProducts]..shuffle();
    final items = <CartItem>[
      for (final p in picks.where((p) => p.defaultVariant?.inStock ?? false).take(3))
        CartItem(p.defaultVariant!.id, p.isLoose ? 0.5 : 1),
    ];
    final now = DateTime.now();
    final slots = upcomingSlots(_catalog.shop, now);
    final q = _price(items, null, Fulfilment.delivery);
    _s.orders.add(
      orderFromQuote(
        q,
        id: const Uuid().v4(),
        orderNo: _s.nextOrderNo(),
        status: OrderStatus.newOrder,
        fulfilment: Fulfilment.delivery,
        address: const Address(
          id: 'sim',
          name: 'Sunita Sharma',
          phone: '9812345678',
          line1: '7, Sector 13',
          pincode: '132001',
        ),
        slotDate: slots.isEmpty ? now : slots.first.date,
        slot: slots.isEmpty ? '18:00-21:00' : slots.first.slot,
        paymentMethod: 'cod',
        createdAt: now,
        customerName: 'Sunita Sharma',
        customerPhone: '9812345678',
        events: [OrderEvent(status: 'new', at: now)],
      ),
    );
    _s.notify();
  }

  @override
  Future<ProductGuess> identifyProduct({
    required String shopId,
    required Uint8List jpeg,
    required List<Category> categories,
  }) async => throw const AppException(
    'Photo recognition (AI) works in your real shop after setup — it needs the shop server. '
        'In the demo you can still add the photo and type the details.',
    'फ़ोटो से पहचान (AI) सेटअप के बाद असली दुकान में चलेगी — इसके लिए दुकान का सर्वर चाहिए। '
        'डेमो में फ़ोटो लगाकर जानकारी ख़ुद भर सकते हैं।',
  );

  @override
  String? imageUrl(String? path) => null;

  @override
  Uint8List? localImage(String? path) => path == null ? null : _s.photos[path];
}
