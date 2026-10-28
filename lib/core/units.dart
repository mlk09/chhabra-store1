/// Units a variant can be sold in. Loose items use kg / l and fractional quantity.
enum SaleUnit {
  kg('kg', 'किलो'),
  g('g', 'ग्राम'),
  l('l', 'लीटर'),
  ml('ml', 'मि.ली.'),
  pc('pc', 'पीस'),
  pack('pack', 'पैकेट'),
  dozen('dozen', 'दर्जन');

  const SaleUnit(this.code, this.hindi);
  final String code;
  final String hindi;

  static SaleUnit parse(String? code) => values.firstWhere((u) => u.code == code, orElse: () => SaleUnit.pc);

  /// Units that make sense for loose (weighed / measured) items.
  bool get isMeasured => this == kg || this == l;
}

String _trim(num v) {
  final s = v.toStringAsFixed(3);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Human quantity: 0.25 kg → "250 g", 1.5 l → "1.5 L", 3 pc → "3".
String formatQty(num qty, SaleUnit unit) {
  switch (unit) {
    case SaleUnit.kg:
      return qty < 1 ? '${_trim(qty * 1000)} g' : '${_trim(qty)} kg';
    case SaleUnit.l:
      return qty < 1 ? '${_trim(qty * 1000)} ml' : '${_trim(qty)} L';
    case SaleUnit.g:
      return '${_trim(qty)} g';
    case SaleUnit.ml:
      return '${_trim(qty)} ml';
    case SaleUnit.dozen:
      return '${_trim(qty)} dozen';
    case SaleUnit.pc:
    case SaleUnit.pack:
      return _trim(qty);
  }
}

/// Price label for a variant: "/kg" for loose items, nothing for packets.
String perUnitSuffix(SaleUnit unit, {required bool loose}) => loose ? '/${unit == SaleUnit.l ? 'L' : unit.code}' : '';
