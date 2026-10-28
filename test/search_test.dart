import 'package:chhabra_store/data/demo/demo_catalog.dart';
import 'package:chhabra_store/domain/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalog = buildDemoCatalog();
  List<String> find(String q) => searchProducts(q, catalog.products, catalog: catalog).map((p) => p.name).toList();

  test('Hinglish finds English names', () {
    expect(find('aloo'), contains('Potato'));
    expect(find('cheeni'), contains('Sugar (Loose)'));
    expect(find('pyaaz'), contains('Onion'));
    expect(find('doodh'), contains('Amul Taaza Milk'));
  });

  test('English finds products, Hindi script finds products', () {
    expect(find('potato'), contains('Potato'));
    expect(find('आलू'), contains('Potato'));
    expect(find('चीनी'), contains('Sugar (Loose)'));
  });

  test('every word must match', () {
    final r = find('amul butter');
    expect(r, contains('Amul Butter'));
    expect(r, isNot(contains('Amul Taaza Milk')));
  });

  test('name starts-with ranks first', () {
    expect(find('tata').first, anyOf('Tata Salt', 'Tata Tea Gold'));
  });

  test('barcode search works', () {
    expect(find('8901725181123'), ['Aashirvaad Whole Wheat Atta']);
  });

  test('empty or junk query returns nothing', () {
    expect(find(''), isEmpty);
    expect(find('   '), isEmpty);
    expect(find('zzzzqq'), isEmpty);
  });

  test('normalisation ignores case and punctuation', () {
    expect(normalizeSearch('  Aashirvaad-ATTA!! '), 'aashirvaad atta');
  });

  group('photo file name / AI name → existing product', () {
    String? match(String text) => findBestMatch(text, catalog.products, catalog: catalog)?.name;

    test('file names from a computer or phone', () {
      expect(match('Tata Salt.jpg'), 'Tata Salt');
      expect(match('tata-salt_1kg.JPG'), 'Tata Salt');
      expect(match('parle g 250g.png'), 'Parle-G Biscuits');
      expect(match('aloo.jpeg'), 'Potato');
    });

    test('camera file names match nothing', () {
      expect(match('IMG_20261028_101522.jpg'), isNull);
      expect(match('WhatsApp Image 2026-10-28.jpeg'), isNull);
    });

    test('AI-read names find the product', () {
      expect(match('Fortune Kachi Ghani Mustard Oil'), 'Fortune Kachi Ghani Mustard Oil');
      expect(match('Amul Butter'), 'Amul Butter');
      expect(match('Kissan Mixed Fruit Jam'), isNull);
    });
  });
}
