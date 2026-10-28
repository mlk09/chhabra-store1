import 'package:intl/intl.dart';

/// Money is kept in integer paise everywhere in the app (₹1 = 100 paise),
/// so there are never floating-point rounding errors. The server uses numeric(12,2).
typedef Paise = int;

Paise paiseFromJson(Object? v) {
  if (v == null) return 0;
  if (v is int) return v * 100;
  if (v is num) return (v * 100).round();
  return ((num.tryParse(v.toString()) ?? 0) * 100).round();
}

/// For sending to the server: 12345 → 123.45
num paiseToJson(Paise p) => p % 100 == 0 ? p ~/ 100 : p / 100;

/// Parses what the shopkeeper typed ("45", "45.5", "₹1,200") → paise, or null.
Paise? parseRupees(String input) {
  final cleaned = input.replaceAll(RegExp(r'[₹,\s]'), '');
  if (cleaned.isEmpty) return null;
  final v = num.tryParse(cleaned);
  if (v == null || v < 0 || v > 10000000) return null;
  return (v * 100).round();
}

final _withPaise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _wholeRupees = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// ₹1,250 or ₹12.50 — paise are shown only when there are any.
String formatMoney(Paise p) => p % 100 == 0 ? _wholeRupees.format(p / 100) : _withPaise.format(p / 100);

/// "45.5" style text for edit fields.
String rupeesText(Paise p) => p % 100 == 0 ? '${p ~/ 100}' : (p / 100).toStringAsFixed(2);

/// Whole-number percentage off MRP, e.g. 12 for MRP ₹50 → price ₹44.
int percentOff(Paise mrp, Paise price) => mrp <= 0 || price >= mrp ? 0 : (((mrp - price) * 100) / mrp).floor();

/// Bulk price change, rounded exactly like the server's round_money():
/// 'rupee' → nearest ₹1, 'fifty' → nearest 50 paise, otherwise nearest paisa.
Paise applyPercent(Paise value, double percent, String rounding) {
  final raw = value * (1 + percent / 100);
  return switch (rounding) {
    'rupee' => (raw / 100).round() * 100,
    'fifty' => (raw / 50).round() * 50,
    _ => raw.round(),
  };
}
