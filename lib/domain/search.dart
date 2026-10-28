import '../data/models/catalog.dart';
import '../data/models/product.dart';

/// Words people actually type at a kirana: Hinglish, Hindi and English.
/// Each line is one group; searching any word finds products named with any other.
const synonymGroups = <List<String>>[
  ['aloo', 'alu', 'potato', 'आलू'],
  ['pyaz', 'pyaaz', 'pyaj', 'kanda', 'onion', 'प्याज'],
  ['tamatar', 'tomato', 'टमाटर'],
  ['cheeni', 'chini', 'shakkar', 'sugar', 'चीनी', 'शक्कर'],
  ['atta', 'aata', 'gehun', 'wheat', 'flour', 'आटा'],
  ['chawal', 'rice', 'basmati', 'चावल'],
  ['dal', 'daal', 'lentil', 'pulses', 'दाल'],
  ['tel', 'oil', 'तेल'],
  ['sarson', 'mustard', 'सरसों'],
  ['doodh', 'dudh', 'milk', 'दूध'],
  ['dahi', 'curd', 'yogurt', 'दही'],
  ['makhan', 'makkhan', 'butter', 'मक्खन'],
  ['ghee', 'ghi', 'घी'],
  ['paneer', 'cottage cheese', 'पनीर'],
  ['namak', 'salt', 'नमक'],
  ['haldi', 'turmeric', 'हल्दी'],
  ['mirch', 'mirchi', 'chilli', 'chili', 'मिर्च'],
  ['dhaniya', 'dhania', 'coriander', 'धनिया'],
  ['jeera', 'zeera', 'cumin', 'जीरा'],
  ['rai', 'mustard seeds', 'राई'],
  ['elaichi', 'cardamom', 'इलायची'],
  ['laung', 'clove', 'लौंग'],
  ['adrak', 'ginger', 'अदरक'],
  ['lehsun', 'lahsun', 'garlic', 'लहसुन'],
  ['nimbu', 'lemon', 'नींबू'],
  ['besan', 'gram flour', 'बेसन'],
  ['maida', 'refined flour', 'मैदा'],
  ['suji', 'sooji', 'rava', 'semolina', 'सूजी'],
  ['poha', 'chivda', 'flattened rice', 'पोहा'],
  ['gud', 'gur', 'jaggery', 'गुड़'],
  ['anda', 'ande', 'egg', 'eggs', 'अंडा'],
  ['chai', 'chay', 'tea', 'चाय'],
  ['coffee', 'kofi', 'कॉफ़ी'],
  ['sabun', 'soap', 'साबुन'],
  ['biscuit', 'biskut', 'cookies', 'बिस्कुट'],
  ['namkeen', 'bhujia', 'snacks', 'नमकीन'],
  ['moongphali', 'mungfali', 'peanut', 'groundnut', 'मूंगफली'],
  ['kaju', 'cashew', 'काजू'],
  ['badam', 'almond', 'बादाम'],
  ['kishmish', 'raisin', 'किशमिश'],
  ['rajma', 'kidney beans', 'राजमा'],
  ['chana', 'chole', 'chickpea', 'चना'],
  ['arhar', 'toor', 'tur', 'अरहर'],
  ['moong', 'mung', 'मूंग'],
  ['masoor', 'मसूर'],
  ['urad', 'उड़द'],
  ['sabzi', 'sabji', 'vegetable', 'vegetables', 'सब्ज़ी'],
  ['phal', 'fruit', 'fruits', 'फल'],
  ['kela', 'banana', 'केला'],
  ['seb', 'apple', 'सेब'],
  ['jhadu', 'broom', 'झाड़ू'],
  ['agarbatti', 'incense', 'अगरबत्ती'],
  ['maachis', 'machis', 'matchbox', 'माचिस'],
];

final Map<String, Set<String>> _synonymIndex = () {
  final index = <String, Set<String>>{};
  for (final group in synonymGroups) {
    final words = group.map(normalizeSearch).toSet();
    for (final w in words) {
      index.putIfAbsent(w, () => <String>{}).addAll(words);
    }
  }
  return index;
}();

/// Lower-case, collapse spaces, drop punctuation. Devanagari is kept as is.
String normalizeSearch(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Every way the shopper's word could be written.
Set<String> expandTerm(String term) {
  final t = normalizeSearch(term);
  final out = <String>{t};
  _synonymIndex.forEach((word, group) {
    // "pyaaz" finds the onion group; "chawal" also matches "chawal basmati".
    if (word == t || (t.length >= 3 && word.startsWith(t))) out.addAll(group);
  });
  return out;
}

String _haystack(Product p, Catalog? catalog) {
  final cat = catalog?.category(p.categoryId);
  return normalizeSearch(
    [
      p.name,
      p.nameHi ?? '',
      p.brand ?? '',
      ...p.synonyms,
      cat?.name ?? '',
      cat?.nameHi ?? '',
      ...p.variants.map((v) => v.barcode ?? ''),
    ].join(' '),
  );
}

/// Products matching every word of the query (in any language), best first.
List<Product> searchProducts(String query, Iterable<Product> products, {Catalog? catalog}) {
  final terms = normalizeSearch(query).split(' ').where((t) => t.isNotEmpty).toList();
  if (terms.isEmpty) return const [];
  final expanded = terms.map(expandTerm).toList();

  final scored = <(Product, int)>[];
  for (final p in products) {
    final hay = _haystack(p, catalog);
    final name = normalizeSearch('${p.name} ${p.nameHi ?? ''}');
    var score = 0;
    var all = true;
    for (final options in expanded) {
      var best = 0;
      for (final o in options) {
        if (name.startsWith(o)) {
          best = 3;
        } else if (RegExp('(^| )${RegExp.escape(o)}').hasMatch(name)) {
          best = best < 2 ? 2 : best;
        } else if (hay.contains(o)) {
          best = best < 1 ? 1 : best;
        }
      }
      if (best == 0) {
        all = false;
        break;
      }
      score += best;
    }
    if (all) scored.add((p, score));
  }
  scored.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.name.compareTo(b.$1.name));
  return scored.map((e) => e.$1).toList();
}

final _sizeToken = RegExp(r'^\d+(\.\d+)?(kg|g|gm|gms|ml|l|ltr|litre|pc|pcs|x)?$');
final _noise = {'img', 'image', 'photo', 'pic', 'whatsapp', 'jpeg', 'jpg', 'png', 'webp', 'final', 'copy', 'new'};

/// Best existing product for a photo's file name ("Tata-Salt_1kg.jpg") or an
/// AI-read name ("Tata Salt"). Sizes and camera noise words are ignored. Null
/// when nothing matches every remaining word.
Product? findBestMatch(String text, Iterable<Product> products, {Catalog? catalog}) {
  final stem = text.replaceAll(RegExp(r'\.(jpe?g|png|webp|heic)$', caseSensitive: false), '');
  final words = normalizeSearch(stem.replaceAll(RegExp(r'[_\-]+'), ' '))
      .split(' ')
      .where((w) => w.length > 1 && !_sizeToken.hasMatch(w) && !_noise.contains(w) && !RegExp(r'^\d+$').hasMatch(w))
      .toList();
  if (words.isEmpty) return null;
  final hits = searchProducts(words.join(' '), products, catalog: catalog);
  return hits.isEmpty ? null : hits.first;
}
