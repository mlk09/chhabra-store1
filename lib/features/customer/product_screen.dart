import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';
import '../../data/models/product.dart';

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  String? _variantId;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).value;
    final product = catalog?.product(widget.productId);
    if (catalog == null) return const Scaffold(body: LoadingView());
    if (product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: MessageView(
          icon: Icons.inventory_2_outlined,
          title: context.tr('This item is no longer available', 'यह सामान अब उपलब्ध नहीं है'),
          actionLabel: context.tr('Back to shop', 'दुकान पर वापस'),
          onAction: () => context.go('/shop'),
        ),
      );
    }
    final t = Theme.of(context);
    final variants = product.activeVariants;
    final selected = variants.where((v) => v.id == _variantId).firstOrNull ?? product.defaultVariant;
    final category = catalog.category(product.categoryId);
    final wide = MediaQuery.sizeOf(context).width >= 760;

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 1,
        child: ProductImage(product: product, thumb: false, fallbackEmoji: category?.icon),
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (product.brand != null)
          Text(
            product.brand!.toUpperCase(),
            style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary, letterSpacing: 0.8),
          ),
        const SizedBox(height: 4),
        Text(context.pick(product.name, product.nameHi), style: t.textTheme.headlineSmall),
        if (product.nameHi != null && !context.isHindi)
          Text(product.nameHi!, style: t.textTheme.titleMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        if (selected != null) PriceTag(variant: selected, loose: product.isLoose, large: true),
        if (selected != null && selected.percentOffMrp > 0) ...[
          const SizedBox(height: 4),
          Text(
            context.tr(
              'You save ${formatMoney(selected.mrp - selected.price)} on MRP',
              'MRP पर ${formatMoney(selected.mrp - selected.price)} की बचत',
            ),
            style: t.textTheme.bodyMedium?.copyWith(color: Brand.saffronDeep, fontWeight: FontWeight.w700),
          ),
        ],
        Text(context.tr('MRP incl. of all taxes', 'MRP सभी करों सहित'), style: t.textTheme.bodySmall),
        const SizedBox(height: 18),
        if (variants.length > 1) ...[
          Text(context.tr('Choose size', 'साइज़ चुनें'), style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final v in variants)
                _SizeChip(variant: v, selected: v.id == selected?.id, onTap: () => setState(() => _variantId = v.id)),
            ],
          ),
          const SizedBox(height: 18),
        ],
        if (selected != null) _StockLine(variant: selected),
        if (product.isLoose) ...[
          const SizedBox(height: 10),
          Text(
            context.tr(
              'Sold loose by weight — buy as little as 250 g.',
              'खुला सामान वज़न से — 250 ग्राम भी ले सकते हैं।',
            ),
            style: t.textTheme.bodyMedium,
          ),
        ],
        if (product.description != null) ...[
          const SizedBox(height: 18),
          Text(product.description!, style: t.textTheme.bodyLarge),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(category == null ? '' : context.pick(category.name, category.nameHi))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: image),
                const SizedBox(width: 24),
                Expanded(child: details),
              ],
            )
          else ...[
            Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: image),
            ),
            const SizedBox(height: 18),
            details,
          ],
        ],
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  const _SizeChip({required this.variant, required this.selected, required this.onTap});
  final Variant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? t.colorScheme.primary.withValues(alpha: 0.14) : t.colorScheme.surfaceContainer,
          border: Border.all(
            color: selected ? t.colorScheme.primary : t.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(variant.label, style: t.textTheme.titleSmall),
            Text(formatMoney(variant.price), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (!variant.inStock)
              Text(
                context.tr('Out of stock', 'स्टॉक में नहीं'),
                style: TextStyle(color: t.colorScheme.error, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}

class _StockLine extends StatelessWidget {
  const _StockLine({required this.variant});
  final Variant variant;

  @override
  Widget build(BuildContext context) {
    final ok = variant.inStock;
    final color = ok ? Brand.green : Brand.red;
    return Row(
      children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color, size: 20),
        const SizedBox(width: 6),
        Text(
          ok ? context.tr('In stock', 'स्टॉक में है') : context.tr('Out of stock', 'स्टॉक में नहीं'),
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
