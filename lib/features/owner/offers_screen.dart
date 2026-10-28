import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/order_state.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models/catalog.dart';
import '../../data/models/order.dart';
import '../../data/models/product.dart';
import 'product_picker.dart';

String offerKindText(BuildContext context, OfferKind k) => switch (k) {
  OfferKind.productPercent => context.tr('% off one product', 'एक सामान पर % छूट'),
  OfferKind.productFlat => context.tr('₹ off one product (per piece/kg)', 'एक सामान पर ₹ छूट (हर पीस/किलो)'),
  OfferKind.categoryPercent => context.tr('% off a whole category', 'पूरी कैटेगरी पर % छूट'),
  OfferKind.bxgy => context.tr('Buy X Get Y free', 'X लो Y फ़्री'),
  OfferKind.cartFlat => context.tr('₹ off on bill above ₹X', '₹X से ऊपर बिल पर ₹ छूट'),
  OfferKind.cartPercent => context.tr('% off on bill above ₹X', '₹X से ऊपर बिल पर % छूट'),
  OfferKind.freeDelivery => context.tr('Free delivery above ₹X', '₹X से ऊपर फ़्री डिलीवरी'),
};

class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Offers & coupons', 'ऑफ़र और कूपन')),
          bottom: TabBar(
            tabs: [
              Tab(text: context.tr('Offers', 'ऑफ़र')),
              Tab(text: context.tr('Coupon codes', 'कूपन कोड')),
            ],
          ),
        ),
        body: const TabBarView(children: [_OffersTab(), _CouponsTab()]),
      ),
    );
  }
}

class _OffersTab extends ConsumerWidget {
  const _OffersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider).value;
    if (catalog == null) return const LoadingView();
    final now = DateTime.now();
    final offers = [...catalog.offers]..sort((a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _editOffer(context, ref, catalog, null),
        icon: const Icon(Icons.add),
        label: Text(context.tr('New offer', 'नया ऑफ़र')),
      ),
      body: offers.isEmpty
          ? MessageView(
              icon: Icons.local_offer_outlined,
              title: context.tr('No offers yet', 'अभी कोई ऑफ़र नहीं'),
              message: context.tr(
                'Examples: "Oil 5% off", "Buy 2 Get 1 Parle-G", "₹50 off above ₹500".',
                'जैसे: "तेल पर 5% छूट", "पारले-जी 2 लो 1 फ़्री", "₹500 से ऊपर ₹50 छूट"।',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Text(
                  context.tr(
                    'Each item gets its single best offer. One cart offer applies on top, then a coupon.',
                    'हर सामान पर उसका सबसे अच्छा एक ऑफ़र लगता है। ऊपर से एक बिल ऑफ़र, फिर कूपन।',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final o in offers)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(context.pick(o.title, o.titleHi)),
                      subtitle: Text(_describe(context, o, catalog)),
                      leading: Icon(
                        o.liveAt(now) ? Icons.local_offer_rounded : Icons.local_offer_outlined,
                        color: o.liveAt(now) ? Brand.green : Theme.of(context).colorScheme.outline,
                      ),
                      trailing: Switch(
                        value: o.isActive,
                        onChanged: (v) => _save(context, ref, Offer.fromJson({...o.toJson(), 'is_active': v})),
                      ),
                      onTap: () => _editOffer(context, ref, catalog, o),
                    ),
                  ),
              ],
            ),
    );
  }

  String _describe(BuildContext context, Offer o, Catalog c) {
    final target = o.productId != null
        ? c.product(o.productId!)?.name
        : o.categoryId != null
        ? c.category(o.categoryId)?.name
        : null;
    final parts = <String>[
      offerKindText(context, o.kind),
      ?target,
      if (o.minOrder > 0) context.tr('min ${formatMoney(o.minOrder)}', 'कम से कम ${formatMoney(o.minOrder)}'),
      if (o.endsAt != null)
        context.tr('till ${DateFormat('d MMM').format(o.endsAt!)}', '${DateFormat('d MMM').format(o.endsAt!)} तक'),
    ];
    return parts.join(' · ');
  }

  static Future<void> _save(BuildContext context, WidgetRef ref, Offer o) async {
    try {
      final saved = await ref.read(backendProvider).saveOffer(o);
      await ref.read(catalogProvider.notifier).applyOffer(saved);
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  static Future<void> _editOffer(BuildContext context, WidgetRef ref, Catalog catalog, Offer? existing) async {
    final result = await Navigator.of(context).push<_OfferResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _OfferEditor(catalog: catalog, existing: existing),
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      if (result.delete) {
        await ref.read(backendProvider).deleteOffer(existing!.id);
        await ref.read(catalogProvider.notifier).removeOffer(existing.id);
      } else {
        await _save(context, ref, result.offer!);
      }
      if (context.mounted) showSnack(context, context.tr('Saved ✓', 'सेव हो गया ✓'));
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }
}

class _OfferResult {
  const _OfferResult(this.offer) : delete = false;
  const _OfferResult.delete() : offer = null, delete = true;
  final Offer? offer;
  final bool delete;
}

class _OfferEditor extends StatefulWidget {
  const _OfferEditor({required this.catalog, this.existing});
  final Catalog catalog;
  final Offer? existing;
  @override
  State<_OfferEditor> createState() => _OfferEditorState();
}

class _OfferEditorState extends State<_OfferEditor> {
  final _form = GlobalKey<FormState>();
  late OfferKind _kind = widget.existing?.kind ?? OfferKind.productPercent;
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _titleHi = TextEditingController(text: widget.existing?.titleHi);
  late final _percent = TextEditingController(text: widget.existing?.percent?.toString() ?? '');
  late final _amount = TextEditingController(
    text: widget.existing?.amount == null ? '' : rupeesText(widget.existing!.amount!),
  );
  late final _min = TextEditingController(
    text: (widget.existing?.minOrder ?? 0) == 0 ? '' : rupeesText(widget.existing!.minOrder),
  );
  late final _max = TextEditingController(
    text: widget.existing?.maxDiscount == null ? '' : rupeesText(widget.existing!.maxDiscount!),
  );
  late final _buy = TextEditingController(text: '${widget.existing?.buyQty ?? 2}');
  late final _get = TextEditingController(text: '${widget.existing?.getQty ?? 1}');
  late Product? _product = widget.existing?.productId == null
      ? null
      : widget.catalog.product(widget.existing!.productId!);
  late String? _categoryId = widget.existing?.categoryId;
  late DateTime? _ends = widget.existing?.endsAt;
  late bool _active = widget.existing?.isActive ?? true;

  @override
  void dispose() {
    for (final c in [_title, _titleHi, _percent, _amount, _min, _max, _buy, _get]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v?.trim().isEmpty ?? true) ? context.tr('Required', 'ज़रूरी') : null;

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_kind.forProduct && _product == null) {
      showSnack(context, context.tr('Choose the product', 'सामान चुनें'), error: true);
      return;
    }
    final e = widget.existing;
    Navigator.pop(
      context,
      _OfferResult(
        Offer(
          id: e?.id ?? const Uuid().v4(),
          title: _title.text.trim(),
          titleHi: _titleHi.text.trim().isEmpty ? null : _titleHi.text.trim(),
          kind: _kind,
          productId: _kind.forProduct ? _product!.id : null,
          categoryId: _kind == OfferKind.categoryPercent ? _categoryId : null,
          percent: _kind.usesPercent ? double.parse(_percent.text.trim()) : null,
          amount: _kind.usesAmount ? parseRupees(_amount.text) : null,
          minOrder: _kind.forCart ? (parseRupees(_min.text) ?? 0) : 0,
          maxDiscount: _kind == OfferKind.cartPercent ? parseRupees(_max.text) : null,
          buyQty: _kind == OfferKind.bxgy ? int.parse(_buy.text) : null,
          getQty: _kind == OfferKind.bxgy ? int.parse(_get.text) : null,
          startsAt: e?.startsAt,
          endsAt: _ends,
          isActive: _active,
          createdAt: e?.createdAt ?? DateTime.now(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? context.tr('New offer', 'नया ऑफ़र') : context.tr('Edit offer', 'ऑफ़र बदलें'),
        ),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: context.tr('Delete', 'हटाएँ'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.pop(context, const _OfferResult.delete()),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: _save, child: Text(context.tr('Save offer', 'ऑफ़र सेव करें'))),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<OfferKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('Type of offer', 'ऑफ़र का प्रकार')),
              items: [
                for (final k in OfferKind.values)
                  DropdownMenuItem(
                    value: k,
                    child: Text(offerKindText(context, k), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (k) => setState(() => _kind = k ?? _kind),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(
                labelText: context.tr('Title customers see *', 'ग्राहकों को दिखने वाला नाम *'),
                hintText: context.tr('e.g. Diwali: ₹50 off above ₹500', 'जैसे: दिवाली: ₹500 से ऊपर ₹50 छूट'),
              ),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleHi,
              decoration: InputDecoration(labelText: context.tr('Title in Hindi', 'हिंदी में नाम')),
            ),
            const SizedBox(height: 12),
            if (_kind.forProduct)
              OutlinedButton.icon(
                icon: const Icon(Icons.search),
                label: Text(
                  _product == null ? context.tr('Choose product *', 'सामान चुनें *') : _product!.name,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () async {
                  final p = await pickProduct(context, widget.catalog);
                  if (p != null) setState(() => _product = p);
                },
              ),
            if (_kind == OfferKind.categoryPercent)
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('Category *', 'कैटेगरी *')),
                items: [
                  for (final c in widget.catalog.categories)
                    DropdownMenuItem(value: c.id, child: Text('${c.icon ?? ''} ${context.pick(c.name, c.nameHi)}')),
                ],
                validator: (v) => v == null ? context.tr('Required', 'ज़रूरी') : null,
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            const SizedBox(height: 12),
            if (_kind.usesPercent)
              TextFormField(
                controller: _percent,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(labelText: context.tr('Discount % *', 'छूट % *'), suffixText: '%'),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return n != null && n > 0 && n <= 90 ? null : context.tr('1 to 90', '1 से 90');
                },
              ),
            if (_kind.usesAmount)
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(
                  labelText: _kind == OfferKind.productFlat
                      ? context.tr('₹ off per piece / kg *', 'हर पीस / किलो पर ₹ छूट *')
                      : context.tr('₹ off on the bill *', 'बिल पर ₹ छूट *'),
                  prefixText: '₹ ',
                ),
                validator: (v) => (parseRupees(v ?? '') ?? 0) > 0 ? null : context.tr('Enter an amount', 'रकम लिखें'),
              ),
            if (_kind == OfferKind.bxgy)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _buy,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('Buy', 'ख़रीदें')),
                      validator: (v) => (int.tryParse(v ?? '') ?? 0).between1and20 ? null : '1–20',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _get,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: context.tr('Get free', 'फ़्री पाएँ')),
                      validator: (v) => (int.tryParse(v ?? '') ?? 0).between1and20 ? null : '1–20',
                    ),
                  ),
                ],
              ),
            if (_kind.forCart) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _min,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(labelText: context.tr('Minimum bill', 'कम से कम बिल'), prefixText: '₹ '),
              ),
            ],
            if (_kind == OfferKind.cartPercent) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _max,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(
                  labelText: context.tr('Maximum discount (optional)', 'अधिकतम छूट (वैकल्पिक)'),
                  prefixText: '₹ ',
                ),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _ends == null
                    ? context.tr('No end date', 'कोई अंतिम तारीख़ नहीं')
                    : context.tr(
                        'Ends ${DateFormat('d MMM y').format(_ends!)}',
                        '${DateFormat('d MMM y').format(_ends!)} को ख़त्म',
                      ),
              ),
              trailing: _ends == null
                  ? null
                  : IconButton(
                      tooltip: context.tr('Clear', 'हटाएँ'),
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _ends = null),
                    ),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _ends ?? now.add(const Duration(days: 7)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _ends = DateTime(d.year, d.month, d.day, 23, 59));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Offer is on', 'ऑफ़र चालू है')),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
    );
  }
}

extension on int {
  bool get between1and20 => this >= 1 && this <= 20;
}

class _CouponsTab extends ConsumerWidget {
  const _CouponsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponsProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text(context.tr('New coupon', 'नया कूपन')),
      ),
      body: coupons.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(couponsProvider)),
        data: (list) => list.isEmpty
            ? MessageView(
                icon: Icons.confirmation_number_outlined,
                title: context.tr('No coupons yet', 'अभी कोई कूपन नहीं'),
                message: context.tr(
                  'Make codes like WELCOME50 for new customers.',
                  'नए ग्राहकों के लिए WELCOME50 जैसे कोड बनाएँ।',
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  for (final c in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(c.code, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
                        subtitle: Text(
                          [
                            c.title ?? '',
                            context.tr(
                              'used ${c.usedCount}${c.usageLimit == null ? '' : '/${c.usageLimit}'}',
                              '${c.usedCount}${c.usageLimit == null ? '' : '/${c.usageLimit}'} बार इस्तेमाल',
                            ),
                            c.isPublic
                                ? context.tr('shown to customers', 'ग्राहकों को दिखता है')
                                : context.tr('secret code', 'गुप्त कोड'),
                          ].where((s) => s.isNotEmpty).join(' · '),
                        ),
                        trailing: Switch(
                          value: c.isActive,
                          onChanged: (v) => _saveCoupon(context, ref, Coupon.fromJson({...c.toJson(), 'is_active': v})),
                        ),
                        onTap: () => _edit(context, ref, c),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  static Future<void> _saveCoupon(BuildContext context, WidgetRef ref, Coupon c) async {
    try {
      await ref.read(backendProvider).saveCoupon(c);
      ref.invalidate(couponsProvider);
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, Coupon? existing) async {
    final result = await Navigator.of(context)
        .push<Object>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _CouponEditor(existing: existing)));
    if (result == null || !context.mounted) return;
    try {
      if (result == 'delete') {
        await ref.read(backendProvider).deleteCoupon(existing!.id);
      } else {
        await ref.read(backendProvider).saveCoupon(result as Coupon);
      }
      ref.invalidate(couponsProvider);
      if (context.mounted) showSnack(context, context.tr('Saved ✓', 'सेव हो गया ✓'));
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(context, e), error: true);
    }
  }
}

class _CouponEditor extends StatefulWidget {
  const _CouponEditor({this.existing});
  final Coupon? existing;
  @override
  State<_CouponEditor> createState() => _CouponEditorState();
}

class _CouponEditorState extends State<_CouponEditor> {
  final _form = GlobalKey<FormState>();
  late CouponKind _kind = widget.existing?.kind ?? CouponKind.flat;
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _value = TextEditingController(
    text: widget.existing == null
        ? ''
        : widget.existing!.kind == CouponKind.flat
        ? rupeesText(widget.existing!.value.toInt())
        : '${widget.existing!.value}',
  );
  late final _max = TextEditingController(
    text: widget.existing?.maxDiscount == null ? '' : rupeesText(widget.existing!.maxDiscount!),
  );
  late final _min = TextEditingController(
    text: (widget.existing?.minOrder ?? 0) == 0 ? '' : rupeesText(widget.existing!.minOrder),
  );
  late final _limit = TextEditingController(text: widget.existing?.usageLimit?.toString() ?? '');
  late final _perUser = TextEditingController(text: '${widget.existing?.perUserLimit ?? 1}');
  late DateTime? _ends = widget.existing?.endsAt;
  late bool _public = widget.existing?.isPublic ?? true;
  late bool _active = widget.existing?.isActive ?? true;

  @override
  void dispose() {
    for (final c in [_code, _title, _value, _max, _min, _limit, _perUser]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? context.tr('New coupon', 'नया कूपन') : context.tr('Edit coupon', 'कूपन बदलें'),
        ),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: context.tr('Delete', 'हटाएँ'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.pop(context, 'delete'),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              final e = widget.existing;
              Navigator.pop(
                context,
                Coupon(
                  id: e?.id ?? const Uuid().v4(),
                  code: _code.text.trim().toUpperCase(),
                  title: _title.text.trim().isEmpty ? null : _title.text.trim(),
                  kind: _kind,
                  value: switch (_kind) {
                    CouponKind.flat => parseRupees(_value.text)!,
                    CouponKind.percent => double.parse(_value.text),
                    CouponKind.freeDelivery => 0,
                  },
                  maxDiscount: _kind == CouponKind.percent ? parseRupees(_max.text) : null,
                  minOrder: parseRupees(_min.text) ?? 0,
                  usageLimit: int.tryParse(_limit.text),
                  perUserLimit: int.tryParse(_perUser.text) ?? 1,
                  usedCount: e?.usedCount ?? 0,
                  startsAt: e?.startsAt,
                  endsAt: _ends,
                  isPublic: _public,
                  isActive: _active,
                ),
              );
            },
            child: Text(context.tr('Save coupon', 'कूपन सेव करें')),
          ),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(20),
              ],
              decoration: InputDecoration(
                labelText: context.tr('Code * (letters & numbers)', 'कोड * (अक्षर और अंक)'),
                hintText: 'WELCOME50',
              ),
              validator: (v) => RegExp(r'^[A-Za-z0-9]{3,20}$').hasMatch(v ?? '')
                  ? null
                  : context.tr('3–20 letters/numbers', '3–20 अक्षर/अंक'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(
                labelText: context.tr('Short description', 'छोटा विवरण'),
                hintText: context.tr('₹50 off above ₹300', '₹300 से ऊपर ₹50 छूट'),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<CouponKind>(
              segments: [
                ButtonSegment(value: CouponKind.flat, label: Text(context.tr('₹ off', '₹ छूट'))),
                ButtonSegment(value: CouponKind.percent, label: Text(context.tr('% off', '% छूट'))),
                ButtonSegment(
                  value: CouponKind.freeDelivery,
                  label: Text(context.tr('Free delivery', 'फ़्री डिलीवरी')),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            if (_kind != CouponKind.freeDelivery)
              TextFormField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(
                  labelText: _kind == CouponKind.flat
                      ? context.tr('₹ off *', '₹ छूट *')
                      : context.tr('% off *', '% छूट *'),
                  prefixText: _kind == CouponKind.flat ? '₹ ' : null,
                  suffixText: _kind == CouponKind.percent ? '%' : null,
                ),
                validator: (v) {
                  if (_kind == CouponKind.flat) {
                    return (parseRupees(v ?? '') ?? 0) > 0 ? null : context.tr('Enter an amount', 'रकम लिखें');
                  }
                  final n = double.tryParse(v ?? '');
                  return n != null && n > 0 && n <= 90 ? null : context.tr('1 to 90', '1 से 90');
                },
              ),
            if (_kind == CouponKind.percent) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _max,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: digits,
                decoration: InputDecoration(
                  labelText: context.tr('Maximum discount (optional)', 'अधिकतम छूट (वैकल्पिक)'),
                  prefixText: '₹ ',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: digits,
              decoration: InputDecoration(
                labelText: context.tr('Minimum bill (optional)', 'कम से कम बिल (वैकल्पिक)'),
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.tr('Total uses (optional)', 'कुल बार (वैकल्पिक)')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _perUser,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.tr('Per customer', 'हर ग्राहक')),
                    validator: (v) => ((int.tryParse(v ?? '') ?? 0) >= 1) ? null : '≥ 1',
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _ends == null
                    ? context.tr('No end date', 'कोई अंतिम तारीख़ नहीं')
                    : context.tr(
                        'Ends ${DateFormat('d MMM y').format(_ends!)}',
                        '${DateFormat('d MMM y').format(_ends!)} को ख़त्म',
                      ),
              ),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _ends ?? now.add(const Duration(days: 30)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (d != null) setState(() => _ends = DateTime(d.year, d.month, d.day, 23, 59));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Show in the customer app', 'ग्राहक ऐप में दिखाएँ')),
              subtitle: Text(context.tr('Off = secret code you share yourself', 'बंद = गुप्त कोड, आप ख़ुद बताएँगे')),
              value: _public,
              onChanged: (v) => setState(() => _public = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('Coupon is on', 'कूपन चालू है')),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
    );
  }
}
