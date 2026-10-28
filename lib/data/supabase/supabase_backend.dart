import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config.dart';
import '../../core/money.dart';
import '../backend.dart';
import '../models/catalog.dart';
import '../models/category.dart';
import '../models/member.dart';
import '../models/product.dart';
import '../models/shop.dart';

/// The real shop, backed by Supabase. Every write is checked again by RLS and
/// Postgres functions on the server — the app is never trusted with prices.
class SupabaseBackend implements Backend {
  SupabaseBackend(this.shopSlug);

  final String shopSlug;
  SupabaseClient get _db => Supabase.instance.client;
  String? _shopId;
  static const _bucket = 'product-images';
  static const _pageSize = 1000;

  @override
  bool get isDemo => false;

  AppUser? _toUser(User? u) => u == null
      ? null
      : AppUser(
          id: u.id,
          email: u.email,
          name: u.userMetadata?['full_name'] as String?,
          phone: u.userMetadata?['phone'] as String?,
        );

  @override
  AppUser? get currentUser => _toUser(_db.auth.currentUser);

  @override
  Stream<AppUser?> authChanges() => _db.auth.onAuthStateChange.map((s) => _toUser(s.session?.user));

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _db.auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<void> signUp({required String name, required String email, required String password, String? phone}) =>
      _guard(() async {
        final res = await _db.auth.signUp(
          email: email.trim(),
          password: password,
          data: {'full_name': name.trim(), if (phone != null && phone.isNotEmpty) 'phone': phone},
        );
        if (res.session == null) {
          throw const AppException(
            'Account created. Please confirm your email, then log in.',
            'खाता बन गया। ईमेल कन्फ़र्म करके लॉग इन करें।',
          );
        }
      });

  @override
  Future<void> sendPasswordReset(String email) => _guard(
    () => _db.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AppConfig.webAppUrl.isEmpty ? null : AppConfig.webAppUrl,
    ),
  );

  @override
  Future<void> updatePassword(String newPassword) =>
      _guard(() => _db.auth.updateUser(UserAttributes(password: newPassword)));

  @override
  Future<void> signOut() => _db.auth.signOut();

  @override
  Future<void> deleteAccount() => _guard(() async {
    await _db.rpc('delete_my_account');
    await _db.auth.signOut();
  });

  @override
  Future<Membership> membership() => _guard(() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return Membership.customer;
    final row = await _db
        .from('shop_members')
        .select('role, permissions, shops!inner(slug)')
        .eq('user_id', uid)
        .eq('shops.slug', shopSlug)
        .maybeSingle();
    if (row == null) return Membership.customer;
    return Membership(
      row['role'] == 'owner' ? ShopRole.owner : ShopRole.staff,
      ((row['permissions'] as List?) ?? const []).cast<String>().toSet(),
    );
  });

  Future<String> _requireShopId() async {
    if (_shopId != null) return _shopId!;
    final row = await _db.from('shops').select('id').eq('slug', shopSlug).maybeSingle();
    if (row == null) {
      throw const AppException(
        'Shop not found. Run the "setup-backend" GitHub Action first.',
        'दुकान नहीं मिली। पहले "setup-backend" GitHub Action चलाएँ।',
      );
    }
    return _shopId = row['id'] as String;
  }

  @override
  Future<Catalog> loadCatalog({required bool staffView, bool withCosts = false}) => _guard(() async {
    final shopRow = await _db.from('shops').select().eq('slug', shopSlug).maybeSingle();
    if (shopRow == null) await _requireShopId(); // throws the friendly message
    final shop = Shop.fromJson(shopRow!);
    _shopId = shop.id;

    final cats = await _db.from('categories').select().eq('shop_id', shop.id).order('sort_order');

    final products = <Map<String, dynamic>>[];
    for (var from = 0; ; from += _pageSize) {
      var q = _db.from('products').select('*, product_variants(*)').eq('shop_id', shop.id);
      if (!staffView) q = q.eq('is_active', true);
      final page = await q.order('id').range(from, from + _pageSize - 1);
      products.addAll(page);
      if (page.length < _pageSize) break;
    }

    if (withCosts) {
      final costs = <String, Object?>{};
      for (var from = 0; ; from += _pageSize) {
        final page = await _db
            .from('variant_costs')
            .select('variant_id, cost_price')
            .eq('shop_id', shop.id)
            .order('variant_id')
            .range(from, from + _pageSize - 1);
        for (final c in page) {
          costs[c['variant_id'] as String] = c['cost_price'];
        }
        if (page.length < _pageSize) break;
      }
      for (final p in products) {
        for (final v in (p['product_variants'] as List).cast<Map<String, dynamic>>()) {
          v['cost_price'] = costs[v['id']];
        }
      }
    }

    return Catalog(
      shop: shop,
      categories: cats.map(Category.fromJson).toList(),
      products: products.map(Product.fromJson).toList(),
    );
  });

  @override
  Future<Product> saveProduct(
    Product product, {
    ProductPhoto? photo,
    bool withCosts = false,
    Set<String>? stockChanged,
  }) => _guard(() async {
    final shopId = await _requireShopId();
    var toSave = product;
    String? oldFull, oldThumb;
    if (photo != null) {
      final stamp = const Uuid().v4().substring(0, 8);
      final full = '$shopId/${product.id}/$stamp.jpg';
      final thumb = '$shopId/${product.id}/${stamp}_t.jpg';
      final opts = const FileOptions(contentType: 'image/jpeg', cacheControl: '31536000', upsert: true);
      await _db.storage.from(_bucket).uploadBinary(full, photo.full, fileOptions: opts);
      await _db.storage.from(_bucket).uploadBinary(thumb, photo.thumb, fileOptions: opts);
      oldFull = product.imagePath;
      oldThumb = product.thumbPath;
      toSave = product.copyWith(imagePath: full, thumbPath: thumb);
    }

    await _db.rpc(
      'save_product',
      params: {
        'p_product': {...toSave.toRowJson(), 'shop_id': shopId},
        'p_variants': [
          for (final v in toSave.variants)
            {...v.toJson(), if (!withCosts) 'cost_price': null}
              ..removeWhere((k, _) => k == 'stock' && stockChanged != null && !stockChanged.contains(v.id)),
        ],
        'p_with_costs': withCosts,
      },
    );

    // New photo is safely saved → remove the old files (best effort).
    final stale = [oldFull, oldThumb].whereType<String>().toList();
    if (stale.isNotEmpty) unawaited(_db.storage.from(_bucket).remove(stale).then((_) {}, onError: (_) {}));

    final row = await _db.from('products').select('*, product_variants(*)').eq('id', product.id).single();
    if (withCosts) {
      final costs = {for (final v in toSave.variants) v.id: v.costPrice};
      for (final v in (row['product_variants'] as List).cast<Map<String, dynamic>>()) {
        final c = costs[v['id']];
        v['cost_price'] = c == null ? null : paiseToJson(c);
      }
    }
    return Product.fromJson(row);
  });

  @override
  Future<void> deleteProduct(String productId) => _guard(() async {
    final row = await _db.from('products').select('image_path, thumb_path').eq('id', productId).maybeSingle();
    await _db.from('products').delete().eq('id', productId);
    final files = [row?['image_path'], row?['thumb_path']].whereType<String>().toList();
    if (files.isNotEmpty) unawaited(_db.storage.from(_bucket).remove(files).then((_) {}, onError: (_) {}));
  });

  @override
  Future<Category> saveCategory(Category category) => _guard(() async {
    final shopId = await _requireShopId();
    final row = await _db.from('categories').upsert({...category.toJson(), 'shop_id': shopId}).select().single();
    return Category.fromJson(row);
  });

  @override
  Future<void> deleteCategory(String categoryId) => _guard(() => _db.from('categories').delete().eq('id', categoryId));

  @override
  Future<int> bulkUpdatePrices({
    required double percent,
    String? categoryId,
    String applyTo = 'both',
    String rounding = 'rupee',
  }) => _guard(() async {
    final shopId = await _requireShopId();
    final n = await _db.rpc(
      'bulk_update_prices',
      params: {
        'p_shop': shopId,
        'p_percent': percent,
        'p_category': categoryId,
        'p_apply_to': applyTo,
        'p_round': rounding,
      },
    );
    return (n as num).toInt();
  });

  @override
  Future<Shop> updateShop(Shop shop) => _guard(() async {
    final row = await _db.from('shops').update(shop.toEditableJson()).eq('id', shop.id).select().single();
    return Shop.fromJson(row);
  });

  @override
  String? imageUrl(String? path) => path == null ? null : AppConfig.imageUrl(path);

  @override
  Uint8List? localImage(String? path) => null;

  /// Turns Supabase errors into messages a shopkeeper understands.
  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run().timeout(const Duration(seconds: 25));
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const AppException('The internet is slow. Please try again.', 'इंटरनेट धीमा है। फिर से कोशिश करें।');
    } on AuthException catch (e) {
      throw _authError(e);
    } on PostgrestException catch (e) {
      throw _dbError(e);
    } on StorageException catch (e) {
      throw AppException('Photo upload failed: ${e.message}', 'फ़ोटो अपलोड नहीं हुई: ${e.message}');
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
        throw const AppException('No internet connection.', 'इंटरनेट कनेक्शन नहीं है।');
      }
      rethrow;
    }
  }

  AppException _authError(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) {
      return const AppException('Wrong email or password.', 'ईमेल या पासवर्ड गलत है।');
    }
    if (m.contains('already registered') || m.contains('already been registered')) {
      return const AppException(
        'This email already has an account. Please log in.',
        'इस ईमेल का खाता पहले से है। लॉग इन करें।',
      );
    }
    if (m.contains('password') && m.contains('characters')) {
      return const AppException('Password must be at least 6 characters.', 'पासवर्ड कम से कम 6 अक्षर का हो।');
    }
    if (m.contains('rate limit') || e.statusCode == '429') {
      return const AppException('Too many tries. Please wait a few minutes.', 'बहुत बार कोशिश हुई। कुछ मिनट रुकें।');
    }
    if (m.contains('email not confirmed')) {
      return const AppException('Please confirm your email first.', 'पहले अपना ईमेल कन्फ़र्म करें।');
    }
    return AppException(e.message);
  }

  AppException _dbError(PostgrestException e) {
    final m = e.message;
    if (e.code == '42501' || m.contains('permission')) {
      return AppException(
        m.contains('price') ? 'You do not have permission to change prices.' : 'You do not have permission for this.',
        m.contains('price') ? 'आपको कीमत बदलने की अनुमति नहीं है।' : 'आपको इसकी अनुमति नहीं है।',
      );
    }
    if (m.contains('price_not_above_mrp')) {
      return const AppException('Selling price cannot be more than MRP.', 'बिक्री मूल्य MRP से ज़्यादा नहीं हो सकता।');
    }
    if (m.contains('product_variants_barcode_uq')) {
      return const AppException(
        'This barcode is already used by another product.',
        'यह बारकोड पहले से किसी और सामान पर है।',
      );
    }
    if (m.contains('stock_check')) {
      return const AppException('Stock cannot be less than zero.', 'स्टॉक शून्य से कम नहीं हो सकता।');
    }
    if (e.code == '23514' || e.code == '22023' || e.code == '23502') {
      return AppException('Please check the details: $m', 'कृपया जानकारी जाँचें: $m');
    }
    return AppException(m);
  }
}
