import '../core/money.dart';
import '../data/models/catalog.dart';
import '../data/models/order.dart';
import '../data/models/product.dart';

/// Thrown for a cart the server would reject outright (e.g. 1.5 packets).
class PricingError implements Exception {
  const PricingError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

int _milli(double qty) => (qty * 1000).round();

/// price × qty, rounded to the paisa (half away from zero), like Postgres round(x, 2).
Paise _times(Paise price, double qty) => (price * _milli(qty) + 500) ~/ 1000;

/// base × percent / 100, rounded to the paisa.
Paise _percentOf(Paise base, double percent) => (base * (percent * 100).round() + 5000) ~/ 10000;

int _byCreated(Offer a, Offer b) {
  final ta = a.createdAt ?? DateTime(2000), tb = b.createdAt ?? DateTime(2000);
  final c = ta.compareTo(tb);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Dart copy of the server's price_cart() (supabase/migrations/0003_orders.sql).
/// Used by Demo mode and for offline counter bills. Real online orders are
/// always priced by the server. Both are checked against test_vectors/pricing.json.
Quote priceCart({
  required Catalog catalog,
  required List<Offer> offers,
  required List<CartItem> items,
  required Fulfilment fulfilment,
  required DateTime now,
  List<Coupon> coupons = const [],
  String? couponCode,
  String? userId,
  int Function(String couponId)? timesUsedByUser,
}) {
  if (items.isEmpty || items.length > 100) {
    throw const PricingError('bad_request', 'Cart must have 1 to 100 items');
  }
  final shop = catalog.shop;
  final merged = <String, double>{};
  for (final i in items) {
    if (i.qty <= 0 || i.qty > 1000) throw const PricingError('bad_quantity', 'Invalid quantity');
    merged[i.variantId] = (merged[i.variantId] ?? 0) + i.qty;
  }
  final live = offers.where((o) => o.liveAt(now)).toList()..sort(_byCreated);

  final lines = <QuoteLine>[];
  final unavailable = <UnavailableLine>[];
  var subMrp = 0, itemsTotal = 0, itemDiscount = 0;

  for (final variantId in merged.keys.toList()..sort()) {
    final qty = merged[variantId]!;
    final hit = catalog.variant(variantId);
    final Product? p = hit?.$1;
    final Variant? v = hit?.$2;
    if (p == null || v == null || !v.isActive || !p.isActive) {
      unavailable.add(UnavailableLine(variantId: variantId, reason: 'unavailable'));
      continue;
    }
    if (!p.isLoose && qty != qty.truncateToDouble()) {
      throw PricingError('bad_quantity', 'Whole quantity needed for ${p.name}');
    }
    if (v.trackStock && v.stock < qty) {
      unavailable.add(UnavailableLine(variantId: variantId, reason: 'insufficient', available: v.stock));
      continue;
    }

    final base = _times(v.price, qty);
    final lineMrp = _times(v.mrp, qty);
    var best = 0;
    String? title;
    var free = 0.0;
    for (final o in live) {
      final applies =
          (o.productId == p.id && o.kind.forProduct) ||
          (o.kind == OfferKind.categoryPercent && o.categoryId != null && o.categoryId == p.categoryId);
      if (!applies) continue;
      var d = 0;
      var fq = 0.0;
      switch (o.kind) {
        case OfferKind.productPercent:
        case OfferKind.categoryPercent:
          d = _percentOf(base, o.percent!);
        case OfferKind.productFlat:
          d = _times(o.amount! < v.price ? o.amount! : v.price, qty);
        case OfferKind.bxgy:
          if (!p.isLoose) {
            fq = (qty / (o.buyQty! + o.getQty!)).floorToDouble() * o.getQty!;
            d = _times(v.price, fq);
          }
        default:
          break;
      }
      if (d > best) {
        best = d;
        title = o.title;
        free = fq;
      }
    }
    if (best > base) best = base;

    lines.add(
      QuoteLine(
        variantId: v.id,
        productId: p.id,
        name: p.name,
        nameHi: p.nameHi,
        label: v.label,
        unit: v.unit,
        isLoose: p.isLoose,
        qty: qty,
        mrp: v.mrp,
        price: v.price,
        lineMrp: lineMrp,
        discount: best,
        lineTotal: base - best,
        freeQty: free,
        offer: title,
      ),
    );
    subMrp += lineMrp;
    itemsTotal += base - best;
    itemDiscount += best;
  }

  // Best cart offer
  var cartDiscount = 0;
  String? cartOffer;
  for (final o in live) {
    if (!(o.kind == OfferKind.cartFlat || o.kind == OfferKind.cartPercent) || o.minOrder > itemsTotal) continue;
    var d = o.kind == OfferKind.cartFlat
        ? (o.amount! < itemsTotal ? o.amount! : itemsTotal)
        : _percentOf(itemsTotal, o.percent!);
    if (o.kind == OfferKind.cartPercent) {
      final cap = o.maxDiscount ?? itemsTotal;
      if (d > cap) d = cap;
    }
    if (d > cartDiscount) {
      cartDiscount = d;
      cartOffer = o.title;
    }
  }
  final afterCart = itemsTotal - cartDiscount;
  var freeDelivery = live.any((o) => o.kind == OfferKind.freeDelivery && o.minOrder <= itemsTotal);

  // Coupon
  final code = couponCode?.trim().toUpperCase();
  String? couponError, couponId;
  Paise? couponMin;
  var couponDiscount = 0;
  if (code != null && code.isNotEmpty) {
    final c = coupons.where((c) => c.code == code).firstOrNull;
    if (c == null || !c.isActive) {
      couponError = 'invalid';
    } else if (c.startsAt != null && c.startsAt!.isAfter(now)) {
      couponError = 'not_started';
    } else if (c.endsAt != null && !c.endsAt!.isAfter(now)) {
      couponError = 'expired';
    } else if (c.usageLimit != null && c.usedCount >= c.usageLimit!) {
      couponError = 'used_up';
    } else if (userId == null) {
      couponError = 'login_required';
    } else if ((timesUsedByUser?.call(c.id) ?? 0) >= c.perUserLimit) {
      couponError = 'already_used';
    } else if (itemsTotal < c.minOrder) {
      couponError = 'min_order';
      couponMin = c.minOrder;
    } else {
      couponId = c.id;
      switch (c.kind) {
        case CouponKind.percent:
          couponDiscount = _percentOf(afterCart, c.value.toDouble());
          final cap = c.maxDiscount ?? afterCart;
          if (couponDiscount > cap) couponDiscount = cap;
        case CouponKind.flat:
          couponDiscount = c.value.toInt() < afterCart ? c.value.toInt() : afterCart;
        case CouponKind.freeDelivery:
          freeDelivery = true;
      }
    }
  }
  final after = afterCart - couponDiscount;

  var delivery = 0, deliverySaved = 0;
  if (fulfilment == Fulfilment.delivery && lines.isNotEmpty) {
    if (freeDelivery || (shop.freeDeliveryAbove != null && afterCart >= shop.freeDeliveryAbove!)) {
      deliverySaved = shop.deliveryCharge;
    } else {
      delivery = shop.deliveryCharge;
    }
  }

  return Quote(
    lines: lines,
    unavailable: unavailable,
    subtotalMrp: subMrp,
    itemsTotal: itemsTotal,
    itemDiscount: itemDiscount,
    cartDiscount: cartDiscount,
    cartOffer: cartOffer,
    couponCode: (code == null || code.isEmpty) ? null : code,
    couponId: couponId,
    couponDiscount: couponDiscount,
    couponError: couponError,
    couponMinOrder: couponMin,
    deliveryCharge: delivery,
    deliverySaved: deliverySaved,
    total: after + delivery,
    savings: (subMrp - after) + deliverySaved,
    minOrder: shop.minOrder,
    belowMinOrder: fulfilment == Fulfilment.delivery && lines.isNotEmpty && itemsTotal < shop.minOrder,
  );
}
