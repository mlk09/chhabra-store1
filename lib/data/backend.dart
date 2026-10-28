import 'dart:typed_data';

import 'models/catalog.dart';
import 'models/category.dart';
import 'models/member.dart';
import 'models/product.dart';
import 'models/shop.dart';

/// A compressed product photo ready for upload (big + thumbnail JPEGs).
class ProductPhoto {
  const ProductPhoto({required this.full, required this.thumb});
  final Uint8List full;
  final Uint8List thumb;
}

/// Error with a message that is safe and useful to show the shopkeeper.
class AppException implements Exception {
  const AppException(this.message, [this.messageHi]);
  final String message;
  final String? messageHi;
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

  /// Public URL of a stored product image (live shop).
  String? imageUrl(String? path);

  /// Photo bytes kept in memory (demo shop only).
  Uint8List? localImage(String? path);
}
