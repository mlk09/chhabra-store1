import '../../core/money.dart';
import '../../core/units.dart';

class Variant {
  const Variant({
    required this.id,
    required this.productId,
    required this.label,
    required this.unit,
    this.unitQty = 1,
    required this.mrp,
    required this.price,
    this.costPrice,
    this.barcode,
    this.stock = 0,
    this.trackStock = true,
    this.expiryDate,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String productId;
  final String label;
  final SaleUnit unit;
  final double unitQty;
  final Paise mrp;
  final Paise price;

  /// Purchase price. Only loaded for staff allowed to see it; null otherwise.
  final Paise? costPrice;
  final String? barcode;
  final double stock;
  final bool trackStock;
  final DateTime? expiryDate;
  final int sortOrder;
  final bool isActive;

  int get percentOffMrp => percentOff(mrp, price);
  bool get inStock => !trackStock || stock > 0;

  factory Variant.fromJson(Map<String, dynamic> j) => Variant(
    id: j['id'] as String,
    productId: j['product_id'] as String,
    label: j['label'] as String,
    unit: SaleUnit.parse(j['unit'] as String?),
    unitQty: (j['unit_qty'] as num?)?.toDouble() ?? 1,
    mrp: paiseFromJson(j['mrp']),
    price: paiseFromJson(j['price']),
    costPrice: j['cost_price'] == null ? null : paiseFromJson(j['cost_price']),
    barcode: j['barcode'] as String?,
    stock: (j['stock'] as num?)?.toDouble() ?? 0,
    trackStock: j['track_stock'] as bool? ?? true,
    expiryDate: j['expiry_date'] == null ? null : DateTime.tryParse(j['expiry_date'] as String),
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    isActive: j['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'product_id': productId,
    'label': label,
    'unit': unit.code,
    'unit_qty': unitQty,
    'mrp': paiseToJson(mrp),
    'price': paiseToJson(price),
    if (costPrice != null) 'cost_price': paiseToJson(costPrice!),
    'barcode': barcode,
    'stock': stock,
    'track_stock': trackStock,
    'expiry_date': expiryDate?.toIso8601String().substring(0, 10),
    'sort_order': sortOrder,
    'is_active': isActive,
  };

  Variant copyWith({Paise? mrp, Paise? price, double? stock, bool? isActive}) => Variant(
    id: id,
    productId: productId,
    label: label,
    unit: unit,
    unitQty: unitQty,
    mrp: mrp ?? this.mrp,
    price: price ?? this.price,
    costPrice: costPrice,
    barcode: barcode,
    stock: stock ?? this.stock,
    trackStock: trackStock,
    expiryDate: expiryDate,
    sortOrder: sortOrder,
    isActive: isActive ?? this.isActive,
  );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    this.nameHi,
    this.categoryId,
    this.brand,
    this.description,
    this.imagePath,
    this.thumbPath,
    this.isLoose = false,
    this.gstRate = 0,
    this.hsn,
    this.synonyms = const [],
    this.lowStockLimit = 5,
    this.isActive = true,
    this.variants = const [],
    this.emoji,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? nameHi;
  final String? categoryId;
  final String? brand;
  final String? description;
  final String? imagePath;
  final String? thumbPath;
  final bool isLoose;
  final double gstRate;
  final String? hsn;
  final List<String> synonyms;
  final double lowStockLimit;
  final bool isActive;
  final List<Variant> variants;

  /// Demo catalog only: picture stand-in when there is no photo.
  final String? emoji;
  final DateTime? updatedAt;

  List<Variant> get activeVariants => variants.where((v) => v.isActive).toList();

  /// Variant shown on product cards: cheapest active one in stock, else first.
  Variant? get defaultVariant {
    final active = activeVariants;
    if (active.isEmpty) return variants.isEmpty ? null : variants.first;
    final inStock = active.where((v) => v.inStock).toList();
    return (inStock.isEmpty ? active : inStock).first;
  }

  bool get isLowStock => variants.any((v) => v.isActive && v.trackStock && v.stock <= lowStockLimit);

  DateTime? get nearestExpiry {
    final dates = variants.where((v) => v.isActive && v.expiryDate != null).map((v) => v.expiryDate!).toList()..sort();
    return dates.isEmpty ? null : dates.first;
  }

  factory Product.fromJson(Map<String, dynamic> j) {
    final rawVariants = (j['product_variants'] ?? j['variants']) as List? ?? const [];
    final variants = rawVariants.map((v) => Variant.fromJson((v as Map).cast<String, dynamic>())).toList()
      ..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.price.compareTo(b.price));
    return Product(
      id: j['id'] as String,
      name: j['name'] as String,
      nameHi: j['name_hi'] as String?,
      categoryId: j['category_id'] as String?,
      brand: j['brand'] as String?,
      description: j['description'] as String?,
      imagePath: j['image_path'] as String?,
      thumbPath: j['thumb_path'] as String?,
      isLoose: j['is_loose'] as bool? ?? false,
      gstRate: (j['gst_rate'] as num?)?.toDouble() ?? 0,
      hsn: j['hsn'] as String?,
      synonyms: (j['synonyms'] as List?)?.cast<String>() ?? const [],
      lowStockLimit: (j['low_stock_limit'] as num?)?.toDouble() ?? 5,
      isActive: j['is_active'] as bool? ?? true,
      variants: variants,
      emoji: j['emoji'] as String?,
      updatedAt: j['updated_at'] == null ? null : DateTime.tryParse(j['updated_at'] as String),
    );
  }

  /// Product row only (variants are saved separately).
  Map<String, dynamic> toRowJson() => {
    'id': id,
    'name': name,
    'name_hi': nameHi,
    'category_id': categoryId,
    'brand': brand,
    'description': description,
    'image_path': imagePath,
    'thumb_path': thumbPath,
    'is_loose': isLoose,
    'gst_rate': gstRate,
    'hsn': hsn,
    'synonyms': synonyms,
    'low_stock_limit': lowStockLimit,
    'is_active': isActive,
  };

  Map<String, dynamic> toJson() => {
    ...toRowJson(),
    'emoji': emoji,
    'updated_at': updatedAt?.toIso8601String(),
    'variants': variants.map((v) => v.toJson()).toList(),
  };

  Product copyWith({String? imagePath, String? thumbPath, bool? isActive, List<Variant>? variants}) => Product(
    id: id,
    name: name,
    nameHi: nameHi,
    categoryId: categoryId,
    brand: brand,
    description: description,
    imagePath: imagePath ?? this.imagePath,
    thumbPath: thumbPath ?? this.thumbPath,
    isLoose: isLoose,
    gstRate: gstRate,
    hsn: hsn,
    synonyms: synonyms,
    lowStockLimit: lowStockLimit,
    isActive: isActive ?? this.isActive,
    variants: variants ?? this.variants,
    emoji: emoji,
    updatedAt: updatedAt,
  );
}
