import 'package:chhabra_store/core/units.dart';
import 'package:chhabra_store/data/demo/demo_backend.dart';
import 'package:chhabra_store/data/demo/demo_catalog.dart';
import 'package:chhabra_store/data/models/catalog.dart';
import 'package:chhabra_store/data/models/product.dart';
import 'package:chhabra_store/data/models/product_guess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog survives a save/load round trip (offline cache)', () {
    final c = buildDemoCatalog();
    final back = Catalog.fromJson(c.toJson());
    expect(back.products.length, c.products.length);
    expect(back.categories.length, c.categories.length);
    final atta = back.products.firstWhere((p) => p.name.startsWith('Aashirvaad'));
    expect(atta.variants.map((v) => v.price), [6200, 27900, 54500]);
    expect(atta.variants.first.costPrice, isNotNull);
    expect(back.byBarcode('8901725181123')?.id, atta.id);
  });

  test('customers only see active items in active categories', () {
    final c = buildDemoCatalog();
    final atta = c.products.first;
    final hidden = c.withProduct(atta.copyWith(isActive: false));
    expect(hidden.visibleProducts.any((p) => p.id == atta.id), isFalse);
    final cat = c.categories.first;
    final hiddenCat = c.withCategory(cat.copyWith(isActive: false));
    expect(hiddenCat.visibleProducts.any((p) => p.categoryId == cat.id), isFalse);
  });

  test('deleting a category keeps its products, uncategorised', () {
    final c = buildDemoCatalog();
    final next = c.withoutCategory('c-oil');
    expect(next.products.length, c.products.length);
    expect(next.products.where((p) => p.categoryId == 'c-oil'), isEmpty);
  });

  test('low stock and expiry helpers', () {
    final c = buildDemoCatalog();
    expect(c.products.firstWhere((p) => p.name == 'Tomato').isLowStock, isTrue);
    expect(c.products.firstWhere((p) => p.name == 'Potato').isLowStock, isFalse);
    expect(c.products.firstWhere((p) => p.name == 'Amul Taaza Milk').nearestExpiry, isNotNull);
  });

  test('default variant prefers an in-stock size', () {
    const p = Product(
      id: 'x',
      name: 'X',
      variants: [
        Variant(id: 'a', productId: 'x', label: 'small', unit: SaleUnit.pc, mrp: 100, price: 90, stock: 0),
        Variant(id: 'b', productId: 'x', label: 'big', unit: SaleUnit.pc, mrp: 300, price: 250, stock: 5),
      ],
    );
    expect(p.defaultVariant?.id, 'b');
  });

  test('demo bulk update: +10% on oil, price capped at MRP', () async {
    final demo = DemoBackend(asShopkeeper: true);
    final n = await demo.bulkUpdatePrices(percent: 10, categoryId: 'c-oil');
    expect(n, 5); // 2 + 1 + 2 sizes
    final oil = (await demo.loadCatalog(staffView: true)).products
        .firstWhere((p) => p.name.startsWith('Fortune Kachi'));
    expect(oil.variants.first.mrp, 21500); // 195 → 214.5 → 215
    expect(oil.variants.first.price, 18900); // 172 → 189.2 → 189
    await demo.bulkUpdatePrices(percent: 50, categoryId: 'c-oil', applyTo: 'price');
    final again = (await demo.loadCatalog(staffView: true)).products
        .firstWhere((p) => p.name.startsWith('Fortune Kachi'));
    expect(again.variants.first.price, again.variants.first.mrp);
  });

  test('demo refuses a price above MRP', () async {
    final demo = DemoBackend(asShopkeeper: true);
    final p = (await demo.loadCatalog(staffView: true)).products.first;
    final bad = p.copyWith(variants: [p.variants.first.copyWith(price: p.variants.first.mrp + 100)]);
    expect(() => demo.saveProduct(bad), throwsA(anything));
  });

  test('AI guess is read safely', () {
    final g = ProductGuess.fromJson({
      'is_product': true,
      'name': 'Tata Salt',
      'name_hi': 'टाटा नमक',
      'size_label': '1 kg',
      'unit': 'kg',
      'unit_qty': 1,
      'mrp': 30,
      'category_id': 'c-sugar',
      'synonyms': ['namak', 5],
    });
    expect(g.mrp, 3000);
    expect(g.unit, SaleUnit.kg);
    expect(g.synonyms, ['namak']);
    expect(g.label, '1 kg');
    expect(const ProductGuess(isProduct: true, name: 'Potato', isLoose: true, unit: SaleUnit.kg).label, 'per kg');
  });
}
