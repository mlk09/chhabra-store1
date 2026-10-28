import 'package:chhabra_store/core/money.dart';
import 'package:chhabra_store/core/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('money', () {
    test('json numbers become exact paise', () {
      expect(paiseFromJson(62), 6200);
      expect(paiseFromJson(192.5), 19250);
      expect(paiseFromJson('44.10'), 4410);
      expect(paiseFromJson(0.1 + 0.2), 30); // no floating-point drift
      expect(paiseFromJson(null), 0);
    });

    test('paise go back to rupees for the server', () {
      expect(paiseToJson(6200), 62);
      expect(paiseToJson(19250), 192.5);
    });

    test('shopkeeper input is parsed safely', () {
      expect(parseRupees('45'), 4500);
      expect(parseRupees('₹1,200.50'), 120050);
      expect(parseRupees(''), isNull);
      expect(parseRupees('abc'), isNull);
      expect(parseRupees('-5'), isNull);
    });

    test('formatting uses Indian grouping and hides zero paise', () {
      expect(formatMoney(6200), '₹62');
      expect(formatMoney(19250), '₹192.50');
      expect(formatMoney(12345600), '₹1,23,456');
    });

    test('percent off MRP rounds down (never over-promises)', () {
      expect(percentOff(5000, 4400), 12);
      expect(percentOff(5000, 5000), 0);
      expect(percentOff(0, 100), 0);
      expect(percentOff(300, 199), 33);
    });

    test('bulk price rounding matches the server', () {
      // Same cases as supabase/tests/10_rls_core_test.sql
      expect(applyPercent(20000, 10, 'rupee'), 22000);
      expect(applyPercent(17500, 10, 'rupee'), 19300); // 192.50 → 193
      expect(applyPercent(17500, 10, 'fifty'), 19250);
      expect(applyPercent(4400, 5, 'none'), 4620);
      expect(applyPercent(10000, -5, 'rupee'), 9500);
    });
  });

  group('units', () {
    test('loose quantities read naturally', () {
      expect(formatQty(0.25, SaleUnit.kg), '250 g');
      expect(formatQty(1.5, SaleUnit.kg), '1.5 kg');
      expect(formatQty(0.5, SaleUnit.l), '500 ml');
      expect(formatQty(3, SaleUnit.pc), '3');
    });

    test('unknown unit codes fall back to piece', () {
      expect(SaleUnit.parse('kg'), SaleUnit.kg);
      expect(SaleUnit.parse('box'), SaleUnit.pc);
    });

    test('per-unit suffix only for loose items', () {
      expect(perUnitSuffix(SaleUnit.kg, loose: true), '/kg');
      expect(perUnitSuffix(SaleUnit.l, loose: true), '/L');
      expect(perUnitSuffix(SaleUnit.kg, loose: false), '');
    });
  });
}
