import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/widgets/common.dart';
import '../../data/models/member.dart';

/// "Raise all oil prices by 5%" in one go — same maths as the server.
class BulkPriceScreen extends ConsumerStatefulWidget {
  const BulkPriceScreen({super.key});
  @override
  ConsumerState<BulkPriceScreen> createState() => _BulkPriceScreenState();
}

class _BulkPriceScreenState extends ConsumerState<BulkPriceScreen> {
  final _percent = TextEditingController(text: '5');
  String? _categoryId;
  String _applyTo = 'both';
  String _rounding = 'rupee';
  bool _busy = false;

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  double? get _pct {
    final v = double.tryParse(_percent.text.trim());
    if (v == null || v == 0 || v < -50 || v > 100) return null;
    return v;
  }

  Future<void> _apply(int count) async {
    final pct = _pct!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Change $count prices?', '$count रेट बदलें?')),
        content: Text(
          ctx.tr(
            '${pct > 0 ? 'Increase' : 'Decrease'} by ${pct.abs()}%. You can change any single price later.',
            '${pct.abs()}% ${pct > 0 ? 'बढ़ाएँ' : 'घटाएँ'}। बाद में कोई भी रेट अलग से बदल सकते हैं।',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel', 'रद्द करें'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Yes, change', 'हाँ, बदलें'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final n = await ref
          .read(catalogProvider.notifier)
          .bulkUpdatePrices(percent: pct, categoryId: _categoryId, applyTo: _applyTo, rounding: _rounding);
      if (!mounted) return;
      showSnack(context, context.tr('$n prices updated ✓', '$n रेट बदल गए ✓'));
      context.pop();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).value;
    final canPrice = ref.watch(sessionProvider).value?.can(Perm.prices) ?? false;
    final t = Theme.of(context);
    if (catalog == null) return const Scaffold(body: LoadingView());
    if (!canPrice) {
      return Scaffold(
        appBar: AppBar(),
        body: MessageView(
          icon: Icons.lock_outline,
          title: context.tr('Only the owner can change prices', 'रेट सिर्फ़ मालिक बदल सकता है'),
        ),
      );
    }
    final products = catalog.products.where((p) => _categoryId == null || p.categoryId == _categoryId).toList();
    final variants = [
      for (final p in products)
        for (final v in p.variants) (p, v),
    ];
    final pct = _pct;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Bulk price update', 'एक साथ रेट बदलें'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: pct == null || variants.isEmpty || _busy ? null : () => _apply(variants.length),
            child: Text(context.tr('Update ${variants.length} prices', '${variants.length} रेट बदलें')),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String?>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('Which products?', 'कौन से सामान?')),
            items: [
              DropdownMenuItem(value: null, child: Text(context.tr('All products', 'सभी सामान'))),
              for (final c in catalog.categories)
                DropdownMenuItem(value: c.id, child: Text('${c.icon ?? ''} ${context.pick(c.name, c.nameHi)}')),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _percent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr('Change by (%)', 'कितने % बदलें'),
              suffixText: '%',
              helperText: context.tr('Use minus for a price cut, e.g. -5', 'रेट घटाने के लिए माइनस लिखें, जैसे -5'),
              errorText: pct == null ? context.tr('Between -50 and 100, not 0', '-50 से 100 के बीच, 0 नहीं') : null,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final q in ['2', '5', '10', '-5'])
                ActionChip(
                  label: Text('${q.startsWith('-') ? '' : '+'}$q%'),
                  onPressed: () => setState(() => _percent.text = q),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(context.tr('Apply to', 'किस पर लागू'), style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'both', label: Text(context.tr('MRP + price', 'MRP + रेट'))),
              ButtonSegment(value: 'price', label: Text(context.tr('Price only', 'सिर्फ़ रेट'))),
              ButtonSegment(value: 'mrp', label: Text(context.tr('MRP only', 'सिर्फ़ MRP'))),
            ],
            selected: {_applyTo},
            onSelectionChanged: (s) => setState(() => _applyTo = s.first),
          ),
          const SizedBox(height: 16),
          Text(context.tr('Round to', 'राउंड करें'), style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'rupee', label: Text(context.tr('₹1', '₹1'))),
              const ButtonSegment(value: 'fifty', label: Text('50 p')),
              ButtonSegment(value: 'none', label: Text(context.tr('Exact', 'सटीक'))),
            ],
            selected: {_rounding},
            onSelectionChanged: (s) => setState(() => _rounding = s.first),
          ),
          const SizedBox(height: 24),
          Text(context.tr('Preview', 'झलक'), style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (pct != null)
            for (final (p, v) in variants.take(8))
              Builder(
                builder: (context) {
                  final mrp = _applyTo == 'price' ? v.mrp : applyPercent(v.mrp, pct, _rounding);
                  var price = _applyTo == 'mrp' ? v.price : applyPercent(v.price, pct, _rounding);
                  if (price > mrp) price = mrp;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${context.pick(p.name, p.nameHi)} · ${v.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      '${formatMoney(v.price)} → ${formatMoney(price)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  );
                },
              ),
          if (variants.length > 8)
            Text(
              context.tr('…and ${variants.length - 8} more', '…और ${variants.length - 8}'),
              style: t.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
