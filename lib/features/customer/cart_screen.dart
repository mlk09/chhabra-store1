import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/order_state.dart';
import '../../core/order_text.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../core/widgets/cart_widgets.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';
import '../../data/models/catalog.dart';
import '../../data/models/order.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final catalog = ref.watch(catalogProvider).value;
    final quoteAsync = ref.watch(quoteProvider);
    final session = ref.watch(sessionProvider).value;
    final choice = ref.watch(checkoutChoiceProvider);
    final t = Theme.of(context);

    if (catalog == null) return const Scaffold(body: LoadingView());
    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Your cart', 'आपका कार्ट'))),
        body: MessageView(
          icon: Icons.shopping_basket_outlined,
          title: context.tr('Your cart is empty', 'कार्ट ख़ाली है'),
          message: context.tr(
            'Add items from the shop to see the bill here.',
            'दुकान से सामान जोड़ें, बिल यहाँ दिखेगा।',
          ),
          actionLabel: context.tr('Start shopping', 'ख़रीदारी शुरू करें'),
          onAction: () => context.go('/shop'),
        ),
      );
    }

    final quote = quoteAsync.value;
    final canCheckout =
        quote != null &&
        quote.unavailable.isEmpty &&
        !quote.belowMinOrder &&
        quote.lines.isNotEmpty &&
        !quoteAsync.isLoading;
    final shop = catalog.shop;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Your cart', 'आपका कार्ट')),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await _confirm(context, context.tr('Empty the cart?', 'कार्ट ख़ाली करें?'));
              if (ok) ref.read(cartProvider.notifier).clear();
            },
            child: Text(context.tr('Clear', 'हटाएँ')),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('To pay', 'कुल भुगतान'), style: t.textTheme.bodySmall),
                    Text(
                      quote == null ? '…' : formatMoney(quote.total),
                      style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: !canCheckout
                      ? null
                      : () => (session?.isLoggedIn ?? false) ? context.push('/checkout') : context.push('/login'),
                  child: Text(
                    (session?.isLoggedIn ?? false)
                        ? context.tr('Checkout', 'आगे बढ़ें')
                        : context.tr('Log in to order', 'ऑर्डर के लिए लॉग इन'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(quoteProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (!shop.takingOrders)
              _Banner(
                color: Brand.red,
                icon: Icons.door_front_door_outlined,
                text:
                    shop.holidayNote ??
                    context.tr('The shop is not taking orders right now.', 'दुकान अभी ऑर्डर नहीं ले रही है।'),
              ),
            if (quoteAsync.hasError)
              _Banner(
                color: Brand.red,
                icon: Icons.cloud_off_rounded,
                text: orderErrorText(context, quoteAsync.error!),
              ),
            if (quote != null && quote.unavailable.isNotEmpty) _UnavailableCard(quote: quote, catalog: catalog),
            for (final e in cart.entries) _CartLine(variantId: e.key, catalog: catalog, line: _lineFor(quote, e.key)),
            const SizedBox(height: 8),
            if (shop.deliveryEnabled && shop.pickupEnabled)
              SegmentedButton<Fulfilment>(
                segments: [
                  ButtonSegment(
                    value: Fulfilment.delivery,
                    icon: const Icon(Icons.delivery_dining_rounded),
                    label: Text(context.tr('Home delivery', 'होम डिलीवरी')),
                  ),
                  ButtonSegment(
                    value: Fulfilment.pickup,
                    icon: const Icon(Icons.storefront_rounded),
                    label: Text(context.tr('Pick up', 'दुकान से लें')),
                  ),
                ],
                selected: {choice.fulfilment},
                onSelectionChanged: (s) => ref.read(checkoutChoiceProvider.notifier).setFulfilment(s.first),
              ),
            const SizedBox(height: 12),
            if (quote != null) _OfferHints(quote: quote, catalog: catalog, fulfilment: choice.fulfilment),
            const _CouponBox(),
            const SizedBox(height: 12),
            if (quote != null) BillCard(quote: quote),
            if (quote != null && quote.belowMinOrder)
              _Banner(
                color: Brand.saffronDeep,
                icon: Icons.info_outline,
                text: context.tr(
                  'Minimum order for delivery is ${formatMoney(quote.minOrder)}. Add ${formatMoney(quote.minOrder - quote.itemsTotal)} more, or choose pickup.',
                  'डिलीवरी के लिए कम से कम ${formatMoney(quote.minOrder)} का ऑर्डर। ${formatMoney(quote.minOrder - quote.itemsTotal)} का और जोड़ें या पिकअप चुनें।',
                ),
              ),
            if (quote == null && quoteAsync.isLoading) const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
          ],
        ),
      ),
    );
  }

  static QuoteLine? _lineFor(Quote? q, String variantId) => q?.lines.where((l) => l.variantId == variantId).firstOrNull;
}

Future<bool> _confirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('No', 'नहीं'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Yes', 'हाँ'))),
        ],
      ),
    ) ??
    false;

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});
  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _CartLine extends ConsumerWidget {
  const _CartLine({required this.variantId, required this.catalog, this.line});
  final String variantId;
  final Catalog catalog;
  final QuoteLine? line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final hit = catalog.variant(variantId);
    if (hit == null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(context.tr('Item no longer sold', 'यह सामान अब नहीं बिकता')),
        trailing: TextButton(
          onPressed: () => ref.read(cartProvider.notifier).setQty(variantId, 0),
          child: Text(context.tr('Remove', 'हटाएँ')),
        ),
      );
    }
    final (p, v) = hit;
    final l = line;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ProductImage(product: p, size: 56, fallbackEmoji: catalog.category(p.categoryId)?.icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.pick(p.name, p.nameHi),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodyLarge,
                ),
                Text(
                  '${v.label} · ${formatMoney(v.price)}${perUnitSuffix(v.unit, loose: p.isLoose)}',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
                if (l != null && l.offer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l.freeQty > 0
                          ? context.tr(
                              '${l.offer} · ${formatQty(l.freeQty, SaleUnit.pc)} free',
                              '${l.offer} · ${formatQty(l.freeQty, SaleUnit.pc)} फ़्री',
                            )
                          : l.offer!,
                      style: const TextStyle(color: Brand.green, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 130,
                  child: AddToCartButton(product: p, variant: v),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (l != null) ...[
                Text(formatMoney(l.lineTotal), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (l.lineMrp > l.lineTotal)
                  Text(
                    formatMoney(l.lineMrp),
                    style: t.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: t.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _UnavailableCard extends ConsumerWidget {
  const _UnavailableCard({required this.quote, required this.catalog});
  final Quote quote;
  final Catalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.read(cartProvider.notifier);
    return Card(
      color: Brand.red.withValues(alpha: 0.10),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Some items need your attention', 'कुछ सामान पर ध्यान दें'),
              style: const TextStyle(color: Brand.red, fontWeight: FontWeight.w800),
            ),
            for (final u in quote.unavailable)
              Builder(
                builder: (context) {
                  final hit = catalog.variant(u.variantId);
                  final name = hit == null
                      ? context.tr('An item', 'एक सामान')
                      : '${context.pick(hit.$1.name, hit.$1.nameHi)} · ${hit.$2.label}';
                  final short = u.reason == 'insufficient' && u.available > 0;
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          short
                              ? context.tr(
                                  '$name: only ${formatQty(u.available, hit?.$1.isLoose ?? false ? hit!.$2.unit : SaleUnit.pc)} left',
                                  '$name: सिर्फ़ ${formatQty(u.available, hit?.$1.isLoose ?? false ? hit!.$2.unit : SaleUnit.pc)} बचा है',
                                )
                              : context.tr('$name: not available now', '$name: अभी उपलब्ध नहीं'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => cart.setQty(u.variantId, short ? u.available : 0),
                        child: Text(
                          short
                              ? context.tr('Take ${formatQty(u.available, SaleUnit.pc)}', 'इतना लें')
                              : context.tr('Remove', 'हटाएँ'),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// "Add ₹120 more for FREE delivery" style nudges.
class _OfferHints extends StatelessWidget {
  const _OfferHints({required this.quote, required this.catalog, required this.fulfilment});
  final Quote quote;
  final Catalog catalog;
  final Fulfilment fulfilment;

  @override
  Widget build(BuildContext context) {
    final hints = <String>[];
    final shop = catalog.shop;
    final afterCart = quote.itemsTotal - quote.cartDiscount;
    if (fulfilment == Fulfilment.delivery && quote.deliveryCharge > 0 && shop.freeDeliveryAbove != null) {
      hints.add(
        context.tr(
          'Add ${formatMoney(shop.freeDeliveryAbove! - afterCart)} more for FREE delivery',
          '${formatMoney(shop.freeDeliveryAbove! - afterCart)} का और लें, डिलीवरी फ़्री',
        ),
      );
    }
    for (final o in catalog.liveCartOffers(DateTime.now())) {
      if (o.kind == OfferKind.freeDelivery || o.minOrder <= quote.itemsTotal) continue;
      if (quote.cartOffer == o.title) continue;
      hints.add(
        context.tr(
          'Add ${formatMoney(o.minOrder - quote.itemsTotal)} more: ${o.title}',
          '${formatMoney(o.minOrder - quote.itemsTotal)} का और लें: ${context.pick(o.title, o.titleHi)}',
        ),
      );
    }
    if (hints.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          for (final h in hints.take(2)) _Banner(color: Brand.green, icon: Icons.local_offer_outlined, text: h),
        ],
      ),
    );
  }
}

class _CouponBox extends ConsumerStatefulWidget {
  const _CouponBox();
  @override
  ConsumerState<_CouponBox> createState() => _CouponBoxState();
}

class _CouponBoxState extends ConsumerState<_CouponBox> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choice = ref.watch(checkoutChoiceProvider);
    final quote = ref.watch(quoteProvider).value;
    final publicCoupons = ref.watch(couponsProvider).value?.where((c) => c.isPublic && c.isActive).toList() ?? const [];
    final notifier = ref.read(checkoutChoiceProvider.notifier);
    final t = Theme.of(context);

    if (choice.coupon != null) {
      final err = quote?.couponError;
      return Card(
        child: ListTile(
          leading: Icon(
            err == null ? Icons.check_circle : Icons.error_outline,
            color: err == null ? Brand.green : Brand.red,
          ),
          title: Text(choice.coupon!, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(
            err != null
                ? couponErrorText(context, err, minOrder: quote?.couponMinOrder)
                : (quote == null
                      ? '…'
                      : quote.couponDiscount > 0
                      ? context.tr(
                          'You save ${formatMoney(quote.couponDiscount)}',
                          '${formatMoney(quote.couponDiscount)} की बचत',
                        )
                      : context.tr('Free delivery applied', 'फ़्री डिलीवरी लगी')),
            style: TextStyle(color: err == null ? Brand.green : Brand.red),
          ),
          trailing: TextButton(onPressed: () => notifier.setCoupon(null), child: Text(context.tr('Remove', 'हटाएँ'))),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  hintText: context.tr('Coupon code', 'कूपन कोड'),
                ),
                onSubmitted: (v) => notifier.setCoupon(v),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => notifier.setCoupon(_code.text), child: Text(context.tr('Apply', 'लगाएँ'))),
          ],
        ),
        if (publicCoupons.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in publicCoupons)
                ActionChip(
                  avatar: Icon(Icons.local_offer_rounded, size: 18, color: t.colorScheme.secondary),
                  label: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width - 110),
                    child: Text(c.title == null ? c.code : '${c.code} · ${c.title}', overflow: TextOverflow.ellipsis),
                  ),
                  onPressed: () => notifier.setCoupon(c.code),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Bill details: MRP → discounts → delivery → total, plus "You saved".
class BillCard extends StatelessWidget {
  const BillCard({super.key, required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget row(String label, String value, {Color? color, bool bold = false, bool strike = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : null),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 18 : null,
              decoration: strike ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Bill details', 'बिल'), style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            row(context.tr('Items (MRP)', 'सामान (MRP)'), formatMoney(quote.subtotalMrp)),
            if (quote.subtotalMrp - quote.itemsTotal > 0)
              row(
                context.tr('Discount on MRP & offers', 'MRP और ऑफ़र छूट'),
                '− ${formatMoney(quote.subtotalMrp - quote.itemsTotal)}',
                color: Brand.green,
              ),
            if (quote.cartDiscount > 0)
              row(
                quote.cartOffer ?? context.tr('Cart offer', 'कार्ट ऑफ़र'),
                '− ${formatMoney(quote.cartDiscount)}',
                color: Brand.green,
              ),
            if (quote.couponDiscount > 0)
              row(
                context.tr('Coupon ${quote.couponCode ?? ''}', 'कूपन ${quote.couponCode ?? ''}'),
                '− ${formatMoney(quote.couponDiscount)}',
                color: Brand.green,
              ),
            if (quote.deliveryCharge > 0)
              row(context.tr('Delivery', 'डिलीवरी'), formatMoney(quote.deliveryCharge))
            else if (quote.deliverySaved > 0)
              row(
                context.tr('Delivery (FREE)', 'डिलीवरी (फ़्री)'),
                formatMoney(quote.deliverySaved),
                color: Brand.green,
                strike: true,
              ),
            const Divider(height: 20),
            row(context.tr('Total', 'कुल'), formatMoney(quote.total), bold: true),
            if (quote.savings > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Brand.green.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  context.tr(
                    '🎉 You saved ${formatMoney(quote.savings)} on this order',
                    '🎉 इस ऑर्डर पर ${formatMoney(quote.savings)} की बचत',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.green, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
