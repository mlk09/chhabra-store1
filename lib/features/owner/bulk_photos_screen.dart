import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/units.dart';
import '../../core/widgets/common.dart';
import '../../data/backend.dart';
import '../../data/models/catalog.dart';
import '../../data/models/member.dart';
import '../../data/models/product.dart';
import '../../data/models/product_guess.dart';
import '../../domain/search.dart';
import 'photo.dart';
import 'product_picker.dart';

const _maxPhotos = 30;

enum _Mode { attach, create, skip }

enum _Status { working, ready, saving, saved, failed }

/// One picked photo and what will happen to it.
class _Item {
  _Item(this.fileName);

  final String fileName;
  final key = UniqueKey();
  ProductPhoto? photo;
  _Status status = _Status.working;
  String? note;
  _Mode mode = _Mode.create;
  Product? attachTo;

  // "New product" fields
  final name = TextEditingController();
  final nameHi = TextEditingController();
  final size = TextEditingController();
  final mrp = TextEditingController();
  final price = TextEditingController();
  String? brand;
  String? categoryId;
  SaleUnit unit = SaleUnit.pc;
  double unitQty = 1;
  bool loose = false;
  List<String> synonyms = const [];

  void applyGuess(ProductGuess g) {
    name.text = g.name;
    nameHi.text = g.nameHi ?? '';
    size.text = g.label;
    if (g.mrp != null) {
      mrp.text = rupeesText(g.mrp!);
      price.text = rupeesText(g.mrp!);
    }
    brand = g.brand;
    categoryId = g.categoryId;
    unit = g.unit;
    unitQty = g.unitQty;
    loose = g.isLoose;
    synonyms = g.synonyms;
  }

  void dispose() {
    for (final c in [name, nameHi, size, mrp, price]) {
      c.dispose();
    }
  }
}

/// Add photos to many products at once — or create new products from photos.
///  1. File name match: "Tata Salt.jpg" → Tata Salt (great from a computer).
///  2. AI (real shop): reads name, Hindi name, size, MRP and category from the photo.
///  3. Anything left: pick the product yourself or type the details.
class BulkPhotosScreen extends ConsumerStatefulWidget {
  const BulkPhotosScreen({super.key});
  @override
  ConsumerState<BulkPhotosScreen> createState() => _BulkPhotosScreenState();
}

class _BulkPhotosScreenState extends ConsumerState<BulkPhotosScreen> {
  final _items = <_Item>[];
  bool _useAi = true;
  bool _busy = false;

  @override
  void dispose() {
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  bool get _isDemo => ref.read(sessionProvider).value?.isDemo ?? true;

  Future<void> _pick() async {
    List<XFile> files;
    try {
      files = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 90, limit: _maxPhotos);
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
      return;
    }
    if (files.isEmpty || !mounted) return;
    if (files.length > _maxPhotos) {
      showSnack(
        context,
        context.tr('Only the first $_maxPhotos photos are used.', 'सिर्फ़ पहली $_maxPhotos फ़ोटो ली गईं।'),
      );
      files = files.take(_maxPhotos).toList();
    }
    final added = [for (final f in files) _Item(f.name)];
    setState(() {
      _items.addAll(added);
      _busy = true;
    });
    for (var i = 0; i < files.length; i++) {
      if (!mounted) return;
      await _prepare(added[i], files[i]);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Compress → match by file name → otherwise ask the AI.
  Future<void> _prepare(_Item item, XFile file) async {
    final catalog = ref.read(catalogProvider).value!;
    final canPrice = ref.read(sessionProvider).value?.can(Perm.prices) ?? false;
    try {
      item.photo = await compute(compressProductPhoto, await file.readAsBytes());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        item.status = _Status.failed;
        item.mode = _Mode.skip;
        item.note = errorText(context, e);
      });
      return;
    }
    if (!mounted) return;

    final byName = findBestMatch(item.fileName, catalog.products, catalog: catalog);
    if (byName != null) {
      setState(() {
        item.mode = _Mode.attach;
        item.attachTo = byName;
        item.status = _Status.ready;
        item.note = context.tr('Matched by file name', 'फ़ाइल के नाम से मिला');
      });
      return;
    }

    if (_useAi && !_isDemo) {
      try {
        final guess = await ref
            .read(backendProvider)
            .identifyProduct(shopId: catalog.shop.id, jpeg: item.photo!.full, categories: catalog.categories);
        if (!mounted) return;
        final existing = findBestMatch(guess.name, catalog.products, catalog: catalog);
        setState(() {
          item.applyGuess(guess);
          if (existing != null) {
            item.mode = _Mode.attach;
            item.attachTo = existing;
            item.note = context.tr('AI: ${guess.name} — already in your list', 'AI: ${guess.name} — पहले से लिस्ट में');
          } else {
            item.mode = canPrice ? _Mode.create : _Mode.attach;
            item.note = context.tr('AI: new product — check the details', 'AI: नया सामान — जानकारी जाँच लें');
          }
          item.status = _Status.ready;
        });
        return;
      } catch (e) {
        if (!mounted) return;
        item.note = errorText(context, e);
      }
    }
    setState(() {
      item.mode = canPrice ? _Mode.create : _Mode.attach;
      item.status = _Status.ready;
      item.note ??= context.tr('Choose the product or type its name', 'सामान चुनें या नाम लिखें');
    });
  }

  String? _problem(_Item i) {
    switch (i.mode) {
      case _Mode.skip:
        return null;
      case _Mode.attach:
        return i.attachTo == null ? context.tr('Choose a product', 'सामान चुनें') : null;
      case _Mode.create:
        if (i.name.text.trim().isEmpty) return context.tr('Name needed', 'नाम चाहिए');
        if (i.size.text.trim().isEmpty) return context.tr('Size needed', 'साइज़ चाहिए');
        final p = parseRupees(i.price.text);
        if (p == null) return context.tr('Selling price needed', 'बिक्री रेट चाहिए');
        final m = parseRupees(i.mrp.text);
        if (m != null && p > m) return context.tr('Price is more than MRP', 'रेट MRP से ज़्यादा है');
        return null;
    }
  }

  Future<void> _saveAll() async {
    final todo = _items.where((i) => i.status == _Status.ready && i.mode != _Mode.skip).toList();
    final firstProblem = todo.map(_problem).whereType<String>().firstOrNull;
    if (firstProblem != null) {
      showSnack(
        context,
        context.tr('Fix the cards marked in red first.', 'पहले लाल निशान वाले कार्ड ठीक करें।'),
        error: true,
      );
      setState(() {});
      return;
    }
    final notifier = ref.read(catalogProvider.notifier);
    setState(() => _busy = true);
    var saved = 0;
    for (final item in todo) {
      setState(() => item.status = _Status.saving);
      try {
        if (item.mode == _Mode.attach) {
          final latest = ref.read(catalogProvider).value?.product(item.attachTo!.id) ?? item.attachTo!;
          await notifier.saveProduct(latest, photo: item.photo, stockChanged: const {});
        } else {
          await notifier.saveProduct(_newProduct(item), photo: item.photo);
        }
        saved++;
        if (mounted) setState(() => item.status = _Status.saved);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          item.status = _Status.ready;
          item.note = errorText(context, e);
        });
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      for (final i in _items.where((i) => i.status == _Status.saved || i.mode == _Mode.skip).toList()) {
        _items.remove(i);
        i.dispose();
      }
    });
    showSnack(context, context.tr('$saved saved ✓', '$saved सेव हुए ✓'));
  }

  Product _newProduct(_Item i) {
    final id = const Uuid().v4();
    final price = parseRupees(i.price.text)!;
    return Product(
      id: id,
      name: i.name.text.trim(),
      nameHi: i.nameHi.text.trim().isEmpty ? null : i.nameHi.text.trim(),
      brand: i.brand,
      categoryId: i.categoryId,
      isLoose: i.loose,
      synonyms: i.synonyms,
      variants: [
        Variant(
          id: const Uuid().v4(),
          productId: id,
          label: i.size.text.trim(),
          unit: i.unit,
          unitQty: i.loose ? 1 : i.unitQty,
          mrp: parseRupees(i.mrp.text) ?? price,
          price: price,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).value;
    final session = ref.watch(sessionProvider).value;
    if (catalog == null || session == null) return const Scaffold(body: LoadingView());
    final t = Theme.of(context);
    final canPrice = session.can(Perm.prices);
    final working = _items.where((i) => i.status == _Status.working).length;
    final toSave = _items.where((i) => i.status == _Status.ready && i.mode != _Mode.skip).length;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Bulk photos', 'एक साथ फ़ोटो'))),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _busy || toSave == 0 ? null : _saveAll,
                  icon: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    working > 0
                        ? context.tr('Reading photos… $working left', 'फ़ोटो पढ़ रहे हैं… $working बाकी')
                        : context.tr('Save $toSave', '$toSave सेव करें'),
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('Add many photos at once', 'एक साथ कई फ़ोटो जोड़ें'), style: t.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      '• Photo file named like the product ("Tata Salt.jpg") → matched automatically.\n'
                          '• Otherwise AI reads the pack: name, Hindi name, size, MRP, category.\n'
                          '• You check every card, then tap Save. Nothing is saved before that.',
                      '• फ़ाइल का नाम सामान जैसा ("Tata Salt.jpg") → अपने आप मिल जाएगा।\n'
                          '• नहीं तो AI पैकेट पढ़ेगा: नाम, हिंदी नाम, साइज़, MRP, कैटेगरी।\n'
                          '• हर कार्ड जाँचें, फिर Save दबाएँ। उससे पहले कुछ सेव नहीं होता।',
                    ),
                    style: t.textTheme.bodyMedium,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Read photos with AI', 'AI से फ़ोटो पढ़ें')),
                    subtitle: session.isDemo
                        ? Text(context.tr('Works in the real shop after setup', 'सेटअप के बाद असली दुकान में चलेगा'))
                        : null,
                    value: _useAi && !session.isDemo,
                    onChanged: session.isDemo || _busy ? null : (v) => setState(() => _useAi = v),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(context.tr('Choose photos (up to $_maxPhotos)', 'फ़ोटो चुनें ($_maxPhotos तक)')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final item in _items)
            _ItemCard(
              key: item.key,
              item: item,
              catalog: catalog,
              canCreate: canPrice,
              problem: item.status == _Status.ready ? _problem(item) : null,
              onChanged: () => setState(() {}),
              onPickProduct: () async {
                final p = await _pickProduct(context, catalog);
                if (p != null) {
                  setState(() {
                    item.attachTo = p;
                    item.mode = _Mode.attach;
                  });
                }
              },
            ),
        ],
      ),
    );
  }

  Future<Product?> _pickProduct(BuildContext context, Catalog catalog) => pickProduct(context, catalog);
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.item,
    required this.catalog,
    required this.canCreate,
    required this.problem,
    required this.onChanged,
    required this.onPickProduct,
  });

  final _Item item;
  final Catalog catalog;
  final bool canCreate;
  final String? problem;
  final VoidCallback onChanged;
  final VoidCallback onPickProduct;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = switch (item.status) {
      _Status.working => context.tr('Reading…', 'पढ़ रहे हैं…'),
      _Status.saving => context.tr('Saving…', 'सेव हो रहा है…'),
      _Status.saved => context.tr('Saved ✓', 'सेव ✓'),
      _Status.failed => context.tr('Could not use this photo', 'यह फ़ोटो काम की नहीं'),
      _Status.ready => item.note ?? '',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: problem == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: t.colorScheme.error, width: 2),
            ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: item.photo == null
                        ? ColoredBox(
                            color: t.colorScheme.surfaceContainerHigh,
                            child: const Center(
                              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          )
                        : Image.memory(item.photo!.thumb, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodySmall),
                      Text(status, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (problem != null)
                        Text(
                          problem!,
                          style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (item.status == _Status.ready) ...[
              const SizedBox(height: 10),
              SegmentedButton<_Mode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: _Mode.attach, label: Text(context.tr('Existing', 'पुराना'))),
                  if (canCreate) ButtonSegment(value: _Mode.create, label: Text(context.tr('New', 'नया'))),
                  ButtonSegment(value: _Mode.skip, label: Text(context.tr('Skip', 'छोड़ें'))),
                ],
                selected: {item.mode},
                onSelectionChanged: (s) {
                  item.mode = s.first;
                  onChanged();
                },
              ),
              const SizedBox(height: 10),
              if (item.mode == _Mode.attach)
                OutlinedButton.icon(
                  onPressed: onPickProduct,
                  icon: const Icon(Icons.search),
                  label: Text(
                    item.attachTo == null
                        ? context.tr('Choose product', 'सामान चुनें')
                        : context.tr(
                            'Photo for: ${item.attachTo!.name}',
                            'फ़ोटो: ${context.pick(item.attachTo!.name, item.attachTo!.nameHi)}',
                          ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (item.mode == _Mode.create) _NewFields(item: item, catalog: catalog, onChanged: onChanged),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewFields extends StatelessWidget {
  const _NewFields({required this.item, required this.catalog, required this.onChanged});
  final _Item item;
  final Catalog catalog;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final cat = catalog.category(item.categoryId) == null ? null : item.categoryId;
    return Column(
      children: [
        TextField(
          controller: item.name,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(labelText: context.tr('Name *', 'नाम *')),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: item.nameHi,
          decoration: InputDecoration(labelText: context.tr('Hindi name', 'हिंदी नाम')),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          key: ValueKey('bulk-cat-${item.key}-$cat'),
          initialValue: cat,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.tr('Category', 'कैटेगरी')),
          items: [
            DropdownMenuItem(value: null, child: Text(context.tr('None', 'कोई नहीं'))),
            for (final c in catalog.categories)
              DropdownMenuItem(
                value: c.id,
                child: Text('${c.icon ?? ''} ${context.pick(c.name, c.nameHi)}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            item.categoryId = v;
            onChanged();
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: item.size,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(labelText: context.tr('Size *', 'साइज़ *'), hintText: '1 kg / 500 ml'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: item.mrp,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: money,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(labelText: 'MRP', prefixText: '₹ '),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: item.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: money,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(labelText: context.tr('Price *', 'रेट *'), prefixText: '₹ '),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
