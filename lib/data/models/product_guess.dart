import '../../core/money.dart';
import '../../core/units.dart';

/// What the AI read from a product photo. Always shown to the shopkeeper to
/// check before saving — it is a suggestion, never saved on its own.
class ProductGuess {
  const ProductGuess({
    required this.isProduct,
    required this.name,
    this.nameHi,
    this.brand,
    this.sizeLabel,
    this.unit = SaleUnit.pc,
    this.unitQty = 1,
    this.mrp,
    this.isLoose = false,
    this.categoryId,
    this.synonyms = const [],
    this.confidence = 0,
  });

  final bool isProduct;
  final String name;
  final String? nameHi;
  final String? brand;
  final String? sizeLabel;
  final SaleUnit unit;
  final double unitQty;
  final Paise? mrp;
  final bool isLoose;
  final String? categoryId;
  final List<String> synonyms;
  final double confidence;

  factory ProductGuess.fromJson(Map<String, dynamic> j) => ProductGuess(
    isProduct: j['is_product'] as bool? ?? false,
    name: (j['name'] as String?)?.trim() ?? '',
    nameHi: j['name_hi'] as String?,
    brand: j['brand'] as String?,
    sizeLabel: j['size_label'] as String?,
    unit: SaleUnit.parse(j['unit'] as String?),
    unitQty: (j['unit_qty'] as num?)?.toDouble() ?? 1,
    mrp: j['mrp'] == null ? null : paiseFromJson(j['mrp']),
    isLoose: j['is_loose'] as bool? ?? false,
    categoryId: j['category_id'] as String?,
    synonyms: (j['synonyms'] as List?)?.whereType<String>().toList() ?? const [],
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
  );

  /// A size label even when the pack size wasn't readable.
  String get label => sizeLabel ?? (isLoose ? 'per ${unit == SaleUnit.l ? 'litre' : 'kg'}' : '1 ${unit.code}');
}
