import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/units.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/product_widgets.dart';
import '../../data/backend.dart';
import '../../data/models/catalog.dart';
import '../../data/models/member.dart';
import '../../data/models/product.dart';
import '../../data/models/product_guess.dart';
import '../../domain/search.dart';
import 'ai_fill.dart';
import 'photo.dart';

const _gstRates = [0.0, 5.0, 18.0, 40.0, 12.0, 28.0, 3.0, 0.25];

/// Add or edit a product with all its sizes.
class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, this.productId, this.barcode});
  final String? productId;
  final String? barcode;

  @override
  ConsumerState<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final String _id;
  Product? _original;
  bool _ready = false;
  bool _saving = false;
  bool _dirty = false;

  final _name = TextEditingController();
  final _nameHi = TextEditingController();
  final _brand = TextEditingController();
  final _synonyms = TextEditingController();
  final _lowStock = TextEditingController(text: '5');
  final _hsn = TextEditingController();
  final _description = TextEditingController();
  String? _categoryId;
  bool _loose = false;
  bool _active = true;
  double _gst = 0;
  ProductPhoto? _newPhoto;
  final List<_SizeForm> _sizes = [];

  @override
  void initState() {
    super.initState();
    _id = widget.productId ?? const Uuid().v4();
  }

  void _load(Catalog catalog) {
    if (_ready) return;
    _ready = true;
    final p = widget.productId == null ? null : catalog.product(widget.productId!);
    _original = p;
    if (p == null) {
      _sizes.add(_SizeForm.blank(barcode: widget.barcode));
      return;
    }
    _name.text = p.name;
    _nameHi.text = p.nameHi ?? '';
    _brand.text = p.brand ?? '';
    _synonyms.text = p.synonyms.join(', ');
    _lowStock.text = _num(p.lowStockLimit);
    _hsn.text = p.hsn ?? '';
    _description.text = p.description ?? '';
    _categoryId = catalog.category(p.categoryId) == null ? null : p.categoryId;
    _loose = p.isLoose;
    _active = p.isActive;
    _gst = p.gstRate;
    _sizes.addAll(p.variants.map(_SizeForm.from));
    if (_sizes.isEmpty) _sizes.add(_SizeForm.blank());
  }

  @override
  void dispose() {
    for (final c in [_name, _nameHi, _brand, _synonyms, _lowStock, _hsn, _description]) {
      c.dispose();
    }
    for (final s in _sizes) {
      s.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Picks a photo; with [withAi] the AI also fills in name, category, size, MRP.
  Future<void> _choosePhoto({bool withAi = false}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(ctx.tr('Take photo', 'फ़ोटो खींचें')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(ctx.tr('Choose from gallery', 'गैलरी से चुनें')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final photo = await pickProductPhoto(source);
      if (photo == null || !mounted) return;
      setState(() {
        _newPhoto = photo;
        _dirty = true;
      });
      if (!withAi) return;
      final guess = await readPhotoWithAi(context, ref, photo);
      if (guess != null && mounted) _applyGuess(guess);
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  /// Fills empty fields from the AI's reading (a new product gets everything).
  void _applyGuess(ProductGuess g) {
    final catalog = ref.read(catalogProvider).value!;
    final canPrice = ref.read(sessionProvider).value?.can(Perm.prices) ?? false;
    final isNew = _original == null;
    bool empty(TextEditingController c) => c.text.trim().isEmpty;
    setState(() {
      if (isNew || empty(_name)) _name.text = g.name;
      if (g.nameHi != null && (isNew || empty(_nameHi))) _nameHi.text = g.nameHi!;
      if (g.brand != null && (isNew || empty(_brand))) _brand.text = g.brand!;
      if (catalog.category(g.categoryId) != null && (isNew || _categoryId == null)) _categoryId = g.categoryId;
      final words = {..._synonyms.text.split(',').map((w) => w.trim()).where((w) => w.isNotEmpty), ...g.synonyms};
      _synonyms.text = words.join(', ');
      final size = _sizes.first;
      if (isNew) {
        _loose = g.isLoose;
        size.unit = g.unit;
        size.unitQty = g.unitQty;
        if (g.isLoose) size.makeLoose();
      }
      if (empty(size.label) || isNew) size.label.text = g.label;
      if (canPrice && g.mrp != null && empty(size.mrp)) {
        size.mrp.text = rupeesText(g.mrp!);
        if (empty(size.price)) size.price.text = rupeesText(g.mrp!);
      }
      _dirty = true;
    });
    final existing = isNew ? findBestMatch(g.name, catalog.products, catalog: catalog) : null;
    showSnack(
      context,
      existing != null
          ? context.tr(
              'Looks like "${existing.name}" is already in your list.',
              '"${existing.name}" पहले से आपकी लिस्ट में लगता है।',
            )
          : context.tr(
              'Filled from photo — please check name, size and price.',
              'फ़ोटो से भरा — नाम, साइज़ और रेट जाँच लें।',
            ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      showSnack(context, context.tr('Please fix the fields in red.', 'लाल रंग वाले खाने ठीक करें।'), error: true);
      return;
    }
    final variants = <Variant>[];
    for (var i = 0; i < _sizes.length; i++) {
      variants.add(_sizes[i].toVariant(productId: _id, loose: _loose, sortOrder: i));
    }
    final product = Product(
      id: _id,
      name: _name.text.trim(),
      nameHi: _nameHi.text.trim().isEmpty ? null : _nameHi.text.trim(),
      categoryId: _categoryId,
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      imagePath: _original?.imagePath,
      thumbPath: _original?.thumbPath,
      isLoose: _loose,
      gstRate: _gst,
      hsn: _hsn.text.trim().isEmpty ? null : _hsn.text.trim(),
      synonyms: _synonyms.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).take(20).toList(),
      lowStockLimit: double.tryParse(_lowStock.text) ?? 5,
      isActive: _active,
      variants: variants,
      emoji: _original?.emoji,
    );
    final stockChanged = _original == null
        ? null
        : {
            for (final s in _sizes)
              if (s.stockEdited) s.id,
          };

    setState(() => _saving = true);
    try {
      await ref.read(catalogProvider.notifier).saveProduct(product, photo: _newPhoto, stockChanged: stockChanged);
      if (!mounted) return;
      showSnack(context, context.tr('Saved ✓', 'सेव हो गया ✓'));
      _dirty = false;
      context.pop();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('Delete this product?', 'यह सामान हटाएँ?')),
        content: Text(
          ctx.tr(
            'Tip: switch off "Show to customers" instead if you may sell it again.',
            'सुझाव: अगर दोबारा बेचना हो तो हटाने की बजाय "ग्राहकों को दिखाएँ" बंद कर दें।',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('Cancel', 'रद्द करें'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('Delete', 'हटाएँ')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(catalogProvider.notifier).deleteProduct(_id);
      if (!mounted) return;
      _dirty = false;
      showSnack(context, context.tr('Product deleted', 'सामान हटा दिया'));
      context.pop();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(catalogProvider);
    final session = ref.watch(sessionProvider).value;
    final catalog = async.value;
    if (catalog == null) return const Scaffold(body: LoadingView());
    _load(catalog);
    final canPrice = session?.can(Perm.prices) ?? false;
    final isNew = _original == null;
    final t = Theme.of(context);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.tr('Discard changes?', 'बदलाव छोड़ दें?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ctx.tr('Keep editing', 'एडिट करते रहें')),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('Discard', 'छोड़ दें'))),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          _dirty = false;
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? context.tr('Add product', 'सामान जोड़ें') : context.tr('Edit product', 'सामान बदलें')),
          actions: [
            if (!isNew)
              IconButton(
                tooltip: context.tr('Delete', 'हटाएँ'),
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _delete,
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.check_rounded),
              label: Text(context.tr('Save product', 'सामान सेव करें')),
            ),
          ),
        ),
        body: Form(
          key: _form,
          onChanged: _changed,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _PhotoPicker(
                    product: _original,
                    fallbackEmoji: catalog.category(_categoryId)?.icon,
                    newPhoto: _newPhoto,
                    onTap: _choosePhoto,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: FilledButton.tonalIcon(
                      onPressed: () => _choosePhoto(withAi: true),
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(context.tr('Fill from photo (AI)', 'फ़ोटो से भरें (AI)')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: context.tr('Name (English) *', 'नाम (English) *')),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? context.tr('Name is required', 'नाम ज़रूरी है') : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameHi,
                    decoration: InputDecoration(
                      labelText: context.tr('Name in Hindi', 'हिंदी नाम'),
                      hintText: 'जैसे: चीनी',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _brand,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(labelText: context.tr('Brand', 'ब्रांड')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          key: ValueKey('cat-$_categoryId'), // re-reads the value after "Fill from photo"
                          initialValue: _categoryId,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: context.tr('Category', 'कैटेगरी')),
                          items: [
                            DropdownMenuItem(value: null, child: Text(context.tr('None', 'कोई नहीं'))),
                            for (final c in catalog.categories)
                              DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  '${c.icon ?? ''} ${context.pick(c.name, c.nameHi)}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            _categoryId = v;
                            _dirty = true;
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Sold loose by weight', 'खुला, वज़न से बिकता है')),
                    subtitle: Text(
                      context.tr(
                        'Price per kg / litre — e.g. ₹60/kg, customer buys 250 g = ₹15',
                        'किलो/लीटर का रेट — जैसे ₹60/किलो, 250 ग्राम = ₹15',
                      ),
                    ),
                    value: _loose,
                    onChanged: (v) => setState(() {
                      _loose = v;
                      _dirty = true;
                      if (v) {
                        for (final s in _sizes) {
                          s.makeLoose();
                        }
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _loose ? context.tr('Rate', 'रेट') : context.tr('Sizes & prices', 'साइज़ और रेट'),
                          style: t.textTheme.titleMedium,
                        ),
                      ),
                      if (!canPrice)
                        Row(
                          children: [
                            Icon(Icons.lock_outline, size: 16, color: t.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              context.tr('Only owner can change prices', 'रेट सिर्फ़ मालिक बदल सकता है'),
                              style: t.textTheme.bodySmall,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _sizes.length; i++)
                    _SizeCard(
                      key: ValueKey(_sizes[i].id),
                      form: _sizes[i],
                      loose: _loose,
                      canPrice: canPrice,
                      canRemove: _sizes.length > 1 && (canPrice || _sizes[i].isNew),
                      onRemove: () => setState(() {
                        _sizes.removeAt(i).dispose();
                        _dirty = true;
                      }),
                      onChanged: _changed,
                    ),
                  if (!_loose && canPrice)
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _sizes.add(_SizeForm.blank());
                        _dirty = true;
                      }),
                      icon: const Icon(Icons.add),
                      label: Text(context.tr('Add another size (e.g. 5 kg)', 'एक और साइज़ जोड़ें (जैसे 5 किलो)')),
                    ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('Show to customers', 'ग्राहकों को दिखाएँ')),
                    subtitle: Text(context.tr('Turn off to hide without deleting', 'बिना हटाए छुपाने के लिए बंद करें')),
                    value: _active,
                    onChanged: (v) => setState(() {
                      _active = v;
                      _dirty = true;
                    }),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      context.tr('More details (GST, search words, alerts)', 'और जानकारी (GST, खोज शब्द, अलर्ट)'),
                    ),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<double>(
                              initialValue: _gst,
                              decoration: const InputDecoration(labelText: 'GST %'),
                              items: [
                                for (final r in {..._gstRates, _gst})
                                  DropdownMenuItem(value: r, child: Text('${_num(r)}%')),
                              ],
                              onChanged: (v) => setState(() {
                                _gst = v ?? 0;
                                _dirty = true;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _hsn,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'HSN'),
                              validator: (v) => (v == null || v.isEmpty || RegExp(r'^[0-9]{4,8}$').hasMatch(v))
                                  ? null
                                  : context.tr('4–8 digits', '4–8 अंक'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _synonyms,
                        decoration: InputDecoration(
                          labelText: context.tr('Other names for search', 'खोज के लिए दूसरे नाम'),
                          hintText: 'cheeni, shakkar',
                          helperText: context.tr('Separate with commas', 'कॉमा (,) से अलग करें'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _lowStock,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: context.tr('Low-stock alert at', 'कम स्टॉक अलर्ट कब'),
                          suffixText: _loose ? 'kg' : context.tr('pcs', 'पीस'),
                        ),
                        validator: (v) =>
                            (double.tryParse(v ?? '') ?? -1) >= 0 ? null : context.tr('Enter a number', 'संख्या लिखें'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _description,
                        maxLines: 3,
                        maxLength: 1000,
                        decoration: InputDecoration(
                          labelText: context.tr('Description (optional)', 'विवरण (वैकल्पिक)'),
                        ),
                      ),
                    ],
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

String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.product, required this.newPhoto, required this.onTap, this.fallbackEmoji});
  final Product? product;
  final ProductPhoto? newPhoto;
  final VoidCallback onTap;
  final String? fallbackEmoji;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hasPhoto = newPhoto != null || product?.imagePath != null;
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: t.colorScheme.surfaceContainer,
            border: Border.all(color: t.colorScheme.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (newPhoto != null)
                  Image.memory(newPhoto!.thumb, fit: BoxFit.cover)
                else if (product != null && hasPhoto)
                  ProductImage(product: product!, fallbackEmoji: fallbackEmoji)
                else
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 36, color: t.colorScheme.primary),
                      const SizedBox(height: 6),
                      Text(context.tr('Add photo', 'फ़ोटो जोड़ें'), style: t.textTheme.bodyMedium),
                    ],
                  ),
                if (hasPhoto)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.black54,
                      child: const Icon(Icons.edit, color: Colors.white, size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text fields for one size/variant.
class _SizeForm {
  _SizeForm._({
    required this.id,
    required this.isNew,
    required this.unit,
    required this.active,
    this.expiry,
    this.unitQty = 1,
    String label = '',
    String mrp = '',
    String price = '',
    String cost = '',
    String stock = '',
    String barcode = '',
    this.trackStock = true,
  }) : label = TextEditingController(text: label),
       mrp = TextEditingController(text: mrp),
       price = TextEditingController(text: price),
       cost = TextEditingController(text: cost),
       stock = TextEditingController(text: stock),
       barcode = TextEditingController(text: barcode),
       _initialStock = stock;

  factory _SizeForm.blank({String? barcode}) => _SizeForm._(
    id: const Uuid().v4(),
    isNew: true,
    unit: SaleUnit.pc,
    active: true,
    stock: '0',
    barcode: barcode ?? '',
  );

  factory _SizeForm.from(Variant v) => _SizeForm._(
    id: v.id,
    isNew: false,
    unit: v.unit,
    unitQty: v.unitQty,
    active: v.isActive,
    expiry: v.expiryDate,
    label: v.label,
    mrp: rupeesText(v.mrp),
    price: rupeesText(v.price),
    cost: v.costPrice == null ? '' : rupeesText(v.costPrice!),
    stock: _num(v.stock),
    barcode: v.barcode ?? '',
    trackStock: v.trackStock,
  );

  final String id;
  final bool isNew;
  SaleUnit unit;
  double unitQty;
  bool active;
  bool trackStock;
  DateTime? expiry;
  final TextEditingController label, mrp, price, cost, stock, barcode;
  final String _initialStock;

  bool get stockEdited => isNew || stock.text.trim() != _initialStock;

  void makeLoose() {
    if (!unit.isMeasured) unit = SaleUnit.kg;
    unitQty = 1;
    if (label.text.trim().isEmpty || !label.text.startsWith('per')) {
      label.text = 'per ${unit == SaleUnit.l ? 'litre' : 'kg'}';
    }
  }

  Variant toVariant({required String productId, required bool loose, required int sortOrder}) {
    final p = parseRupees(price.text)!;
    final m = parseRupees(mrp.text) ?? p;
    return Variant(
      id: id,
      productId: productId,
      label: label.text.trim(),
      unit: unit,
      unitQty: loose ? 1 : unitQty,
      mrp: m,
      price: p,
      costPrice: parseRupees(cost.text),
      barcode: barcode.text.trim().isEmpty ? null : barcode.text.trim(),
      stock: double.tryParse(stock.text.trim()) ?? 0,
      trackStock: trackStock,
      expiryDate: expiry,
      sortOrder: sortOrder,
      isActive: active,
    );
  }

  void dispose() {
    for (final c in [label, mrp, price, cost, stock, barcode]) {
      c.dispose();
    }
  }
}

class _SizeCard extends StatefulWidget {
  const _SizeCard({
    super.key,
    required this.form,
    required this.loose,
    required this.canPrice,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });
  final _SizeForm form;
  final bool loose;
  final bool canPrice;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_SizeCard> createState() => _SizeCardState();
}

class _SizeCardState extends State<_SizeCard> {
  _SizeForm get f => widget.form;
  final _money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

  String? _priceError(String? v) {
    final p = parseRupees(v ?? '');
    if (p == null) return context.tr('Enter price', 'रेट लिखें');
    final m = parseRupees(f.mrp.text);
    if (m != null && p > m) return context.tr('More than MRP', 'MRP से ज़्यादा');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final loose = widget.loose;
    final units = loose ? SaleUnit.values.where((u) => u.isMeasured).toList() : SaleUnit.values;
    if (!units.contains(f.unit)) f.unit = units.first;
    final m = parseRupees(f.mrp.text), p = parseRupees(f.price.text), c = parseRupees(f.cost.text);
    final off = m != null && p != null ? percentOff(m, p) : 0;
    final margin = p != null && c != null && p > 0 ? ((p - c) * 100 / p) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: f.label,
                    decoration: InputDecoration(
                      labelText: loose ? context.tr('Label', 'लेबल') : context.tr('Size *', 'साइज़ *'),
                      hintText: loose ? 'per kg' : '1 kg / 500 ml / 1 pc',
                    ),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? context.tr('Required', 'ज़रूरी') : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<SaleUnit>(
                    key: ValueKey('unit-${f.id}-${f.unit.code}'),
                    initialValue: f.unit,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.tr('Unit', 'इकाई')),
                    items: [
                      for (final u in units)
                        DropdownMenuItem(value: u, child: Text(context.isHindi ? u.hindi : u.code)),
                    ],
                    onChanged: (u) {
                      setState(() => f.unit = u ?? f.unit);
                      widget.onChanged();
                    },
                  ),
                ),
                if (widget.canRemove)
                  IconButton(
                    tooltip: context.tr('Remove size', 'साइज़ हटाएँ'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: f.mrp,
                    enabled: widget.canPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _money,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'MRP',
                      prefixText: '₹ ',
                      suffixText: loose ? '/${f.unit.code}' : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: f.price,
                    enabled: widget.canPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _money,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: context.tr('Selling price *', 'बिक्री रेट *'),
                      prefixText: '₹ ',
                      suffixText: loose ? '/${f.unit.code}' : null,
                    ),
                    validator: _priceError,
                  ),
                ),
              ],
            ),
            if (widget.canPrice) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: f.cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: _money,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.tr('Purchase price (only you see this)', 'ख़रीद रेट (सिर्फ़ आपको दिखेगा)'),
                  prefixText: '₹ ',
                  helperText: margin == null
                      ? null
                      : context.tr('Margin ${margin.toStringAsFixed(1)}%', 'मुनाफ़ा ${margin.toStringAsFixed(1)}%'),
                ),
              ),
            ],
            if (off > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    context.tr('Customers see $off% OFF', 'ग्राहकों को $off% छूट दिखेगी'),
                    style: TextStyle(color: t.colorScheme.secondary, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: f.stock,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _money,
                    decoration: InputDecoration(
                      labelText: context.tr('Stock', 'स्टॉक'),
                      suffixText: loose ? f.unit.code : context.tr('pcs', 'पीस'),
                    ),
                    validator: (v) =>
                        (double.tryParse(v?.trim() ?? '') ?? -1) >= 0 ? null : context.tr('0 or more', '0 या ज़्यादा'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: f.barcode,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.tr('Barcode', 'बारकोड')),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty || RegExp(r'^[0-9A-Za-z-]{4,32}$').hasMatch(v.trim()))
                        ? null
                        : context.tr('Invalid', 'गलत'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.event_outlined, size: 20),
                      label: Text(
                        f.expiry == null
                            ? context.tr('Expiry date', 'एक्सपायरी')
                            : DateFormat('d MMM y').format(f.expiry!),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: f.expiry ?? now.add(const Duration(days: 90)),
                          firstDate: now.subtract(const Duration(days: 365)),
                          lastDate: now.add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setState(() => f.expiry = picked);
                          widget.onChanged();
                        }
                      },
                    ),
                  ),
                ),
                if (f.expiry != null)
                  IconButton(
                    tooltip: context.tr('Clear expiry', 'एक्सपायरी हटाएँ'),
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      setState(() => f.expiry = null);
                      widget.onChanged();
                    },
                  ),
                Text(context.tr('On sale', 'बिक्री में'), style: t.textTheme.bodyMedium),
                Switch(
                  value: f.active,
                  onChanged: (v) {
                    setState(() => f.active = v);
                    widget.onChanged();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
