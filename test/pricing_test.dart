import 'dart:convert';
import 'dart:io';

import 'package:chhabra_store/core/money.dart';
import 'package:chhabra_store/data/models/catalog.dart';
import 'package:chhabra_store/data/models/category.dart';
import 'package:chhabra_store/data/models/order.dart';
import 'package:chhabra_store/data/models/product.dart';
import 'package:chhabra_store/data/models/shop.dart';
import 'package:chhabra_store/domain/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same cases as supabase/tests/20_pricing_test.sql → the app's copy of the
/// pricing rules can never silently disagree with the server.
void main() {
  final d = jsonDecode(File('test_vectors/pricing.json').readAsStringSync()) as Map<String, dynamic>;
  final shop = Shop.fromJson({'id': 'shop', 'name': 'Pricing Test', ...(d['shop'] as Map).cast<String, dynamic>()});
  final catalog = Catalog(
    shop: shop,
    categories: [for (final c in d['categories'] as List) Category.fromJson((c as Map).cast())],
    products: [
      for (final p in d['products'] as List)
        Product.fromJson({
          ...(p as Map).cast<String, dynamic>(),
          'variants': [
            for (final v in p['variants'] as List) {...(v as Map).cast<String, dynamic>(), 'product_id': p['id']},
          ],
        }),
    ],
  );
  final offers = [for (final o in d['offers'] as List) Offer.fromJson((o as Map).cast())];
  final coupons = [for (final c in d['coupons'] as List) Coupon.fromJson((c as Map).cast())];
  final now = DateTime.parse(d['now'] as String);

  Map<String, Object?> asJson(Quote q) => {
    'subtotal_mrp': q.subtotalMrp,
    'items_total': q.itemsTotal,
    'item_discount': q.itemDiscount,
    'cart_discount': q.cartDiscount,
    'cart_offer': q.cartOffer,
    'coupon_code': q.couponCode,
    'coupon_discount': q.couponDiscount,
    'coupon_error': q.couponError,
    'coupon_min_order': q.couponMinOrder,
    'delivery_charge': q.deliveryCharge,
    'delivery_saved': q.deliverySaved,
    'total': q.total,
    'savings': q.savings,
    'below_min_order': q.belowMinOrder,
  };

  const moneyKeys = {
    'subtotal_mrp',
    'items_total',
    'item_discount',
    'cart_discount',
    'coupon_discount',
    'coupon_min_order',
    'delivery_charge',
    'delivery_saved',
    'total',
    'savings',
    'discount',
    'line_total',
  };
  Object? want(String key, Object? v) => v is num && moneyKeys.contains(key) ? paiseFromJson(v) : v;

  for (final raw in d['cases'] as List) {
    final cs = (raw as Map).cast<String, dynamic>();
    test(cs['name'], () {
      Quote run() => priceCart(
        catalog: catalog,
        offers: offers,
        coupons: coupons,
        items: [for (final i in cs['items'] as List) CartItem(i['variant_id'] as String, (i['qty'] as num).toDouble())],
        couponCode: cs['coupon'] as String?,
        fulfilment: cs['fulfilment'] == 'pickup' ? Fulfilment.pickup : Fulfilment.delivery,
        userId: cs['logged_in'] == true ? 'buyer' : null,
        now: now,
      );
      if (cs.containsKey('error')) {
        expect(run, throwsA(isA<PricingError>().having((e) => e.code, 'code', cs['error'])));
        return;
      }
      final q = run();
      final got = asJson(q);
      (cs['expect'] as Map).forEach((key, value) {
        if (key == 'lines') {
          (value as Map).forEach((variantId, fields) {
            final line = q.lines.firstWhere((l) => l.variantId == variantId);
            final lj = {
              'discount': line.discount,
              'line_total': line.lineTotal,
              'free_qty': line.freeQty,
              'offer': line.offer,
              'qty': line.qty,
            };
            (fields as Map).forEach((k, v) {
              final w = want(k as String, v);
              expect(lj[k], w is num ? closeTo(w, 1e-9) : w, reason: 'line $variantId $k');
            });
          });
        } else if (key == 'unavailable') {
          final gotU = [for (final u in q.unavailable) '${u.variantId}:${u.reason}:${u.available}']..sort();
          final wantU = [
            for (final u in value as List) '${u['variant_id']}:${u['reason']}:${(u['available'] as num).toDouble()}',
          ]..sort();
          expect(gotU, wantU);
        } else {
          expect(got[key], want(key as String, value), reason: key);
        }
      });
    });
  }
}
