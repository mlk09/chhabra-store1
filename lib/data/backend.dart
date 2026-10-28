import 'dart:typed_data';

import 'models/catalog.dart';
import 'models/category.dart';
import 'models/member.dart';
import 'models/order.dart';
import 'models/product.dart';
import 'models/product_guess.dart';
import 'models/shop.dart';

/// A compressed product photo ready for upload (big + thumbnail JPEGs).
class ProductPhoto {
  const ProductPhoto({required this.full, required this.thumb});
  final Uint8List full;
  final Uint8List thumb;
}

/// Error with a message that is safe and useful to show the shopkeeper.
class AppException implements Exception {
  const AppException(this.message, [this.messageHi, this.code, this.data = const {}]);
  final String message;
  final String? messageHi;

  /// Machine-readable reason from the server, e.g. 'price_changed', 'bad_slot'.
  final String? code;
  final Map<String, dynamic> data;
  @override
  String toString() => message;
}

/// One interface, two implementations: [DemoBackend] (offline sample shop)
/// and [SupabaseBackend] (the real shop). Screens never know which one they use.
abstract class Backend {
  bool get isDemo;

  // ── Account ──
  AppUser? get currentUser;
  Stream<AppUser?> authChanges();
  Future<void> signIn({required String email, required String password});
  Future<void> signUp({required String name, required String email, required String password, String? phone});
  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
  Future<void> signOut();
  Future<void> deleteAccount();

  /// Role of the logged-in person in this shop (customer if none).
  Future<Membership> membership();

  // ── Catalog ──
  /// [staffView]: include inactive items and (if allowed) cost prices.
  Future<Catalog> loadCatalog({required bool staffView, bool withCosts = false});

  /// [stockChanged]: ids of sizes whose stock the shopkeeper edited. Other sizes
  /// keep the server's stock, so sales made meanwhile are not overwritten.
  /// Null sends every stock value (new products).
  Future<Product> saveProduct(
    Product product, {
    ProductPhoto? photo,
    bool withCosts = false,
    Set<String>? stockChanged,
  });
  Future<void> deleteProduct(String productId);
  Future<Category> saveCategory(Category category);
  Future<void> deleteCategory(String categoryId);

  /// Returns how many variants changed.
  Future<int> bulkUpdatePrices({
    required double percent,
    String? categoryId,
    String applyTo = 'both',
    String rounding = 'rupee',
  });
  Future<Shop> updateShop(Shop shop);

  // ── Offers & coupons (owner) ──
  Future<Offer> saveOffer(Offer offer);
  Future<void> deleteOffer(String offerId);

  /// Owner/offer staff: all coupons. Customers: only public ones.
  Future<List<Coupon>> loadCoupons();
  Future<Coupon> saveCoupon(Coupon coupon);
  Future<void> deleteCoupon(String couponId);

  // ── Cart & checkout ──
  /// The bill for a cart, priced by the server (or the demo copy of the rules).
  Future<Quote> quoteCart({required List<CartItem> items, String? coupon, required Fulfilment fulfilment});

  /// Places the order. [expectedTotal] is what the customer saw; if prices
  /// changed meanwhile the server refuses with code 'price_changed'.
  /// Returns the new order id.
  Future<String> placeOrder(OrderRequest request);

  Future<List<Address>> addresses();
  Future<Address> saveAddress(Address address);
  Future<void> deleteAddress(String addressId);

  // ── Orders ──
  /// The customer's own orders, newest first, kept live.
  Stream<List<Order>> watchMyOrders();

  /// Shop side: recent orders, newest first, kept live (new-order alerts).
  Stream<List<Order>> watchShopOrders();

  /// One order with items + timeline, kept live.
  Stream<Order> watchOrder(String orderId);
  Future<void> setOrderStatus(String orderId, OrderStatus status, {String? note});

  /// Products the logged-in customer bought before, most recent first ("Buy again").
  Future<List<String>> recentlyBoughtProductIds();
  Future<void> markItemUnavailable(String orderItemId);

  /// Reads a product photo with AI (name, Hindi name, brand, size, MRP,
  /// category). [jpeg] should be the compressed photo, not the raw camera file.
  Future<ProductGuess> identifyProduct({
    required String shopId,
    required Uint8List jpeg,
    required List<Category> categories,
  });

  /// Public URL of a stored product image (live shop).
  String? imageUrl(String? path);

  /// Photo bytes kept in memory (demo shop only).
  Uint8List? localImage(String? path);
}

class OrderRequest {
  const OrderRequest({
    required this.items,
    required this.fulfilment,
    required this.paymentMethod,
    required this.slotDate,
    required this.slot,
    this.addressId,
    this.coupon,
    this.note,
    required this.clientRef,
    required this.expectedTotal,
  });

  final List<CartItem> items;
  final Fulfilment fulfilment;
  final String paymentMethod;
  final DateTime slotDate;
  final String slot;
  final String? addressId;
  final String? coupon;
  final String? note;

  /// Same id on a retry → the server returns the same order (no duplicates).
  final String clientRef;
  final int expectedTotal;
}
