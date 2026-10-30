import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/order_state.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';
import '../../data/models/catalog.dart';
import '../../data/models/member.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import '../common/demo_banner.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(catalogProvider);
    final session = ref.watch(sessionProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Shop dashboard', 'दुकान डैशबोर्ड')),
        actions: [
          IconButton(
            tooltip: context.tr('See shop as customer', 'ग्राहक की नज़र से देखें'),
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => context.go('/shop'),
          ),
        ],
      ),
      floatingActionButton: (session?.can(Perm.prices) ?? false)
          ? FloatingActionButton.extended(
              heroTag: null, // several tabs have one; no shared hero animation
              onPressed: () => context.push('/owner/product/new'),
              icon: const Icon(Icons.add),
              label: Text(context.tr('Add product', 'सामान जोड़ें')),
            )
          : null,
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(catalogProvider)),
        data: (c) => RefreshIndicator(
          onRefresh: () => ref.read(catalogProvider.notifier).refresh(),
          child: _Body(catalog: c),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.catalog});
  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final products = catalog.products;
    final active = products.where((p) => p.isActive).length;
    final low = products.where((p) => p.isActive && p.isLowStock).toList();
    final soon = DateTime.now().add(const Duration(days: 30));
    final expiring =
        products.where((p) => p.isActive && p.nearestExpiry != null && p.nearestExpiry!.isBefore(soon)).toList()
          ..sort((a, b) => a.nearestExpiry!.compareTo(b.nearestExpiry!));
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? context.tr('Good morning', 'सुप्रभात')
        : hour < 17
        ? context.tr('Good afternoon', 'नमस्ते')
        : context.tr('Good evening', 'शुभ संध्या');

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        const DemoBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            '$greet 🙏  ${context.pick(catalog.shop.name, catalog.shop.nameHi)}',
            style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ),
        if (!catalog.shop.serviceActive)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              context.tr(
                'Online orders are paused by your app provider${catalog.shop.serviceNote == null ? '' : ': ${catalog.shop.serviceNote}'}. Please contact them.',
                'आपके ऐप प्रोवाइडर ने ऑनलाइन ऑर्डर रोके हैं${catalog.shop.serviceNote == null ? '' : ': ${catalog.shop.serviceNote}'}। कृपया उनसे बात करें।',
              ),
              style: const TextStyle(color: Brand.red, fontWeight: FontWeight.w700),
            ),
          ),
        const _TodayOrders(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 700 ? 4 : 2;
              final w = (c.maxWidth - 12 * (cols - 1)) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final s in [
                    (
                      context.tr('Products on sale', 'बिक रहे सामान'),
                      '$active',
                      Icons.inventory_2_rounded,
                      Brand.green,
                      '/owner/products',
                    ),
                    (
                      context.tr('Low stock', 'कम स्टॉक'),
                      '${low.length}',
                      Icons.warning_amber_rounded,
                      Brand.saffron,
                      '/owner/products?filter=low',
                    ),
                    (
                      context.tr('Expiring in 30 days', '30 दिन में एक्सपायरी'),
                      '${expiring.length}',
                      Icons.event_busy_rounded,
                      Brand.red,
                      '/owner/products?filter=expiry',
                    ),
                    (
                      context.tr('Categories', 'कैटेगरी'),
                      '${catalog.categories.length}',
                      Icons.category_rounded,
                      const Color(0xFF5B8DEF),
                      '/owner/categories',
                    ),
                  ])
                    SizedBox(
                      width: w,
                      child: _StatCard(label: s.$1, value: s.$2, icon: s.$3, color: s.$4, route: s.$5),
                    ),
                ],
              );
            },
          ),
        ),
        SectionTitle(context.tr('Quick actions', 'जल्दी करें')),
        SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _Action(
                icon: Icons.add_box_rounded,
                label: context.tr('Add product', 'सामान जोड़ें'),
                route: '/owner/product/new',
              ),
              _Action(icon: Icons.local_offer_rounded, label: context.tr('Offers', 'ऑफ़र'), route: '/owner/offers'),
              _Action(
                icon: Icons.add_photo_alternate_rounded,
                label: context.tr('Bulk photos', 'एक साथ फ़ोटो'),
                route: '/owner/bulk-photos',
              ),
              _Action(
                icon: Icons.percent_rounded,
                label: context.tr('Bulk price', 'एक साथ रेट'),
                route: '/owner/bulk-price',
              ),
              _Action(
                icon: Icons.category_rounded,
                label: context.tr('Categories', 'कैटेगरी'),
                route: '/owner/categories',
              ),
              _Action(
                icon: Icons.store_mall_directory_rounded,
                label: context.tr('Shop details', 'दुकान की जानकारी'),
                route: '/owner/shop',
              ),
            ],
          ),
        ),
        if (low.isNotEmpty) ...[
          SectionTitle(context.tr('Running low — reorder soon', 'स्टॉक कम — जल्द मँगवाएँ')),
          for (final p in low.take(6)) _AlertTile(product: p, catalog: catalog, kind: _AlertKind.low),
        ],
        if (expiring.isNotEmpty) ...[
          SectionTitle(context.tr('Expiring soon', 'जल्द एक्सपायर')),
          for (final p in expiring.take(6)) _AlertTile(product: p, catalog: catalog, kind: _AlertKind.expiry),
        ],
        if (products.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: MessageView(
              icon: Icons.add_shopping_cart_rounded,
              title: context.tr('Add your first product', 'अपना पहला सामान जोड़ें'),
              message: context.tr(
                'Your price list is empty. Tap "Add product" to start.',
                'रेट लिस्ट खाली है। "सामान जोड़ें" दबाएँ।',
              ),
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.route,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String route;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Products is a bottom-nav tab → go; other screens open on top → push.
        onTap: () => route.startsWith('/owner/products') ? context.go(route) : context.push(route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(value, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.route});
  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 96,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(route),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: t.colorScheme.primary, size: 30),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _AlertKind { low, expiry }

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.product, required this.catalog, required this.kind});
  final Product product;
  final Catalog catalog;
  final _AlertKind kind;

  @override
  Widget build(BuildContext context) {
    final String detail;
    if (kind == _AlertKind.low) {
      final v = product.variants.where((v) => v.isActive && v.trackStock).reduce((a, b) => a.stock <= b.stock ? a : b);
      detail = context.tr(
        '${v.label}: ${formatQty(v.stock, product.isLoose ? v.unit : SaleUnit.pc)} left',
        '${v.label}: ${formatQty(v.stock, product.isLoose ? v.unit : SaleUnit.pc)} बचे',
      );
    } else {
      final days = product.nearestExpiry!.difference(DateTime.now()).inDays;
      detail = days < 0
          ? context.tr('Expired', 'एक्सपायर हो गया')
          : context.tr('Expires in $days days', '$days दिन में एक्सपायर');
    }
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ProductImage(product: product, size: 48, fallbackEmoji: catalog.category(product.categoryId)?.icon),
      ),
      title: Text(context.pick(product.name, product.nameHi), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        detail,
        style: TextStyle(color: kind == _AlertKind.low ? Brand.saffronDeep : Brand.red, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/owner/product/${product.id}'),
    );
  }
}

/// "Today: 5 orders · ₹2,340 · 2 waiting" — tap to open Orders.
class _TodayOrders extends ConsumerWidget {
  const _TodayOrders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(shopOrdersProvider).value ?? const <Order>[];
    final now = DateTime.now();
    final today = orders
        .where((o) => o.status != OrderStatus.cancelled && DateUtils.isSameDay(o.createdAt, now))
        .toList();
    final waiting = orders.where((o) => o.status == OrderStatus.newOrder).length;
    final sales = today.fold<int>(0, (s, o) => s + o.total);
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        color: waiting > 0 ? Brand.saffron.withValues(alpha: 0.16) : null,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/owner/orders'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  color: waiting > 0 ? Brand.saffronDeep : t.colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(
                          'Today: ${today.length} orders · ${formatMoney(sales)}',
                          'आज: ${today.length} ऑर्डर · ${formatMoney(sales)}',
                        ),
                        style: t.textTheme.titleMedium,
                      ),
                      Text(
                        waiting > 0
                            ? context.tr('$waiting new — tap to accept', '$waiting नए — स्वीकार करने के लिए दबाएँ')
                            : context.tr('No new orders waiting', 'कोई नया ऑर्डर बाकी नहीं'),
                        style: TextStyle(
                          color: waiting > 0 ? Brand.saffronDeep : null,
                          fontWeight: waiting > 0 ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
