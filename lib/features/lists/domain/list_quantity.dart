class ListQuantity {
  const ListQuantity._(this.thousandths);

  static const minThousandths = 1;
  static const maxThousandths = 999999999;
  static const one = ListQuantity._(1000);

  final int thousandths;

  factory ListQuantity.fromThousandths(int value) {
    if (value < minThousandths || value > maxThousandths) {
      throw const FormatException('quantity out of range');
    }
    return ListQuantity._(value);
  }

  static ListQuantity? tryParse(String input) {
    final normalized = input.trim();
    final match = RegExp(r'^(\d{1,6})(?:\.(\d{1,3}))?$').firstMatch(normalized);
    if (match == null) return null;

    final wholeDigits = match.group(1)!;
    final fractionDigits = match.group(2) ?? '';
    final whole = int.tryParse(wholeDigits);
    final fraction = int.tryParse(fractionDigits.padRight(3, '0')) ?? 0;
    if (whole == null) return null;

    final value = whole * 1000 + fraction;
    if (value < minThousandths || value > maxThousandths) return null;
    return ListQuantity._(value);
  }

  String format() {
    final whole = thousandths ~/ 1000;
    final remainder = thousandths.remainder(1000);
    if (remainder == 0) return '$whole';
    final fraction =
        remainder.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
    return '$whole.$fraction';
  }

  @override
  bool operator ==(Object other) =>
      other is ListQuantity && other.thousandths == thousandths;

  @override
  int get hashCode => thousandths.hashCode;

  @override
  String toString() => format();
}

enum ListUnit {
  piece('piece'),
  kilogram('kg'),
  gram('g'),
  litre('l'),
  millilitre('ml'),
  pack('pack'),
  box('box'),
  bottle('bottle'),
  can('can'),
  bag('bag');

  const ListUnit(this.code);

  final String code;

  static ListUnit? fromCode(String? code) {
    if (code == null) return null;
    for (final unit in values) {
      if (unit.code == code) return unit;
    }
    throw const FormatException('unknown unit code');
  }
}
