import 'dart:async';
import 'dart:typed_data';

import '../../core/money.dart';
import '../backend.dart';
import '../models/catalog.dart';
import '../models/category.dart';
import '../models/member.dart';
import '../models/product.dart';
import '../models/shop.dart';
import 'demo_catalog.dart';

/// Works fully offline with a sample shop. Changes live in memory until the
/// app restarts, so anyone can try every screen without an account.
class DemoBackend implements Backend {
  DemoBackend({required this.asShopkeeper});

  final bool asShopkeeper;
  Catalog _catalog = buildDemoCatalog();
  final _auth = StreamController<AppUser?>.broadcast();

  static const _demoUser = AppUser(id: 'demo-user', email: 'demo@example.com', name: 'Demo');

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
      _photos[full] = photo.full;
      _photos[thumb] = photo.thumb;
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

  @override
  String? imageUrl(String? path) => null;

  final _photos = <String, Uint8List>{};

  @override
  Uint8List? localImage(String? path) => path == null ? null : _photos[path];
}
