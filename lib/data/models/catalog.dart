import 'category.dart';
import 'product.dart';
import 'shop.dart';

/// Everything a screen needs to show the shop, with quick lookups.
class Catalog {
  Catalog({required this.shop, required List<Category> categories, required List<Product> products})
    : categories = List.unmodifiable([...categories]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))),
      products = List.unmodifiable(
        [...products]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      ) {
    for (final p in this.products) {
      _byId[p.id] = p;
      for (final v in p.variants) {
        if (v.barcode != null) _byBarcode[v.barcode!] = p;
      }
    }
    for (final c in this.categories) {
      _categoryById[c.id] = c;
    }
  }

  final Shop shop;
  final List<Category> categories;
  final List<Product> products;
  final _byId = <String, Product>{};
  final _byBarcode = <String, Product>{};
  final _categoryById = <String, Category>{};

  Product? product(String id) => _byId[id];
  Product? byBarcode(String code) => _byBarcode[code];
  Category? category(String? id) => id == null ? null : _categoryById[id];

  List<Category> get activeCategories => categories.where((c) => c.isActive).toList();

  /// What customers see: active products that have at least one active variant.
  List<Product> get visibleProducts => products
      .where((p) => p.isActive && p.activeVariants.isNotEmpty && (category(p.categoryId)?.isActive ?? true))
      .toList();

  List<Product> inCategory(String categoryId, {bool onlyVisible = true}) =>
      (onlyVisible ? visibleProducts : products).where((p) => p.categoryId == categoryId).toList();

  Catalog copyWith({Shop? shop, List<Category>? categories, List<Product>? products}) =>
      Catalog(shop: shop ?? this.shop, categories: categories ?? this.categories, products: products ?? this.products);

  Catalog withProduct(Product p) => copyWith(products: [...products.where((x) => x.id != p.id), p]);
  Catalog withoutProduct(String id) => copyWith(products: products.where((x) => x.id != id).toList());
  Catalog withCategory(Category c) => copyWith(categories: [...categories.where((x) => x.id != c.id), c]);
  Catalog withoutCategory(String id) => copyWith(
    categories: categories.where((x) => x.id != id).toList(),
    products: products.map((p) => p.categoryId == id ? _uncategorised(p) : p).toList(),
  );

  static Product _uncategorised(Product p) => Product.fromJson({...p.toJson(), 'category_id': null});

  Map<String, dynamic> toJson() => {
    'shop': shop.toJson(),
    'categories': categories.map((c) => c.toJson()).toList(),
    'products': products.map((p) => p.toJson()).toList(),
  };

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
    shop: Shop.fromJson((j['shop'] as Map).cast<String, dynamic>()),
    categories: (j['categories'] as List).map((c) => Category.fromJson((c as Map).cast<String, dynamic>())).toList(),
    products: (j['products'] as List).map((p) => Product.fromJson((p as Map).cast<String, dynamic>())).toList(),
  );
}
