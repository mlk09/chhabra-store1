import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/order.dart';
import 'app_state.dart';

// ── Cart ─────────────────────────────────────────────────────────────────────

/// variantId → quantity (pieces, or kg/litre for loose items). Saved on the
/// phone so the cart survives closing the app. Demo and real shop keep separate carts.
class CartController extends Notifier<Map<String, double>> {
  String get _key => ref.read(sessionProvider).value?.isDemo ?? true ? 'cart:demo' : 'cart:live';

  @override
  Map<String, double> build() {
    ref.watch(sessionProvider.select((s) => s.value?.isDemo));
    final raw = ref.read(localStoreProvider).pref<String>(_key);
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble()));
    } catch (_) {
      return const {};
    }
  }

  void _save(Map<String, double> next) {
    state = Map.unmodifiable(next);
    unawaited(ref.read(localStoreProvider).setPref(_key, next.isEmpty ? null : jsonEncode(next)));
  }

  double qtyOf(String variantId) => state[variantId] ?? 0;

  void setQty(String variantId, double qty) {
    final next = {...state};
    final rounded = (qty * 1000).round() / 1000;
    if (rounded <= 0) {
      next.remove(variantId);
    } else {
      next[variantId] = rounded > 1000 ? 1000 : rounded;
    }
    _save(next);
  }

  void add(String variantId, double step) => setQty(variantId, qtyOf(variantId) + step);

  /// Replace the cart (Reorder).
  void replaceWith(Map<String, double> items) => _save(items);

  void clear() => _save(const {});
}

final cartProvider = NotifierProvider<CartController, Map<String, double>>(CartController.new);

/// Number of different items in the cart (badge).
final cartCountProvider = Provider<int>((ref) => ref.watch(cartProvider).length);

class CheckoutChoice {
  const CheckoutChoice({this.coupon, this.fulfilment = Fulfilment.delivery});
  final String? coupon;
  final Fulfilment fulfilment;
}

class CheckoutChoiceController extends Notifier<CheckoutChoice> {
  @override
  CheckoutChoice build() => const CheckoutChoice();

  void setCoupon(String? code) => state = CheckoutChoice(
    coupon: (code == null || code.trim().isEmpty) ? null : code.trim().toUpperCase(),
    fulfilment: state.fulfilment,
  );

  void setFulfilment(Fulfilment f) => state = CheckoutChoice(coupon: state.coupon, fulfilment: f);
}

final checkoutChoiceProvider = NotifierProvider<CheckoutChoiceController, CheckoutChoice>(CheckoutChoiceController.new);

/// The bill for the current cart. Always priced by the server in the real
/// shop (the app never decides a price), by the demo copy in Demo mode.
final quoteProvider = FutureProvider.autoDispose<Quote?>((ref) async {
  final cart = ref.watch(cartProvider);
  final choice = ref.watch(checkoutChoiceProvider);
  final backend = ref.watch(backendProvider);
  if (cart.isEmpty) return null;
  // Small pause so tapping + five times sends one request, not five.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  if (!ref.mounted) return null;
  return backend.quoteCart(
    items: [for (final e in cart.entries) CartItem(e.key, e.value)],
    coupon: choice.coupon,
    fulfilment: choice.fulfilment,
  );
});

// ── Customer data ────────────────────────────────────────────────────────────

class AddressesController extends AsyncNotifier<List<Address>> {
  @override
  Future<List<Address>> build() async {
    final s = await ref.watch(sessionProvider.future);
    if (!s.isLoggedIn) return const [];
    return s.backend.addresses();
  }

  Future<Address> save(Address a) async {
    final saved = await ref.read(backendProvider).saveAddress(a);
    state = AsyncData([...?state.value?.where((x) => x.id != saved.id), saved]);
    return saved;
  }

  Future<void> delete(String id) async {
    await ref.read(backendProvider).deleteAddress(id);
    state = AsyncData([...?state.value?.where((x) => x.id != id)]);
  }
}

final addressesProvider = AsyncNotifierProvider<AddressesController, List<Address>>(AddressesController.new);

/// Coupons the person may see: public ones for customers, all for the owner.
final couponsProvider = FutureProvider<List<Coupon>>((ref) async {
  final s = await ref.watch(sessionProvider.future);
  return s.backend.loadCoupons();
});

final myOrdersProvider = StreamProvider<List<Order>>((ref) {
  final s = ref.watch(sessionProvider).value;
  if (s == null || !s.isLoggedIn) return Stream.value(const []);
  return s.backend.watchMyOrders();
});

final buyAgainProvider = FutureProvider<List<String>>((ref) async {
  final s = await ref.watch(sessionProvider.future);
  ref.watch(myOrdersProvider); // refresh after each new order
  if (!s.isLoggedIn || s.isShopkeeper) return const [];
  return s.backend.recentlyBoughtProductIds();
});

final orderProvider = StreamProvider.family<Order, String>((ref, id) => ref.watch(backendProvider).watchOrder(id));

// ── Shop side ────────────────────────────────────────────────────────────────

final shopOrdersProvider = StreamProvider<List<Order>>((ref) {
  final s = ref.watch(sessionProvider).value;
  if (s == null || !s.isShopkeeper) return Stream.value(const []);
  return s.backend.watchShopOrders();
});

/// Orders waiting for the shop to accept (badge on the Orders tab).
final newOrderCountProvider = Provider<int>(
  (ref) => ref.watch(shopOrdersProvider).value?.where((o) => o.status == OrderStatus.newOrder).length ?? 0,
);
