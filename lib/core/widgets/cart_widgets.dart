import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/product.dart';
import '../i18n.dart';
import '../money.dart';
import '../order_state.dart';
import '../units.dart';
import 'common.dart';

/// "ADD" button that turns into − qty + once the item is in the cart.
/// Loose items open a weight picker (250 g, 500 g, 1 kg…).
class AddToCartButton extends ConsumerWidget {
  const AddToCartButton({super.key, required this.product, required this.variant, this.large = false});

  final Product product;
  final Variant variant;
  final bool large;

  double get _step => product.isLoose ? 0.25 : 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final qty = ref.watch(cartProvider.select((c) => c[variant.id] ?? 0));
    final cart = ref.read(cartProvider.notifier);
    final height = large ? 52.0 : 38.0;
    final max = variant.trackStock ? variant.stock : 1000.0;

    if (!variant.inStock || !variant.isActive) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(minimumSize: Size(0, height), padding: EdgeInsets.zero),
          child: Text(context.tr('Out of stock', 'स्टॉक में नहीं'), maxLines: 1),
        ),
      );
    }

    if (qty == 0) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, height),
            padding: EdgeInsets.zero,
            foregroundColor: t.colorScheme.primary,
            side: BorderSide(color: t.colorScheme.primary, width: 1.5),
            backgroundColor: t.colorScheme.primary.withValues(alpha: 0.08),
          ),
          onPressed: () async {
            if (product.isLoose) {
              final picked = await pickLooseQty(context, product, variant);
              if (picked != null) cart.setQty(variant.id, picked);
            } else {
              cart.add(variant.id, 1);
            }
          },
          child: Text(context.tr('ADD', 'जोड़ें'), style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      );
    }

    return Container(
      height: height,
      decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _StepButton(
            icon: Icons.remove_rounded,
            tooltip: context.tr('Less', 'कम करें'),
            onTap: () => cart.setQty(variant.id, qty - _step < 0.0001 ? 0 : qty - _step),
          ),
          Expanded(
            child: InkWell(
              onTap: product.isLoose
                  ? () async {
                      final picked = await pickLooseQty(context, product, variant, current: qty);
                      if (picked != null) cart.setQty(variant.id, picked);
                    }
                  : null,
              child: Center(
                child: Text(
                  product.isLoose ? formatQty(qty, variant.unit) : formatQty(qty, SaleUnit.pc),
                  maxLines: 1,
                  style: TextStyle(
                    color: t.colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: large ? 18 : 15,
                  ),
                ),
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            tooltip: context.tr('More', 'ज़्यादा'),
            onTap: () {
              if (qty + _step > max + 0.0001) {
                showSnack(
                  context,
                  context.tr(
                    'Only ${formatQty(max, product.isLoose ? variant.unit : SaleUnit.pc)} in stock',
                    'स्टॉक में सिर्फ़ ${formatQty(max, product.isLoose ? variant.unit : SaleUnit.pc)} है',
                  ),
                );
                return;
              }
              cart.add(variant.id, _step);
            },
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 44,
        height: double.infinity,
        child: Icon(icon, color: Theme.of(context).colorScheme.onPrimary),
      ),
    ),
  );
}

/// Weight picker for loose items: 250 g / 500 g / 1 kg / 2 kg / 5 kg or typed grams.
Future<double?> pickLooseQty(BuildContext context, Product product, Variant variant, {double? current}) {
  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _LooseQtySheet(product: product, variant: variant, current: current),
  );
}

class _LooseQtySheet extends StatefulWidget {
  const _LooseQtySheet({required this.product, required this.variant, this.current});
  final Product product;
  final Variant variant;
  final double? current;

  @override
  State<_LooseQtySheet> createState() => _LooseQtySheetState();
}

class _LooseQtySheetState extends State<_LooseQtySheet> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.variant;
    final small = v.unit == SaleUnit.l ? 'ml' : 'g';
    final max = v.trackStock ? v.stock : 1000.0;
    final options = [0.25, 0.5, 1.0, 2.0, 5.0].where((q) => q <= max + 0.0001).toList();
    final typed = double.tryParse(_custom.text.trim());
    final typedQty = typed == null ? null : typed / 1000;
    final typedOk = typedQty != null && typedQty >= 0.05 && typedQty <= max;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.pick(widget.product.name, widget.product.nameHi), style: Theme.of(context).textTheme.titleLarge),
          Text(
            context.tr(
              '${formatMoney(v.price)} per ${v.unit == SaleUnit.l ? 'litre' : 'kg'} · choose quantity',
              '${formatMoney(v.price)} प्रति ${v.unit == SaleUnit.l ? 'लीटर' : 'किलो'} · मात्रा चुनें',
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final q in options)
                ChoiceChip(
                  label: Text('${formatQty(q, v.unit)} · ${formatMoney((v.price * q).round())}'),
                  selected: widget.current == q,
                  onSelected: (_) => Navigator.pop(context, q),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _custom,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.tr('Or type amount', 'या मात्रा लिखें'),
                    suffixText: small,
                    helperText: typedOk ? '≈ ${formatMoney((v.price * typedQty).round())}' : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: typedOk ? () => Navigator.pop(context, typedQty) : null,
                child: Text(context.tr('Add', 'जोड़ें')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom strip on shop screens: "3 items · ₹245   View cart ›".
class CartBar extends ConsumerWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartCountProvider);
    if (count == 0) return const SizedBox.shrink();
    final quote = ref.watch(quoteProvider).value;
    final t = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Material(
          color: t.colorScheme.primary,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/cart'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.shopping_basket_rounded, color: t.colorScheme.onPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      [
                        context.tr('$count items', '$count सामान'),
                        if (quote != null) formatMoney(quote.total),
                      ].join(' · '),
                      style: TextStyle(color: t.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Text(
                    context.tr('View cart', 'कार्ट देखें'),
                    style: TextStyle(color: t.colorScheme.onPrimary, fontWeight: FontWeight.w700),
                  ),
                  Icon(Icons.chevron_right_rounded, color: t.colorScheme.onPrimary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
