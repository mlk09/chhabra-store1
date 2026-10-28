import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/widgets/product_widgets.dart';
import '../../data/models/catalog.dart';
import '../../data/models/product.dart';
import '../../domain/search.dart';

/// Search-and-pick a product in a bottom sheet.
Future<Product?> pickProduct(BuildContext context, Catalog catalog) => showModalBottomSheet<Product>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ProductPicker(catalog: catalog),
);

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.catalog});
  final Catalog catalog;
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.catalog;
    final list = _q.trim().isEmpty ? c.products : searchProducts(_q, c.products, catalog: c);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.tr('Search product', 'सामान खोजें'),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ProductImage(
                      product: list[i],
                      size: 44,
                      fallbackEmoji: c.category(list[i].categoryId)?.icon,
                    ),
                  ),
                  title: Text(context.pick(list[i].name, list[i].nameHi)),
                  subtitle: Text(
                    list[i].variants.map((v) => v.label).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(context, list[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
