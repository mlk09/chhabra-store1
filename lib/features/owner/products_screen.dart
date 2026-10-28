import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';
import '../../data/models/catalog.dart';
import '../../data/models/member.dart';
import '../../data/models/product.dart';
import '../../domain/search.dart';

enum ProductFilter { all, low, expiry, inactive }

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});
  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _categoryId;
  ProductFilter _filter = ProductFilter.all;
  String? _appliedLink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Dashboard links like /owner/products?filter=low
    final link = GoRouterState.of(context).uri.queryParameters['filter'];
    if (link != _appliedLink) {
      _appliedLink = link;
      _filter = ProductFilter.values.where((f) => f.name == link).firstOrNull ?? ProductFilter.all;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<Product> _visible(Catalog c) {
    Iterable<Product> list = _query.trim().isEmpty ? c.products : searchProducts(_query, c.products, catalog: c);
    if (_categoryId != null) list = list.where((p) => p.categoryId == _categoryId);
    final soon = DateTime.now().add(const Duration(days: 30));
    list = switch (_filter) {
      ProductFilter.all => list,
      ProductFilter.low => list.where((p) => p.isActive && p.isLowStock),
      ProductFilter.expiry => list.where((p) => p.nearestExpiry != null && p.nearestExpiry!.isBefore(soon)),
      ProductFilter.inactive => list.where((p) => !p.isActive),
    };
    return list.toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(catalogProvider);
    final canAdd = ref.watch(sessionProvider).value?.can(Perm.prices) ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Products & prices', 'सामान और रेट')),
        actions: [
          IconButton(
            tooltip: context.tr('Bulk photos', 'एक साथ फ़ोटो'),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: () => context.push('/owner/bulk-photos'),
          ),
          IconButton(
            tooltip: context.tr('Bulk price update', 'एक साथ रेट बदलें'),
            icon: const Icon(Icons.percent_rounded),
            onPressed: () => context.push('/owner/bulk-price'),
          ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: null, // several tabs have one; no shared hero animation
              onPressed: () => context.push('/owner/product/new'),
              icon: const Icon(Icons.add),
              label: Text(context.tr('Add', 'जोड़ें')),
            )
          : null,
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(catalogProvider)),
        data: (catalog) {
          final items = _visible(catalog);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 180), () => setState(() => _query = v));
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: context.tr('Search name, Hindi name or barcode', 'नाम, हिंदी नाम या बारकोड खोजें'),
                  ),
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final f in ProductFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(switch (f) {
                            ProductFilter.all => context.tr('All', 'सभी'),
                            ProductFilter.low => context.tr('Low stock', 'कम स्टॉक'),
                            ProductFilter.expiry => context.tr('Expiring', 'एक्सपायरी'),
                            ProductFilter.inactive => context.tr('Hidden', 'छुपे हुए'),
                          }),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CategoryFilter(
                        catalog: catalog,
                        value: _categoryId,
                        onChanged: (id) => setState(() => _categoryId = id),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('${items.length} items', '${items.length} सामान'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? MessageView(
                        icon: Icons.inventory_2_outlined,
                        title: context.tr('No products found', 'कोई सामान नहीं मिला'),
                      )
                    : RefreshIndicator(
                        onRefresh: () => ref.read(catalogProvider.notifier).refresh(),
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: items.length,
                          itemExtent: 84 * (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 1.8),
                          itemBuilder: (_, i) => _ProductRow(product: items[i], catalog: catalog),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.catalog, required this.value, required this.onChanged});
  final Catalog catalog;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = catalog.category(value);
    return PopupMenuButton<String>(
      tooltip: context.tr('Filter by category', 'कैटेगरी चुनें'),
      onSelected: (id) => onChanged(id.isEmpty ? null : id),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text(context.tr('All categories', 'सभी कैटेगरी'))),
        for (final c in catalog.categories)
          PopupMenuItem(value: c.id, child: Text('${c.icon ?? ''} ${context.pick(c.name, c.nameHi)}')),
      ],
      child: Chip(
        avatar: const Icon(Icons.filter_list_rounded, size: 18),
        label: Text(current == null ? context.tr('Category', 'कैटेगरी') : context.pick(current.name, current.nameHi)),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.catalog});
  final Product product;
  final Catalog catalog;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final variants = product.variants;
    final prices = variants
        .take(3)
        .map((v) => '${v.label} ${formatMoney(v.price)}${perUnitSuffix(v.unit, loose: product.isLoose)}')
        .join('  ·  ');
    final stock = variants
        .where((v) => v.trackStock)
        .map((v) => formatQty(v.stock, product.isLoose ? v.unit : SaleUnit.pc))
        .join(' / ');
    return InkWell(
      onTap: () => context.push('/owner/product/${product.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: product.isActive ? 1 : 0.4,
                child: ProductImage(
                  product: product,
                  size: 60,
                  fallbackEmoji: catalog.category(product.categoryId)?.icon,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          context.pick(product.name, product.nameHi),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.titleSmall,
                        ),
                      ),
                      if (!product.isActive) ...[
                        const SizedBox(width: 6),
                        Pill(context.tr('Hidden', 'छुपा'), color: t.colorScheme.outline),
                      ],
                      if (product.isActive && product.isLowStock) ...[
                        const SizedBox(width: 6),
                        Pill(context.tr('Low', 'कम'), color: Brand.saffronDeep),
                      ],
                    ],
                  ),
                  Text(prices, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
                  if (stock.isNotEmpty)
                    Text(
                      context.tr('Stock: $stock', 'स्टॉक: $stock'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
