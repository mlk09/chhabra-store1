import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';
import '../../data/models/catalog.dart';
import '../../data/models/category.dart';
import '../common/demo_banner.dart';

class CustomerHome extends ConsumerWidget {
  const CustomerHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final session = ref.watch(sessionProvider).value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: catalog.when(
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(catalogProvider)),
          data: (c) => RefreshIndicator(
            onRefresh: () => ref.read(catalogProvider.notifier).refresh(),
            child: _HomeBody(catalog: c, isShopkeeper: session?.isShopkeeper ?? false),
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.catalog, required this.isShopkeeper});
  final Catalog catalog;
  final bool isShopkeeper;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final shop = catalog.shop;
    final categories = catalog.activeCategories.where((c) => catalog.inCategory(c.id).isNotEmpty).toList();
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          titleSpacing: 16,
          toolbarHeight: 64,
          title: Row(
            children: [
              const AppLogo(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.pick(shop.name, shop.nameHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [shop.address, shop.city].whereType<String>().join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (isShopkeeper)
              IconButton(
                tooltip: context.tr('Back to shop management', 'दुकान मैनेजमेंट पर जाएँ'),
                icon: const Icon(Icons.storefront_rounded),
                onPressed: () => context.go('/owner'),
              ),
            IconButton(
              tooltip: context.tr('Account', 'खाता'),
              icon: const Icon(Icons.account_circle_outlined, size: 30),
              onPressed: () => context.push('/account'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        const SliverToBoxAdapter(child: DemoBanner()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _SearchBox(onTap: () => context.push('/shop/search')),
          ),
        ),
        if (shop.holidayMode || !shop.isOpen)
          SliverToBoxAdapter(
            child: _Notice(
              icon: Icons.door_front_door_outlined,
              color: Brand.red,
              text: shop.holidayMode
                  ? (shop.holidayNote ?? context.tr('Shop is closed for a holiday.', 'दुकान छुट्टी पर बंद है।'))
                  : context.tr(
                      'Shop is closed right now. You can still browse.',
                      'दुकान अभी बंद है। आप सामान देख सकते हैं।',
                    ),
            ),
          ),
        SliverToBoxAdapter(child: _HeroBanner(catalog: catalog)),
        SliverToBoxAdapter(child: SectionTitle(context.tr('Shop by category', 'कैटेगरी से खरीदें'))),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 104 * (MediaQuery.textScalerOf(context).scale(14) / 14),
            ),
            itemCount: categories.length,
            itemBuilder: (_, i) => _CategoryTile(category: categories[i]),
          ),
        ),
        SliverList.builder(
          itemCount: categories.length,
          itemBuilder: (_, i) => _CategoryRow(catalog: catalog, category: categories[i]),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Material(
      color: t.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: t.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('Search "atta", "cheeni", "aloo"…', '"आटा", "चीनी", "आलू" खोजें…'),
                  style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
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

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.catalog});
  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final shop = catalog.shop;
    final bestDeal = catalog.visibleProducts
        .where((p) => p.defaultVariant != null)
        .fold<int>(0, (m, p) => p.defaultVariant!.percentOffMrp > m ? p.defaultVariant!.percentOffMrp : m);
    final lines = <String>[
      if (shop.freeDeliveryAbove != null)
        context.tr(
          'Free delivery above ${formatMoney(shop.freeDeliveryAbove!)}',
          '${formatMoney(shop.freeDeliveryAbove!)} से ऊपर फ्री डिलीवरी',
        ),
      context.tr(
        'Delivery in ${shop.deliveryRadiusKm.toStringAsFixed(0)} km · Pickup at shop',
        '${shop.deliveryRadiusKm.toStringAsFixed(0)} किमी तक डिलीवरी · दुकान से पिकअप',
      ),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Color(0xFFE07A12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bestDeal > 0
                      ? context.tr('Up to $bestDeal% off MRP', 'MRP पर $bestDeal% तक छूट')
                      : context.pick(shop.tagline ?? 'Fresh groceries, fair prices', 'ताज़ा सामान, सही दाम'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2B1600),
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                for (final l in lines)
                  Text(
                    '• $l',
                    style: const TextStyle(fontSize: 14.5, color: Color(0xFF3D2200), fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text('🛒', style: TextStyle(fontSize: 54)),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.push('/shop/c/${category.id}'),
      child: Column(
        children: [
          Container(
            height: 64,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(category.icon ?? '🛍️', style: const TextStyle(fontSize: 32)),
          ),
          const SizedBox(height: 4),
          Text(
            context.pick(category.name, category.nameHi),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
          ),
        ],
      ),
    );
  }
}

/// One horizontal shelf per category.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.catalog, required this.category});
  final Catalog catalog;
  final Category category;

  @override
  Widget build(BuildContext context) {
    final items = catalog.inCategory(category.id);
    const cardWidth = 156.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          context.pick(category.name, category.nameHi),
          trailing: TextButton(
            onPressed: () => context.push('/shop/c/${category.id}'),
            child: Text(context.tr('See all (${items.length})', 'सभी (${items.length})')),
          ),
        ),
        SizedBox(
          height: cardWidth / 1.15 + productCardTextHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length.clamp(0, 12),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: cardWidth,
              child: ProductCard(
                product: items[i],
                catalog: catalog,
                onTap: () => context.push('/shop/p/${items[i].id}'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
