import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/catalog.dart';
import '../../data/models/product.dart';
import '../../data/models/shop.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../money.dart';
import '../theme.dart';
import '../units.dart';
import 'cart_widgets.dart';
import 'common.dart';

/// Product photo (cached, downsized in memory) or a tidy emoji placeholder.
class ProductImage extends ConsumerWidget {
  const ProductImage({super.key, required this.product, this.size, this.thumb = true, this.fallbackEmoji});

  final Product product;
  final double? size;
  final bool thumb;
  final String? fallbackEmoji;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(backendProvider);
    final path = thumb ? (product.thumbPath ?? product.imagePath) : (product.imagePath ?? product.thumbPath);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = size == null ? null : (size! * dpr).round();
    final placeholder = _Placeholder(emoji: product.emoji ?? fallbackEmoji, name: product.name, size: size);

    Widget child;
    final bytes = backend.localImage(path);
    final url = backend.imageUrl(path);
    if (bytes != null) {
      child = Image.memory(bytes, fit: BoxFit.cover, cacheWidth: cachePx, gaplessPlayback: true);
    } else if (url != null) {
      child = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: cachePx,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    } else {
      child = placeholder;
    }
    return SizedBox(width: size, height: size, child: child);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.emoji, required this.name, this.size});
  final String? emoji;
  final String name;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, c) {
          final s = (c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : (size ?? 64)) * 0.5;
          return emoji != null
              ? Text(emoji!, style: TextStyle(fontSize: s, height: 1))
              : Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: TextStyle(fontSize: s, fontWeight: FontWeight.w700, color: scheme.primary, height: 1),
                );
        },
      ),
    );
  }
}

/// ₹44  ~~₹50~~  12% OFF   — MRP struck through when there is a discount.
class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.variant, this.loose = false, this.large = false, this.showBadge = true});
  final Variant variant;
  final bool loose;
  final bool large;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final off = variant.percentOffMrp;
    final suffix = perUnitSuffix(variant.unit, loose: loose);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          '${formatMoney(variant.price)}$suffix',
          style: (large ? t.textTheme.headlineSmall : t.textTheme.titleMedium)?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (off > 0)
          Text(
            formatMoney(variant.mrp),
            style: t.textTheme.bodyMedium?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: t.colorScheme.onSurfaceVariant,
            ),
          ),
        if (off > 0 && showBadge) Pill(context.tr('$off% OFF', '$off% छूट'), color: Brand.saffronDeep, filled: true),
      ],
    );
  }
}

/// Quick-commerce style product card used in grids.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, required this.catalog, this.onTap, this.showAdd = true});
  final Product product;
  final Catalog catalog;
  final VoidCallback? onTap;
  final bool showAdd;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final v = product.defaultVariant;
    final outOfStock = v == null || !v.inStock;
    final sizes = product.activeVariants.length;
    final offer = catalog.liveOffersFor(product, DateTime.now()).firstOrNull;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.15,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(product: product, fallbackEmoji: catalog.category(product.categoryId)?.icon),
                  if (v != null && v.percentOffMrp > 0)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Pill(
                        context.tr('${v.percentOffMrp}% OFF', '${v.percentOffMrp}% छूट'),
                        color: Brand.saffronDeep,
                        filled: true,
                      ),
                    ),
                  if (offer != null)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: Brand.greenDeep, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            context.pick(offer.title, offer.titleHi),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                  if (outOfStock)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: Text(
                        context.tr('Out of stock', 'स्टॉक में नहीं'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.pick(product.name, product.nameHi),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v == null
                        ? ''
                        : sizes > 1
                        ? context.tr('${v.label} · $sizes sizes', '${v.label} · $sizes साइज़')
                        : v.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  if (v != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${formatMoney(v.price)}${perUnitSuffix(v.unit, loose: product.isLoose)}',
                          style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (v.percentOffMrp > 0) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              formatMoney(v.mrp),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: t.textTheme.bodySmall?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: t.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  if (v != null && showAdd) ...[
                    const SizedBox(height: 8),
                    AddToCartButton(product: product, variant: v),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Height of the text part of a [ProductCard] (name ×2, size, price + padding),
/// measured from the real text styles so large system fonts never overflow.
double productCardTextHeight(BuildContext context) {
  final t = Theme.of(context).textTheme;
  final scaler = MediaQuery.textScalerOf(context);
  double line(TextStyle? s) => scaler.scale(s?.fontSize ?? 14) * (s?.height ?? 1.3);
  // + 8 gap + 38 ADD button
  return 2 * line(t.bodyLarge) + line(t.bodySmall) + line(t.titleMedium) + 8 + 18 + 4 + 46;
}

/// Grid layout for product cards that stays correct with large system fonts.
SliverGridDelegate productGridDelegate(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final columns = width >= 1100
      ? 6
      : width >= 840
      ? 5
      : width >= 600
      ? 4
      : 2;
  final tileWidth = (width - 16 * 2 - 12 * (columns - 1)) / columns;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    mainAxisExtent: tileWidth / 1.15 + productCardTextHeight(context),
  );
}

/// The shop's uploaded logo, or its monogram in the shop's colour.
class ShopLogo extends ConsumerWidget {
  const ShopLogo({super.key, required this.name, this.logoPath, this.brandColor, this.size = 40});

  ShopLogo.of(Shop shop, {Key? key, double size = 40})
    : this(key: key, name: shop.name, logoPath: shop.logoPath, brandColor: shop.brandColor, size: size);

  final String name;
  final String? logoPath;
  final String? brandColor;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = AppLogo(size: size, letter: name, color: parseHexColor(brandColor));
    if (logoPath == null) return fallback;
    final backend = ref.watch(backendProvider);
    final bytes = backend.localImage(logoPath);
    final url = backend.imageUrl(logoPath);
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final Widget image = bytes != null
        ? Image.memory(bytes, fit: BoxFit.cover, cacheWidth: px)
        : url != null
        ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, memCacheWidth: px, errorWidget: (_, _, _) => fallback)
        : fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SizedBox(width: size, height: size, child: image),
    );
  }
}
