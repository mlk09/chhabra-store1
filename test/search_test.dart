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
}
