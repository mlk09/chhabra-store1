import 'category.dart';
import 'order.dart';
import 'product.dart';
import 'shop.dart';

/// Everything a screen needs to show the shop, with quick lookups.
class Catalog {
  Catalog({
    required this.shop,
    required List<Category> categories,
    required List<Product> products,
    List<Offer> offers = const [],
  }) : categories = List.unmodifiable([...categories]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))),
       products = List.unmodifiable(
         [...products]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
       ),
       offers = List.unmodifiable(offers) {
    for (final p in this.products) {
      _byId[p.id] = p;
      for (final v in p.variants) {
        if (v.barcode != null) _byBarcode[v.barcode!] = p;
        _byVariant[v.id] = (p, v);
      }
    }
    for (final c in this.categories) {
      _categoryById[c.id] = c;
    }
  }

  final Shop shop;
  final List<Category> categories;
  final List<Product> products;

  /// Offers the shop runs (customers receive only the active ones).
  final List<Offer> offers;
  final _byId = <String, Product>{};
  final _byBarcode = <String, Product>{};
  final _byVariant = <String, (Product, Variant)>{};
  final _categoryById = <String, Category>{};

  Product? product(String id) => _byId[id];
  Product? byBarcode(String code) => _byBarcode[code];
  (Product, Variant)? variant(String variantId) => _byVariant[variantId];
  Category? category(String? id) => id == null ? null : _categoryById[id];

  List<Category> get activeCategories => categories.where((c) => c.isActive).toList();

  /// What customers see: active products that have at least one active variant.
  List<Product> get visibleProducts => products
      .where((p) => p.isActive && p.activeVariants.isNotEmpty && (category(p.categoryId)?.isActive ?? true))
      .toList();

  List<Product> inCategory(String categoryId, {bool onlyVisible = true}) =>
      (onlyVisible ? visibleProducts : products).where((p) => p.categoryId == categoryId).toList();

  /// Item offers running now for a product (its own or its category's).
  List<Offer> liveOffersFor(Product p, DateTime now) => offers
      .where(
        (o) =>
            o.liveAt(now) &&
            ((o.productId == p.id && o.kind.forProduct) ||
                (o.kind == OfferKind.categoryPercent && o.categoryId == p.categoryId)),
      )
      .toList();

  /// Cart-wide offers running now (₹ off above X, free delivery above X).
  List<Offer> liveCartOffers(DateTime now) => offers.where((o) => o.liveAt(now) && o.kind.forCart).toList();

  Catalog copyWith({Shop? shop, List<Category>? categories, List<Product>? products, List<Offer>? offers}) => Catalog(
    shop: shop ?? this.shop,
    categories: categories ?? this.categories,
    products: products ?? this.products,
    offers: offers ?? this.offers,
  );

  Catalog withProduct(Product p) => copyWith(products: [...products.where((x) => x.id != p.id), p]);
  Catalog withoutProduct(String id) => copyWith(
    products: products.where((x) => x.id != id).toList(),
    offers: offers.where((o) => o.productId != id).toList(),
  );
  Catalog withCategory(Category c) => copyWith(categories: [...categories.where((x) => x.id != c.id), c]);
  Catalog withoutCategory(String id) => copyWith(
    categories: categories.where((x) => x.id != id).toList(),
    products: products.map((p) => p.categoryId == id ? _uncategorised(p) : p).toList(),
    offers: offers.where((o) => o.categoryId != id).toList(),
  );
  Catalog withOffer(Offer o) => copyWith(offers: [...offers.where((x) => x.id != o.id), o]);
  Catalog withoutOffer(String id) => copyWith(offers: offers.where((x) => x.id != id).toList());

  static Product _uncategorised(Product p) => Product.fromJson({...p.toJson(), 'category_id': null});

  Map<String, dynamic> toJson() => {
    'shop': shop.toJson(),
    'categories': categories.map((c) => c.toJson()).toList(),
    'products': products.map((p) => p.toJson()).toList(),
    'offers': offers.map((o) => o.toJson()).toList(),
  };

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
    shop: Shop.fromJson((j['shop'] as Map).cast<String, dynamic>()),
    categories: (j['categories'] as List).map((c) => Category.fromJson((c as Map).cast<String, dynamic>())).toList(),
    products: (j['products'] as List).map((p) => Product.fromJson((p as Map).cast<String, dynamic>())).toList(),
    offers: ((j['offers'] as List?) ?? const [])
        .map((o) => Offer.fromJson((o as Map).cast<String, dynamic>()))
        .toList(),
  );
}
